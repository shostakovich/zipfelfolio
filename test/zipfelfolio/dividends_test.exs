defmodule Zipfelfolio.DividendsTest do
  use ExUnit.Case, async: true

  import Zipfelfolio.PortfoliosFixtures, only: [money: 1, shares: 1]

  alias Zipfelfolio.Dividends
  alias Zipfelfolio.Portfolios.{Transaction, TransactionUnit}
  alias Zipfelfolio.Securities.Security
  alias Zipfelfolio.Valuation.Market

  @fund %Security{id: 1, name: "All-World", currency: "EUR"}
  @dollar_fund %Security{id: 2, name: "Quality", currency: "USD"}
  @market Market.new([@fund, @dollar_fund], [], [])

  defp dividend(date, net, attrs \\ []) do
    struct!(
      %Transaction{
        type: :dividend,
        date_time: NaiveDateTime.new!(date, ~T[09:00:00]),
        account_id: 10,
        security_id: @fund.id,
        shares: shares(10),
        amount: money(net),
        currency: "EUR",
        units: []
      },
      attrs
    )
  end

  defp unit(type, amount, currency \\ "EUR"),
    do: %TransactionUnit{type: type, amount: money(amount), currency: currency}

  describe "received/2" do
    test "gives each dividend with gross, taxes, fees and net, newest first" do
      older = dividend(~D[2026-03-31], 10)
      newer = dividend(~D[2026-09-30], 15, units: [unit(:tax, 4.5), unit(:fee, 0.5)])

      assert Dividends.received([older, newer], @market) == [
               %{
                 date: ~D[2026-09-30],
                 security: @fund,
                 shares: shares(10),
                 gross: money(20),
                 taxes: money(4.5),
                 fees: money(0.5),
                 net: money(15)
               },
               %{
                 date: ~D[2026-03-31],
                 security: @fund,
                 shares: shares(10),
                 gross: money(10),
                 taxes: 0,
                 fees: 0,
                 net: money(10)
               }
             ]
    end

    test "counts only dividends, not interest" do
      interest = %{dividend(~D[2026-09-30], 7) | type: :interest, security_id: nil}

      assert Dividends.received([interest, dividend(~D[2026-09-30], 5)], @market)
             |> Enum.map(& &1.net) == [money(5)]
    end

    test "converts each amount at the ECB rate of the pay date" do
      market =
        Market.new([@fund, @dollar_fund], [], [
          {"USD", ~D[2026-09-29], Decimal.new("1.10")},
          {"USD", ~D[2026-09-30], Decimal.new("1.25")}
        ])

      dividend =
        dividend(~D[2026-09-30], 20,
          security_id: @dollar_fund.id,
          currency: "USD",
          units: [unit(:tax, 5, "USD")]
        )

      assert [%{gross: gross, taxes: taxes, net: net}] = Dividends.received([dividend], market)
      assert {gross, taxes, net} == {money(20), money(4), money(16)}
    end

    test "takes a dividend without shares as zero shares" do
      assert [%{shares: 0}] =
               Dividends.received([dividend(~D[2026-09-30], 5, shares: nil)], @market)
    end
  end

  describe "by_year/2" do
    test "adds up gross and net per month and year, newest year first" do
      received =
        Dividends.received(
          [
            dividend(~D[2025-03-31], 8, units: [unit(:tax, 2)]),
            dividend(~D[2026-03-02], 9, units: [unit(:tax, 1)]),
            dividend(~D[2026-03-31], 5),
            dividend(~D[2026-09-30], 4)
          ],
          @market
        )

      assert [this_year, last_year] = Dividends.by_year(received, ~D[2026-10-10])

      assert this_year.year == 2026
      assert Enum.at(this_year.months, 2) == %{gross: money(15), net: money(14)}
      assert Enum.at(this_year.months, 8) == %{gross: money(4), net: money(4)}
      assert Enum.at(this_year.months, 0) == %{gross: 0, net: 0}
      assert length(this_year.months) == 12
      assert {this_year.gross, this_year.net} == {money(19), money(18)}

      assert last_year.year == 2025
      assert {last_year.gross, last_year.net} == {money(10), money(8)}
    end

    test "lists every year from the first dividend to this year, those without any at zero" do
      received = Dividends.received([dividend(~D[2023-06-30], 5)], @market)

      assert Dividends.by_year(received, ~D[2026-10-10])
             |> Enum.map(&{&1.year, &1.net}) == [
               {2026, 0},
               {2025, 0},
               {2024, 0},
               {2023, money(5)}
             ]
    end

    test "is empty without dividends" do
      assert Dividends.by_year([], ~D[2026-10-10]) == []
    end
  end

  describe "total/2" do
    test "adds up gross and net of the dividends paid in the range" do
      received =
        Dividends.received(
          [
            dividend(~D[2025-12-31], 3),
            dividend(~D[2026-01-01], 8, units: [unit(:tax, 2)]),
            dividend(~D[2026-10-10], 5),
            dividend(~D[2026-10-11], 7)
          ],
          @market
        )

      assert Dividends.total(received, Date.range(~D[2026-01-01], ~D[2026-10-10])) ==
               %{gross: money(15), net: money(13)}
    end
  end
end
