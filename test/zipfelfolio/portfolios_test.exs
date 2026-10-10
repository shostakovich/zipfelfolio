defmodule Zipfelfolio.PortfoliosTest do
  use Zipfelfolio.DataCase

  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures, UsersFixtures}

  alias Zipfelfolio.{ExchangeRates, Portfolios}

  @friday ~D[2026-10-02]
  @saturday ~D[2026-10-03]

  setup do
    scope = user_scope_fixture()
    %{scope: scope, portfolio: portfolio_fixture(scope)}
  end

  defp deliver(scope, portfolio, security, date, count) do
    transaction_fixture(scope, date,
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count)
    )
  end

  describe "history/2" do
    test "gives net worth and invested capital, each transferal at the rate of its day", ctx do
      account = account_fixture(ctx.scope, %{currency: "USD"})

      ExchangeRates.store([
        {"USD", @friday, Decimal.new("1.10")},
        {"USD", @saturday, Decimal.new("1.25")}
      ])

      transaction_fixture(ctx.scope, @friday,
        type: :deposit,
        account_id: account.id,
        currency: "USD",
        amount: money(110)
      )

      assert Portfolios.history(ctx.scope, [@saturday]) ==
               [%{date: @saturday, net_worth: money(88), invested_capital: money(100)}]
    end
  end

  describe "first_transaction_date/1" do
    test "is the day of the user's first transaction", ctx do
      assert Portfolios.first_transaction_date(ctx.scope) == nil

      security = security_fixture()
      deliver(ctx.scope, ctx.portfolio, security, @saturday, 1)
      deliver(ctx.scope, ctx.portfolio, security, @friday, 1)

      other = user_scope_fixture()
      deliver(other, portfolio_fixture(other), security, Date.add(@friday, -1), 1)

      assert Portfolios.first_transaction_date(ctx.scope) == @friday
    end
  end

  describe "net_worth/2" do
    test "values shares on a day without a price at the last close before it", ctx do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(100), :pp)
      deliver(ctx.scope, ctx.portfolio, security, @friday, 10)

      assert Portfolios.net_worth(ctx.scope, [@saturday]) == %{@saturday => money(1_000)}
    end

    test "values today's shares at today's quote", ctx do
      security =
        security_fixture(quote_feed: :manual, latest_date: @saturday, latest_close: price(102))

      price_fixture(security, @friday, price(100), :pp)
      deliver(ctx.scope, ctx.portfolio, security, @friday, 10)

      assert Portfolios.net_worth(ctx.scope, [@friday, @saturday]) ==
               %{@friday => money(1_000), @saturday => money(1_020)}
    end

    test "converts a foreign currency at the ECB rate of the day", ctx do
      security = security_fixture(quote_feed: :manual, currency: "USD")
      price_fixture(security, @friday, price(110), :pp)
      ExchangeRates.store([{"USD", @friday, Decimal.new("1.10")}])
      deliver(ctx.scope, ctx.portfolio, security, @friday, 10)

      assert Portfolios.net_worth(ctx.scope, [@friday]) == %{@friday => money(1_000)}
    end

    test "converts pence at a hundredth of the pound's ECB rate", ctx do
      security = security_fixture(quote_feed: :manual, currency: "GBX")
      price_fixture(security, @friday, price(500), :pp)
      ExchangeRates.store([{"GBP", @friday, Decimal.new("0.85")}])
      deliver(ctx.scope, ctx.portfolio, security, @friday, 1_000)

      assert Portfolios.net_worth(ctx.scope, [@friday]) == %{@friday => money(5_882.35)}
    end

    test "adds the account balances and leaves out other users' transactions", ctx do
      account = account_fixture(ctx.scope)

      transaction_fixture(ctx.scope, @friday,
        type: :deposit,
        account_id: account.id,
        amount: money(500)
      )

      other = user_scope_fixture()
      other_account = account_fixture(other)

      transaction_fixture(other, @friday,
        type: :deposit,
        account_id: other_account.id,
        amount: money(1)
      )

      assert Portfolios.net_worth(ctx.scope, [@friday]) == %{@friday => money(500)}
    end
  end
end
