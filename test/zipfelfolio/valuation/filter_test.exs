defmodule Zipfelfolio.Valuation.FilterTest do
  use ExUnit.Case, async: true

  import Zipfelfolio.PortfoliosFixtures, only: [money: 1, shares: 1]

  alias Zipfelfolio.Portfolios.{Portfolio, Transaction, TransactionUnit}
  alias Zipfelfolio.Valuation.Filter

  # Portfolio 1 settles against account 10 and holds security 20; portfolio 2 settles against
  # account 11; security 21 only portfolio 2 ever held.
  @portfolio %Portfolio{id: 1, reference_account_id: 10}

  defp transaction(type, attrs) do
    struct!(
      %Transaction{
        type: type,
        date_time: ~N[2026-10-02 12:00:00],
        amount: money(100),
        currency: "EUR",
        units: []
      },
      attrs
    )
  end

  defp history do
    [
      transaction(:buy, portfolio_id: 1, account_id: 10, security_id: 20, shares: shares(1)),
      transaction(:buy, portfolio_id: 2, account_id: 11, security_id: 21, shares: shares(1))
    ]
  end

  defp with_account, do: Filter.new([@portfolio], [10], history())
  defp without_account, do: Filter.new([@portfolio], [], history())

  defp dividend(type, account_id, security_id),
    do: transaction(type, account_id: account_id, security_id: security_id)

  defp usd_transfer(from, to) do
    unit = %TransactionUnit{
      type: :gross_value,
      amount: money(100),
      currency: "EUR",
      fx_amount: money(110),
      fx_currency: "USD"
    }

    transaction(:cash_transfer, account_id: from, other_account_id: to, units: [unit])
  end

  describe "all/0" do
    test "counts deposits and inbound deliveries as money in, removals and outbound ones as out" do
      assert Filter.flows(Filter.all(), transaction(:deposit, account_id: 10)) ==
               [{:inbound, money(100), "EUR"}]

      assert Filter.flows(Filter.all(), transaction(:inbound_delivery, portfolio_id: 1)) ==
               [{:inbound, money(100), "EUR"}]

      assert Filter.flows(Filter.all(), transaction(:removal, account_id: 10)) ==
               [{:outbound, money(100), "EUR"}]

      assert Filter.flows(Filter.all(), transaction(:outbound_delivery, portfolio_id: 1)) ==
               [{:outbound, money(100), "EUR"}]
    end

    test "keeps transfers as transfers, the received side in the other account's currency" do
      assert Filter.flows(Filter.all(), usd_transfer(10, 11)) ==
               [{:transfer_out, money(100), "EUR"}, {:transfer_in, money(110), "USD"}]

      transfer = transaction(:security_transfer, portfolio_id: 1, other_portfolio_id: 2)

      assert Filter.flows(Filter.all(), transfer) ==
               [{:transfer_out, money(100), "EUR"}, {:transfer_in, money(100), "EUR"}]
    end

    test "counts no money in or out for what happens inside" do
      for transaction <- history() ++ [transaction(:sell, portfolio_id: 1, account_id: 10)],
          do: assert(Filter.flows(Filter.all(), transaction) == [])

      for type <- [:dividend, :interest, :interest_charge, :tax, :tax_refund, :fee, :fee_refund],
          do: assert(Filter.flows(Filter.all(), dividend(type, 10, 99)) == [])
    end

    test "includes every portfolio and account" do
      assert Filter.portfolio?(Filter.all(), 1)
      assert Filter.account?(Filter.all(), 10)
      refute Filter.account?(Filter.all(), nil)
    end
  end

  describe "new/3" do
    test "includes the given portfolios and accounts only" do
      assert Filter.portfolio?(with_account(), 1)
      refute Filter.portfolio?(with_account(), 2)
      assert Filter.account?(with_account(), 10)
      refute Filter.account?(with_account(), 11)
      refute Filter.account?(without_account(), 10)
    end

    test "a purchase from an account outside brings the shares in, a sale into one takes them out" do
      buy = transaction(:buy, portfolio_id: 1, account_id: 11)
      sell = transaction(:sell, portfolio_id: 1, account_id: 11)

      assert Filter.flows(with_account(), buy) == [{:inbound, money(100), "EUR"}]
      assert Filter.flows(with_account(), sell) == [{:outbound, money(100), "EUR"}]
      assert Filter.flows(without_account(), hd(history())) == [{:inbound, money(100), "EUR"}]
    end

    test "a purchase by a portfolio outside takes the money out, a sale by one brings it in" do
      buy = transaction(:buy, portfolio_id: 2, account_id: 10)
      sell = transaction(:sell, portfolio_id: 2, account_id: 10)

      assert Filter.flows(with_account(), buy) == [{:outbound, money(100), "EUR"}]
      assert Filter.flows(with_account(), sell) == [{:inbound, money(100), "EUR"}]
    end

    test "a purchase or sale inside counts no money in or out" do
      assert Filter.flows(with_account(), transaction(:sell, portfolio_id: 1, account_id: 10)) ==
               []
    end

    test "a transfer across the edge is money in or out, in the currency of its side" do
      assert Filter.flows(with_account(), usd_transfer(10, 11)) == [
               {:outbound, money(100), "EUR"}
             ]

      assert Filter.flows(with_account(), usd_transfer(11, 10)) == [{:inbound, money(110), "USD"}]

      out = transaction(:security_transfer, portfolio_id: 1, other_portfolio_id: 2)
      into = transaction(:security_transfer, portfolio_id: 2, other_portfolio_id: 1)

      assert Filter.flows(with_account(), out) == [{:outbound, money(100), "EUR"}]
      assert Filter.flows(with_account(), into) == [{:inbound, money(100), "EUR"}]
    end

    test "a dividend, tax or fee of a security the portfolios never held is money in or out" do
      for type <- [:dividend, :tax_refund, :fee_refund],
          do:
            assert(
              Filter.flows(with_account(), dividend(type, 10, 21)) == [
                {:inbound, money(100), "EUR"}
              ]
            )

      for type <- [:tax, :fee],
          do:
            assert(
              Filter.flows(with_account(), dividend(type, 10, 21)) == [
                {:outbound, money(100), "EUR"}
              ]
            )
    end

    test "a dividend, tax or fee of a held security or without one stays inside" do
      for type <- [:dividend, :tax, :fee, :interest, :interest_charge],
          security_id <- [20, nil],
          do: assert(Filter.flows(with_account(), dividend(type, 10, security_id)) == [])
    end

    test "a dividend on the reference account outside goes out at once, a tax or fee comes in" do
      assert Filter.flows(without_account(), dividend(:dividend, 10, 20)) ==
               [{:outbound, money(100), "EUR"}]

      assert Filter.flows(without_account(), dividend(:tax, 10, 20)) ==
               [{:inbound, money(100), "EUR"}]

      assert Filter.flows(without_account(), dividend(:dividend, 10, 21)) == []
      assert Filter.flows(without_account(), dividend(:dividend, 11, 20)) == []
      assert Filter.flows(without_account(), dividend(:interest, 10, nil)) == []
    end

    test "counts nothing of other portfolios and accounts" do
      for transaction <- [
            transaction(:deposit, account_id: 11),
            transaction(:inbound_delivery, portfolio_id: 2),
            transaction(:buy, portfolio_id: 2, account_id: 11),
            usd_transfer(11, 12)
          ],
          do: assert(Filter.flows(with_account(), transaction) == [])
    end
  end
end
