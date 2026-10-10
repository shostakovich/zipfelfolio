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

  describe "ttwror_per_year/1" do
    test "spreads the TTWROR over years of 365 days, as PP annualises it" do
      days = [day(~D[2024-01-01], money(1_000)), day(~D[2025-07-01], money(1_210))]

      assert_in_delta Performance.ttwror_per_year(index(days)),
                      :math.pow(1.21, 365 / 547) - 1,
                      1.0e-12
    end

    test "is nil after a loss of more than everything" do
      days = [day(~D[2025-01-01], money(1_000)), day(~D[2026-01-01], money(-500))]

      assert Performance.ttwror_per_year(index(days)) == nil
    end

    test "is a loss of everything after one" do
      days = [day(~D[2025-01-01], money(1_000)), day(~D[2026-01-01], 0)]

      assert Performance.ttwror_per_year(index(days)) == -1.0
    end
  end

  describe "drawdown/1" do
    test "is the largest fall of the accumulated TTWROR from a peak, with its days" do
      days = [
        day(~D[2026-09-01], money(1_000)),
        day(~D[2026-09-02], money(1_100)),
        day(~D[2026-09-03], money(990)),
        day(~D[2026-09-04], money(1_045)),
        day(~D[2026-09-05], money(1_210)),
        day(~D[2026-09-06], money(1_150))
      ]

      assert %{max: max, from: ~D[2026-09-02], to: ~D[2026-09-03]} =
               Performance.drawdown(index(days))

      assert_in_delta max, 0.1, 1.0e-12
    end

    test "is not a fall that money taken out causes" do
      days = [day(@thursday, money(1_000)), day(@friday, money(500), outbound: money(500))]

      assert Performance.drawdown(index(days)) == %{max: 0.0, from: @thursday, to: @thursday}
    end

    test "starts on the first day with a value" do
      days = [
        day(@thursday, 0),
        day(@friday, money(1_000), inbound: money(1_000)),
        day(@saturday, money(900))
      ]

      assert %{from: @friday, to: @saturday} = Performance.drawdown(index(days))
    end

    test "has nothing to fall from while the peak is a loss of everything" do
      days = [
        day(@thursday, 0),
        day(@friday, money(-500), inbound: money(1_000), outbound: money(500)),
        day(@saturday, money(-500)),
        day(~D[2026-10-04], money(-400))
      ]

      assert Performance.drawdown(index(days)) == %{max: 0.0, from: @friday, to: @friday}
    end
  end

  describe "volatility/1" do
    test "is the standard deviation of the daily log returns, scaled to their number" do
      # Monday 5 October to Friday 9 October 2026.
      values = [1_000, 1_010, 1_005, 1_030, 1_020]

      days =
        for {value, i} <- Enum.with_index(values),
            do: day(Date.add(~D[2026-10-05], i), money(value))

      returns =
        values |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> :math.log(b / a) end)

      mean = Enum.sum(returns) / 4
      variance = Enum.sum(Enum.map(returns, &((&1 - mean) ** 2))) / 3

      assert_in_delta Performance.volatility(index(days)), :math.sqrt(variance * 4), 1.0e-12
    end

    test "leaves out the first day, days without value and weekends and holidays" do
      # Christmas Eve 2026 is a Thursday, so only the 23rd and the 28th count.
      days =
        [
          day(~D[2026-12-21], 0),
          day(~D[2026-12-22], money(1_000), inbound: money(1_000)),
          day(~D[2026-12-23], money(1_100)),
          day(~D[2026-12-24], money(500)),
          day(~D[2026-12-25], money(2_000)),
          day(~D[2026-12-26], money(2_000)),
          day(~D[2026-12-27], money(1_000)),
          day(~D[2026-12-28], money(1_210))
        ]

      returns = [:math.log(1.1), :math.log(1.21)]
      mean = Enum.sum(returns) / 2
      variance = Enum.sum(Enum.map(returns, &((&1 - mean) ** 2))) / 1

      assert_in_delta Performance.volatility(index(days)), :math.sqrt(variance * 2), 1.0e-12
    end

    test "leaves out losses of everything or more" do
      # Monday 5 October to Friday 9 October 2026.
      days = [
        day(~D[2026-10-05], money(1_000)),
        day(~D[2026-10-06], money(1_100)),
        day(~D[2026-10-07], money(-100)),
        day(~D[2026-10-08], money(-110)),
        day(~D[2026-10-09], money(-132))
      ]

      returns = [:math.log(1.1), :math.log(1.1), :math.log(1.2)]
      mean = Enum.sum(returns) / 3
      variance = Enum.sum(Enum.map(returns, &((&1 - mean) ** 2))) / 2

      assert_in_delta Performance.volatility(index(days)), :math.sqrt(variance * 3), 1.0e-12
    end

    test "is 0 with less than two returns" do
      assert Performance.volatility(index([day(@thursday, money(1)), day(@friday, money(2))])) ==
               0.0
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
