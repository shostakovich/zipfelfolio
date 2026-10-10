defmodule ZipfelfolioWeb.SecuritiesLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures}

  alias Zipfelfolio.{ExchangeRates, FakePriceFeed, LocalTime, MarketData, Repo}

  setup :register_and_log_in_user

  defp fresh, do: DateTime.utc_now()

  # Background fetches tell the page over PubSub; once their task is gone, the message is there.
  defp await_background_fetches do
    for pid <- Task.Supervisor.children(Zipfelfolio.TaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  defp save_feed(lv, security, feed, symbol) do
    lv
    |> form("#feed-#{security.id}", feed: %{quote_feed: feed, symbol: symbol})
    |> render_submit()
  end

  test "lists the securities with feed, latest quote and fetch status", %{conn: conn} do
    security_fixture(
      latest_close: 16_666_000_000,
      latest_date: ~D[2026-10-09],
      fetched_at: fresh(),
      checked_at: fresh()
    )

    security_fixture(
      name: "L&G Gerd Kommer",
      symbol: "LDGL.L",
      fetch_error: "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR.",
      fetched_at: fresh(),
      checked_at: fresh()
    )

    security_fixture(
      name: "iShares Dividend",
      retired: true,
      fetched_at: fresh(),
      checked_at: fresh()
    )

    {:ok, lv, html} = live(conn, ~p"/settings/securities")

    assert html =~ "Vanguard FTSE All-World"
    assert html =~ "166,66 EUR"
    assert html =~ "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR."
    assert lv |> element("#retired") |> render() =~ "iShares Dividend"
  end

  test "is linked from the settings", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert {:ok, _lv, html} =
             lv
             |> element("#securities a", "Kursquellen und Kurse")
             |> render_click()
             |> follow_redirect(conn)

    assert html =~ "Wertpapiere"
  end

  test "shows until when exchange rates are stored and the last error", %{conn: conn} do
    ExchangeRates.store([{"USD", ~D[2026-10-08], Decimal.new("1.1186")}])

    Repo.insert!(%MarketData.JobRun{
      name: "daily",
      ran_at: fresh(),
      error: "Die EZB ist nicht erreichbar."
    })

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")

    rates = lv |> element("#exchange-rates") |> render()
    assert rates =~ "08.10.2026"
    assert rates =~ "Die EZB ist nicht erreichbar."
  end

  test "opening the page refreshes stale quotes, not fresh ones", %{conn: conn} do
    stale = security_fixture(latest_close: 100)
    security_fixture(symbol: "LDGL.DE", fetched_at: fresh(), checked_at: fresh())

    FakePriceFeed.stub(fn _symbol, _from, _now ->
      {:ok, FakePriceFeed.chart_result([], 17_012_000_000)}
    end)

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")
    await_background_fetches()

    assert_received {:chart, "VGWL.DE", _today}
    refute_received {:chart, "LDGL.DE", _today}
    assert lv |> element("#security-#{stale.id}") |> render() =~ "170,12 EUR"
  end

  test "a new symbol drops the old Yahoo prices and fetches the whole history", %{conn: conn} do
    security = security_fixture(fetched_at: fresh(), checked_at: fresh())
    price_fixture(security, ~D[2026-10-05], 100, :pp)
    price_fixture(security, ~D[2026-10-06], 200, :manual)
    price_fixture(security, ~D[2026-10-07], 300, :yahoo)

    FakePriceFeed.stub(fn _symbol, _from, _now ->
      {:ok, FakePriceFeed.chart_result([{~D[2017-10-26], 50}])}
    end)

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")
    assert save_feed(lv, security, "yahoo", "VWRL.AS") =~ "Kursquelle gespeichert."
    await_background_fetches()

    assert_received {:chart, "VWRL.AS", nil}

    assert prices_of(security) == [
             {~D[2017-10-26], 50, :yahoo},
             {~D[2026-10-05], 100, :pp},
             {~D[2026-10-06], 200, :manual}
           ]
  end

  test "switching to manual keeps the Yahoo prices and fetches nothing", %{conn: conn} do
    security = security_fixture(fetched_at: fresh(), checked_at: fresh())
    price_fixture(security, ~D[2026-10-07], 300, :yahoo)
    FakePriceFeed.stub(fn _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([])} end)

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")
    save_feed(lv, security, "manual", "")
    await_background_fetches()

    refute_received {:chart, _symbol, _from}
    assert prices_of(security) == [{~D[2026-10-07], 300, :yahoo}]
    assert Repo.reload!(security).quote_feed == :manual
  end

  test "Yahoo needs a symbol", %{conn: conn} do
    security = security_fixture(fetched_at: fresh(), checked_at: fresh())

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")

    assert save_feed(lv, security, "yahoo", "") =~ "muss ausgefüllt werden"
    assert Repo.reload!(security).symbol == "VGWL.DE"
  end

  test "enters and deletes a manual price", %{conn: conn} do
    security = security_fixture(quote_feed: :manual, symbol: nil)

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")

    html =
      lv
      |> form("#manual-price-#{security.id}", price: %{date: "2026-10-07", close: "166,50"})
      |> render_submit()

    assert html =~ "Kurs eingetragen."
    assert [{~D[2026-10-07], 16_650_000_000, :manual}] = prices_of(security)
    assert lv |> element("#security-#{security.id}") |> render() =~ "07.10.2026"

    lv |> element("#security-#{security.id} button", "Löschen") |> render_click()

    assert prices_of(security) == []
  end

  test "entering or deleting a manual price updates the sidebar", %{conn: conn, scope: scope} do
    security = security_fixture(quote_feed: :manual, symbol: nil)
    today = LocalTime.today()
    price_fixture(security, Date.add(today, -1), price(100), :pp)
    portfolio = portfolio_fixture(scope)

    transaction_fixture(scope, Date.add(today, -1),
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(10)
    )

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")
    assert lv |> element("#side-portfolio-#{portfolio.id}") |> render() =~ "1.000,00"

    lv
    |> form("#manual-price-#{security.id}", price: %{date: Date.to_iso8601(today), close: "120"})
    |> render_submit()

    assert lv |> element("#side-portfolio-#{portfolio.id}") |> render() =~ "1.200,00"

    lv |> element("#security-#{security.id} button", "Löschen") |> render_click()

    assert lv |> element("#side-portfolio-#{portfolio.id}") |> render() =~ "1.000,00"
  end

  test "deleting a manual price lets Yahoo fill that day again", %{conn: conn} do
    security = security_fixture(fetched_at: fresh(), checked_at: fresh())
    price_fixture(security, ~D[2026-10-07], 200, :manual)
    price_fixture(security, ~D[2026-10-08], 300, :yahoo)

    FakePriceFeed.stub(fn _symbol, _from, _now ->
      {:ok, FakePriceFeed.chart_result([{~D[2026-10-07], 199}])}
    end)

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")
    lv |> element("#security-#{security.id} button", "Löschen") |> render_click()
    await_background_fetches()

    assert_received {:chart, "VGWL.DE", ~D[2026-10-07]}
    assert prices_of(security) == [{~D[2026-10-07], 199, :yahoo}, {~D[2026-10-08], 300, :yahoo}]
  end

  test "explains why a manual price was refused", %{conn: conn} do
    security = security_fixture(quote_feed: :manual, symbol: nil)
    price_fixture(security, ~D[2026-10-05], 100, :pp)

    {:ok, lv, _html} = live(conn, ~p"/settings/securities")

    html =
      lv
      |> form("#manual-price-#{security.id}", price: %{date: "2026-10-05", close: "1"})
      |> render_submit()

    assert html =~ "hat schon einen Kurs aus Portfolio Performance"
  end
end
