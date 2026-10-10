defmodule Zipfelfolio.PerformanceTest do
  use ExUnit.Case, async: true

  import Zipfelfolio.PortfoliosFixtures, only: [money: 1, shares: 1]
  import Zipfelfolio.SecuritiesFixtures, only: [price: 1]

  alias Zipfelfolio.Performance
  alias Zipfelfolio.Performance.IRR
  alias Zipfelfolio.Portfolios.{Account, Portfolio, Transaction}
  alias Zipfelfolio.Securities.Security
  alias Zipfelfolio.Valuation.{Filter, Market}

  @thursday ~D[2026-10-01]
  @friday ~D[2026-10-02]
  @saturday ~D[2026-10-03]
  @days Date.range(@thursday, @saturday)

  # Portfolio 1 settles against account 10 (EUR); account 11 is in USD; security 20 is in EUR.
  @accounts [%Account{id: 10, currency: "EUR"}, %Account{id: 11, currency: "USD"}]
  @portfolio %Portfolio{id: 1, reference_account_id: 10}

  defp transaction(type, date, attrs) do
    struct!(
      %Transaction{
        type: type,
        date_time: NaiveDateTime.new!(date, ~T[12:00:00]),
        amount: 0,
        currency: "EUR",
        units: []
      },
      attrs
    )
  end

  defp market(closes, rates \\ []),
    do: Market.new([%Security{id: 20, currency: "EUR"}], closes, rates)

  defp day(date, value, attrs \\ []),
    do: Map.merge(%{date: date, value: value, inbound: 0, outbound: 0}, Map.new(attrs))

  defp index(days, cash_flows \\ []), do: %Performance{days: days, cash_flows: cash_flows}

  describe "ttwror/1" do
    test "chains the days, money coming in at the start of a day and going out at its end" do
      days = [
        day(@thursday, money(1_000)),
        day(@friday, money(1_100)),
        day(@saturday, money(1_650), inbound: money(500)),
        day(~D[2026-10-04], money(1_500), outbound: money(200))
      ]

      assert_in_delta Performance.ttwror(index(days)),
                      1.1 * (1_650 / 1_600) * (1_700 / 1_650) - 1,
                      1.0e-12
    end

    test "returns 0 on a day with neither value before it nor money coming in" do
      days = [day(@thursday, 0), day(@friday, money(100)), day(@saturday, money(110))]

      assert_in_delta Performance.ttwror(index(days)), 0.1, 1.0e-12
    end

    test "starts from the reference day's value, whatever came in that day" do
      days = [day(@thursday, money(1_000), inbound: money(1_000)), day(@friday, money(1_100))]

      assert_in_delta Performance.ttwror(index(days)), 0.1, 1.0e-12
    end
  end

  describe "irr/1" do
    test "pays in the reference day's value and the money in after it, and gets the last day's" do
      days = [day(~D[2025-01-01], money(1_000)), day(~D[2026-01-01], money(1_650))]
      cash_flows = [{~D[2025-07-02], -500.0}, {~D[2025-10-01], 20.0}]

      assert Performance.irr(index(days, cash_flows)) ==
               IRR.calculate([
                 {~D[2025-01-01], -1_000.0},
                 {~D[2025-07-02], -500.0},
                 {~D[2025-10-01], 20.0},
                 {~D[2026-01-01], 1_650.0}
               ])
    end

    test "leaves out a value of nothing" do
      days = [day(~D[2025-01-01], 0), day(~D[2026-01-01], money(1_100))]

      assert_in_delta Performance.irr(index(days, [{~D[2025-01-01], -1_000.0}])), 0.1, 1.0e-9
    end

    test "is nothing without any value or money in or out" do
      assert Performance.irr(index([day(@thursday, 0), day(@friday, 0)])) == 0.0
    end
  end

  describe "index/5" do
    # 1,000 € deposited on Thursday buy 10 shares at 100 € on Friday; on Saturday they close at
    # 105 €, 500 € more come in and a dividend of 20 € is paid.
    setup do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        transaction(:buy, @friday,
          portfolio_id: 1,
          account_id: 10,
          security_id: 20,
          shares: shares(10),
          amount: money(1_000)
        ),
        transaction(:deposit, @saturday, account_id: 10, amount: money(500)),
        transaction(:dividend, @saturday, account_id: 10, security_id: 20, amount: money(20))
      ]

      %{
        transactions: transactions,
        market: market([{20, @friday, price(100)}, {20, @saturday, price(105)}])
      }
    end

    test "values every day and counts the money in and out per day", ctx do
      index = Performance.index(ctx.transactions, @accounts, ctx.market, Filter.all(), @days)

      assert Enum.map(index.days, &Map.take(&1, [:date, :value, :inbound, :outbound])) == [
               day(@thursday, money(1_000), inbound: money(1_000)),
               day(@friday, money(1_000)),
               day(@saturday, money(1_570), inbound: money(500))
             ]

      assert Enum.map(index.days, & &1.invested_capital) == [
               money(1_000),
               money(1_000),
               money(1_500)
             ]

      assert index.cash_flows == [{@saturday, -500.0}]
      assert_in_delta Performance.ttwror(index), 1_570 / 1_500 - 1, 1.0e-12
    end

    test "counts a portfolio's dividends with or without its reference account", ctx do
      days = Date.range(@friday, @saturday)

      for {account_ids, ttwror} <- [{[10], 1_570 / 1_500 - 1}, {[], (1_050 + 20) / 1_000 - 1}] do
        filter = Filter.new([@portfolio], account_ids, ctx.transactions)
        index = Performance.index(ctx.transactions, @accounts, ctx.market, filter, days)

        assert_in_delta Performance.ttwror(index), ttwror, 1.0e-12
      end
    end

    test "converts the money in and out at the ECB rate of its day" do
      transactions = [
        transaction(:deposit, @friday, account_id: 11, currency: "USD", amount: money(110)),
        transaction(:removal, @saturday, account_id: 11, currency: "USD", amount: money(50))
      ]

      market =
        market([], [
          {"USD", @friday, Decimal.new("1.10")},
          {"USD", @saturday, Decimal.new("1.25")}
        ])

      index = Performance.index(transactions, @accounts, market, Filter.all(), @days)

      assert Enum.map(index.days, &{&1.inbound, &1.outbound}) ==
               [{0, 0}, {money(100), 0}, {0, money(40)}]

      assert index.cash_flows == [{@friday, -100.0}, {@saturday, 40.0}]
    end

    test "counts both sides of a transfer inside for the IRR only" do
      transfer =
        transaction(:cash_transfer, @friday,
          account_id: 10,
          other_account_id: 10,
          amount: money(5)
        )

      index = Performance.index([transfer], @accounts, market([]), Filter.all(), @days)

      assert Enum.map(index.days, &{&1.inbound, &1.outbound}) == [{0, 0}, {0, 0}, {0, 0}]
      assert index.cash_flows == [{@friday, 5.0}, {@friday, -5.0}]
    end
  end
end
