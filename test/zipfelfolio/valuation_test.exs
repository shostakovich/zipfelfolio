defmodule Zipfelfolio.ValuationTest do
  use ExUnit.Case, async: true

  import Zipfelfolio.PortfoliosFixtures, only: [money: 1, shares: 1]
  import Zipfelfolio.SecuritiesFixtures, only: [price: 1]

  alias Zipfelfolio.Portfolios.{Account, Transaction, TransactionUnit}
  alias Zipfelfolio.Securities.Security
  alias Zipfelfolio.Valuation
  alias Zipfelfolio.Valuation.{Holding, Market}

  @thursday ~D[2026-10-01]
  @friday ~D[2026-10-02]
  @saturday ~D[2026-10-03]

  # Portfolios 1 and 2, accounts 10 (EUR) and 11 (USD), securities 20 (EUR) and 21 (USD).
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

  defp in_portfolio(type, date, portfolio_id, security_id, count, attrs \\ []) do
    transaction(
      type,
      date,
      [portfolio_id: portfolio_id, security_id: security_id, shares: shares(count)] ++ attrs
    )
  end

  defp market(closes, opts \\ []) do
    securities = [
      %Security{
        id: 20,
        currency: "EUR",
        latest_date: opts[:quote_date],
        latest_close: opts[:quote]
      },
      %Security{id: 21, currency: "USD"}
    ]

    Market.new(securities, closes, opts[:rates] || [])
  end

  defp holding(security_id, count, transactions \\ []) do
    %Holding{
      portfolio_id: 1,
      security_id: security_id,
      shares: shares(count),
      transactions: transactions
    }
  end

  defp shares_per_holding(holdings),
    do: holdings |> Enum.map(&{&1.portfolio_id, &1.security_id, &1.shares}) |> Enum.sort()

  describe "holdings/2" do
    test "a purchase adds shares and a sale removes them" do
      buy = in_portfolio(:buy, @thursday, 1, 20, 10, account_id: 10)
      sell = in_portfolio(:sell, @friday, 1, 20, 4, account_id: 10)

      assert Valuation.holdings([buy, sell], @friday) == [
               %Holding{
                 portfolio_id: 1,
                 security_id: 20,
                 shares: shares(6),
                 transactions: [buy, sell]
               }
             ]
    end

    test "deliveries add and remove shares" do
      transactions = [
        in_portfolio(:inbound_delivery, @thursday, 1, 20, 5),
        in_portfolio(:outbound_delivery, @friday, 1, 20, 2)
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) == [{1, 20, shares(3)}]
    end

    test "a security transfer moves shares to the other portfolio" do
      transactions = [
        in_portfolio(:buy, @thursday, 1, 20, 10),
        in_portfolio(:security_transfer, @friday, 1, 20, 4, other_portfolio_id: 2)
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) ==
               [{1, 20, shares(6)}, {2, 20, shares(4)}]
    end

    test "are kept apart per portfolio and security, and left out without shares" do
      transactions = [
        in_portfolio(:buy, @thursday, 1, 20, 1),
        in_portfolio(:buy, @thursday, 2, 20, 2),
        in_portfolio(:buy, @thursday, 1, 21, 3),
        in_portfolio(:sell, @friday, 1, 21, 3)
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) ==
               [{1, 20, shares(1)}, {2, 20, shares(2)}]
    end

    test "count the transactions of the day and none after it" do
      transactions = [
        in_portfolio(:inbound_delivery, @friday, 1, 20, 1),
        in_portfolio(:inbound_delivery, @saturday, 1, 20, 2)
      ]

      assert Valuation.holdings(transactions, @thursday) == []
      assert shares_per_holding(Valuation.holdings(transactions, @friday)) == [{1, 20, shares(1)}]
    end

    test "do not change with dividends" do
      transactions = [
        in_portfolio(:inbound_delivery, @thursday, 1, 20, 5),
        transaction(:dividend, @friday,
          account_id: 10,
          security_id: 20,
          shares: shares(5),
          amount: money(1)
        )
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) == [{1, 20, shares(5)}]
    end
  end

  describe "balances/2" do
    for {type, sign} <- [
          deposit: 1,
          removal: -1,
          buy: -1,
          sell: 1,
          dividend: 1,
          interest: 1,
          interest_charge: -1,
          tax: -1,
          tax_refund: 1,
          fee: -1,
          fee_refund: 1
        ] do
      test "#{type} books #{if sign > 0, do: "a credit", else: "a debit"}" do
        transactions = [transaction(unquote(type), @friday, account_id: 10, amount: money(100))]

        assert Valuation.balances(transactions, @friday) == %{10 => unquote(sign) * money(100)}
      end
    end

    test "add up per account" do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        in_portfolio(:buy, @friday, 1, 20, 10, account_id: 10, amount: money(900)),
        transaction(:deposit, @friday, account_id: 11, amount: money(5))
      ]

      assert Valuation.balances(transactions, @friday) == %{10 => money(100), 11 => money(5)}
    end

    test "a cash transfer moves the amount to the other account" do
      transfer =
        transaction(:cash_transfer, @friday,
          account_id: 10,
          other_account_id: 11,
          amount: money(500)
        )

      assert Valuation.balances([transfer], @friday) == %{10 => -money(500), 11 => money(500)}
    end

    test "a cash transfer into another currency credits its converted gross value" do
      unit = %TransactionUnit{
        type: :gross_value,
        amount: money(500),
        currency: "EUR",
        fx_amount: money(550),
        fx_currency: "USD"
      }

      transfer =
        transaction(:cash_transfer, @friday,
          account_id: 10,
          other_account_id: 11,
          amount: money(500),
          units: [unit]
        )

      assert Valuation.balances([transfer], @friday) == %{10 => -money(500), 11 => money(550)}
    end

    test "count no transaction after the day" do
      transactions = [transaction(:deposit, @saturday, account_id: 10, amount: money(1))]

      assert Valuation.balances(transactions, @friday) == %{}
    end
  end

  describe "value/3" do
    test "is shares times the last close before a day without a price" do
      market = market([{20, @friday, price(100)}])

      assert Valuation.value(holding(20, 10), market, @saturday) == money(1_000)
    end

    test "is shares times today's quote" do
      market = market([{20, @friday, price(100)}], quote_date: @saturday, quote: price(102))

      assert Valuation.value(holding(20, 10), market, @saturday) == money(1_020)
    end

    test "converts a foreign currency at the ECB rate of the day" do
      market = market([{21, @friday, price(110)}], rates: [{"USD", @friday, Decimal.new("1.10")}])

      assert Valuation.value(holding(21, 10), market, @friday) == money(1_000)
    end

    test "rounds half up to cents in the security's currency, as PP does" do
      market = market([{20, @friday, price(33.335)}])

      assert Valuation.value(holding(20, 3), market, @friday) == money(100.01)
    end

    test "multiplies to ten significant digits before rounding, as PP does" do
      market = market([{20, @friday, 123_456_789_460_000}])

      assert Valuation.value(holding(20, 1), market, @friday) == money(1_234_567.90)
    end

    test "takes the gross price per share of the last transaction without any price, as PP does" do
      fee = %TransactionUnit{type: :fee, amount: money(10), currency: "EUR"}

      transactions = [
        in_portfolio(:buy, @thursday, 1, 20, 2, amount: money(180)),
        in_portfolio(:buy, @friday, 1, 20, 4, amount: money(410), units: [fee])
      ]

      assert Valuation.value(holding(20, 6, transactions), market([]), @friday) == money(600)
    end

    test "takes the price in the security's currency from the gross value of a foreign purchase" do
      unit = %TransactionUnit{
        type: :gross_value,
        amount: money(920),
        currency: "EUR",
        fx_amount: money(1_000),
        fx_currency: "USD"
      }

      transactions = [in_portfolio(:buy, @friday, 1, 21, 10, amount: money(920), units: [unit])]
      market = market([], rates: [{"USD", @friday, Decimal.new("1.25")}])

      assert Valuation.value(holding(21, 10, transactions), market, @friday) == money(800)
    end

    test "is nothing without any price or transaction" do
      assert Valuation.value(holding(20, 10), market([]), @friday) == 0
    end
  end

  describe "net_worth/4" do
    setup do
      %{accounts: [%Account{id: 10, currency: "EUR"}, %Account{id: 11, currency: "USD"}]}
    end

    test "adds the values of the holdings and the account balances", %{accounts: accounts} do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        in_portfolio(:buy, @friday, 1, 20, 10, account_id: 10, amount: money(900))
      ]

      market = market([{20, @friday, price(95)}])

      assert Valuation.net_worth(transactions, accounts, market, @friday) == money(1_050)
    end

    test "converts account balances in a foreign currency", %{accounts: accounts} do
      transactions = [
        transaction(:deposit, @friday, account_id: 11, currency: "USD", amount: money(110))
      ]

      market = market([], rates: [{"USD", @friday, Decimal.new("1.10")}])

      assert Valuation.net_worth(transactions, accounts, market, @friday) == money(100)
    end

    test "changes with today's quote", %{accounts: accounts} do
      transactions = [in_portfolio(:inbound_delivery, @thursday, 1, 20, 10)]
      market = market([{20, @friday, price(100)}], quote_date: @saturday, quote: price(102))

      assert Valuation.net_worth(transactions, accounts, market, @friday) == money(1_000)
      assert Valuation.net_worth(transactions, accounts, market, @saturday) == money(1_020)
    end

    test "values a security held in several portfolios once, as PP does", %{accounts: accounts} do
      transactions = [
        in_portfolio(:inbound_delivery, @friday, 1, 20, 1),
        in_portfolio(:inbound_delivery, @friday, 2, 20, 1)
      ]

      market = market([{20, @friday, price(0.015)}])

      assert Valuation.net_worth(transactions, accounts, market, @friday) == 3
    end
  end
end
