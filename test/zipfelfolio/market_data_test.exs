defmodule Zipfelfolio.MarketDataTest do
  use Zipfelfolio.DataCase

  import Zipfelfolio.SecuritiesFixtures

  alias Zipfelfolio.{ExchangeRates, FakePriceFeed, FakeRateSource, MarketData}
  alias Zipfelfolio.Securities.Security

  @now ~U[2026-10-09 16:00:00.000000Z]

  defp usd(date, rate), do: {"USD", date, Decimal.new(rate)}

  describe "run_daily/1" do
    test "stores rates and prices; the next run fetches from the last stored day on" do
      security = security_fixture()
      FakeRateSource.stub(fn _from -> {:ok, [usd(~D[2026-10-08], "1.1186")]} end)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}])}
      end)

      MarketData.run_daily(@now)

      assert_received {:rates, ~D[1999-01-04]}
      assert_received {:chart, "VGWL.DE", nil}
      assert ExchangeRates.rate_on("USD", ~D[2026-10-09]) == Decimal.new("1.1186")
      assert prices_of(security) == [{~D[2026-10-08], 100, :yahoo}]

      security = Repo.reload!(security)
      assert {security.latest_close, security.latest_date} == {16_666_000_000, ~D[2026-10-09]}
      assert {security.fetched_at, security.fetch_error} == {@now, nil}
      assert MarketData.last_run().ran_at == @now

      MarketData.run_daily(@now)

      assert_received {:rates, ~D[2026-10-08]}
      assert_received {:chart, "VGWL.DE", ~D[2026-10-08]}
    end

    test "PP and manual prices win over Yahoo" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-05], 100, :pp)
      price_fixture(security, ~D[2026-10-06], 200, :manual)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-05], 1}, {~D[2026-10-06], 2}])}
      end)

      MarketData.run_daily(@now)

      assert prices_of(security) == [{~D[2026-10-05], 100, :pp}, {~D[2026-10-06], 200, :manual}]
    end

    test "a quote in another currency stores nothing and records the mismatch" do
      security = security_fixture(symbol: "LDGL.L")

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}], 1, "USD")}
      end)

      MarketData.run_daily(@now)

      assert prices_of(security) == []
      security = Repo.reload!(security)
      assert security.fetch_error == "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR."
      assert {security.latest_close, security.fetched_at} == {nil, nil}
    end

    test "fetches neither manual nor retired securities" do
      security_fixture(quote_feed: :manual, symbol: nil)
      security_fixture(retired: true)
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([])} end)

      MarketData.run_daily(@now)

      refute_received {:chart, _symbol, _from}
    end

    test "a failing source is recorded, the other one still runs" do
      security = security_fixture(fetched_at: ~U[2026-10-08 16:00:00.000000Z])
      FakeRateSource.stub(fn _from -> {:error, {:http_status, 503}} end)
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :not_found} end)

      MarketData.run_daily(@now)

      assert MarketData.last_run().error == "Die EZB antwortet mit HTTP 503."
      security = Repo.reload!(security)
      assert security.fetch_error == "Yahoo kennt das Symbol VGWL.DE nicht."
      assert security.fetched_at == ~U[2026-10-08 16:00:00.000000Z]
    end

    test "stores nothing a fetch delivered for a symbol changed meanwhile" do
      security = security_fixture()

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        security |> Ecto.Changeset.change(symbol: "VWRL.AS") |> Repo.update!()
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}])}
      end)

      MarketData.run_daily(@now)

      assert prices_of(security) == []
      assert %Security{latest_close: nil, fetched_at: nil} = Repo.reload!(security)
    end

    test "an exception is recorded and does not stop the other securities" do
      broken = security_fixture(symbol: "BROKEN.DE")
      fine = security_fixture(symbol: "FINE.DE")
      FakeRateSource.stub(fn _from -> raise "ECB parser exploded" end)

      FakePriceFeed.stub(fn
        "BROKEN.DE", _from, _now -> raise "chart exploded"
        _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}])}
      end)

      ExUnit.CaptureLog.capture_log(fn -> MarketData.run_daily(@now) end)

      assert MarketData.last_run().error ==
               "Die Wechselkurse ließen sich nicht speichern: ECB parser exploded"

      assert Repo.reload!(broken).fetch_error ==
               "Die Kurse ließen sich nicht speichern: chart exploded"

      assert prices_of(fine) == [{~D[2026-10-08], 100, :yahoo}]
    end

    test "never asks for prices after today" do
      security = security_fixture()
      price_fixture(security, ~D[2026-12-24], 100, :manual)
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([])} end)

      MarketData.run_daily(@now)

      assert_received {:chart, "VGWL.DE", ~D[2026-10-09]}
    end

    test "tells subscribers about the update" do
      MarketData.subscribe()

      MarketData.run_daily(@now)

      assert_received :market_data_updated
    end
  end

  describe "refresh_stale_quotes/1" do
    test "refreshes quotes older than 15 minutes in the background, without storing prices" do
      stale = security_fixture(checked_at: ~U[2026-10-09 15:44:59.000000Z])
      _fresh = security_fixture(symbol: "LDGL.DE", checked_at: ~U[2026-10-09 15:46:00.000000Z])

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}], 42)}
      end)

      MarketData.subscribe()

      MarketData.refresh_stale_quotes(@now)

      assert_receive :market_data_updated
      assert_received {:chart, "VGWL.DE", ~D[2026-10-09]}
      refute_received {:chart, "LDGL.DE", _from}
      assert %Security{latest_close: 42, fetched_at: @now} = Repo.reload!(stale)
      assert prices_of(stale) == []
    end

    test "a failed check counts as a check, so pages opened together fetch once" do
      security = security_fixture()
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :unreachable} end)
      MarketData.subscribe()

      MarketData.refresh_stale_quotes(@now)
      MarketData.refresh_stale_quotes(@now)

      assert_receive :market_data_updated
      assert_received {:chart, "VGWL.DE", _from}
      refute_receive {:chart, "VGWL.DE", _from}, 50

      assert %Security{checked_at: @now, fetch_error: "Yahoo ist nicht erreichbar."} =
               Repo.reload!(security)
    end

    test "does nothing when every quote is fresh" do
      security_fixture(checked_at: ~U[2026-10-09 15:50:00.000000Z])
      MarketData.subscribe()

      assert MarketData.refresh_stale_quotes(@now) == :ok

      refute_receive :market_data_updated, 50
    end
  end

  describe "fetch_in_background/2" do
    test "fetches the whole history and tells subscribers" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-01], 100, :pp)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2017-10-26], 50}])}
      end)

      MarketData.subscribe()

      MarketData.fetch_in_background(security)

      assert_receive :market_data_updated
      assert_received {:chart, "VGWL.DE", nil}
      assert {~D[2017-10-26], 50, :yahoo} in prices_of(security)
    end
  end
end
