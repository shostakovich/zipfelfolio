defmodule Zipfelfolio.MarketData.YahooTest do
  use ExUnit.Case, async: true

  alias Zipfelfolio.MarketData.Yahoo

  @body File.read!("test/fixtures/yahoo/chart.json")

  # 2026-10-09 is still trading in the fixture until 17:30 CEST.
  @during_trading ~U[2026-10-09 10:00:00Z]
  @after_close ~U[2026-10-09 16:00:00Z]

  test "reads the currency, the closes per trading day and the latest quote" do
    assert {:ok, chart} = Yahoo.parse(@body, @after_close)

    assert chart.currency == "EUR"

    assert chart.closes == [
             {~D[2026-10-05], 16_704_000_000},
             {~D[2026-10-06], 16_768_000_000},
             {~D[2026-10-07], 16_702_000_000},
             {~D[2026-10-09], 16_666_000_000}
           ]

    assert chart.quote == %{
             at: ~U[2026-10-09 08:23:24.000000Z],
             date: ~D[2026-10-09],
             close: 16_666_000_000
           }
  end

  test "names pence and cents as ISO 4217 does" do
    for {yahoo, iso} <- [{"GBp", "GBX"}, {"ZAc", "ZAC"}, {"ILA", "ILA"}, {"GBP", "GBP"}] do
      body =
        @body
        |> JSON.decode!()
        |> put_in(["chart", "result", Access.at(0), "meta", "currency"], yahoo)
        |> JSON.encode!()

      assert {:ok, %{currency: ^iso}} = Yahoo.parse(body, @after_close)
    end
  end

  test "leaves out closes of 0" do
    body =
      @body
      |> JSON.decode!()
      |> update_in(
        ["chart", "result", Access.at(0), "indicators", "quote", Access.at(0), "close"],
        fn [_, _ | rest] -> [0, 0.0 | rest] end
      )
      |> JSON.encode!()

    assert {:ok, %{closes: closes}} = Yahoo.parse(body, @after_close)
    assert Enum.map(closes, &elem(&1, 0)) == [~D[2026-10-07], ~D[2026-10-09]]
  end

  test "leaves out the day that is still trading" do
    assert {:ok, chart} = Yahoo.parse(@body, @during_trading)

    assert List.last(chart.closes) == {~D[2026-10-07], 16_702_000_000}
  end

  test "a range without trading days has no closes" do
    body =
      @body
      |> JSON.decode!()
      |> update_in(["chart", "result", Access.at(0)], &Map.drop(&1, ["timestamp"]))
      |> update_in(
        ["chart", "result", Access.at(0), "indicators", "quote", Access.at(0)],
        &Map.delete(&1, "close")
      )
      |> JSON.encode!()

    assert {:ok, %{closes: []}} = Yahoo.parse(body, @after_close)
  end

  test "a candle at local midnight keeps its day across daylight saving time" do
    # 2026-07-15 00:00 CEST, read with the winter offset of a response from January.
    midnight = DateTime.to_unix(~U[2026-07-14 22:00:00Z])

    body =
      @body
      |> JSON.decode!()
      |> put_in(["chart", "result", Access.at(0), "timestamp"], [midnight])
      |> put_in(["chart", "result", Access.at(0), "meta", "gmtoffset"], 3600)
      |> put_in(["chart", "result", Access.at(0), "indicators", "quote", Access.at(0), "close"], [
        1.5
      ])
      |> JSON.encode!()

    assert {:ok, %{closes: [{~D[2026-07-15], 150_000_000}]}} = Yahoo.parse(body, @after_close)
  end

  test "an unexpected body is reported as such" do
    assert Yahoo.parse("<html>", @after_close) == {:error, :invalid_response}

    assert Yahoo.parse(~s({"chart": {"result": null}}), @after_close) ==
             {:error, :invalid_response}
  end
end
