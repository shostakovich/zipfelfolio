defmodule Zipfelfolio.PortfoliosTest do
  use Zipfelfolio.DataCase

  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures, UsersFixtures}

  alias Zipfelfolio.{ExchangeRates, Portfolios}
  alias Zipfelfolio.Performance.IRR
  alias Zipfelfolio.Portfolios.TransactionUnit

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

  describe "overview/3" do
    # 10 shares delivered on Friday for 1,000 €, closing at 100 € that day and at 102 € today.
    defp shares_fixture(scope, portfolio, count \\ 10) do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(100), :pp)
      price_fixture(security, @saturday, price(102), :pp)

      transaction_fixture(scope, @friday,
        type: :inbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(count),
        amount: money(count * 100)
      )

      security
    end

    defp deposit(scope, account, date, amount) do
      transaction_fixture(scope, date,
        type: :deposit,
        account_id: account.id,
        amount: money(amount)
      )
    end

    test "gives net worth, its chart, the returns and this year's dividends of the user", ctx do
      account = account_fixture(ctx.scope)
      deposit(ctx.scope, account, ~D[2026-01-15], 1_000)
      security = shares_fixture(ctx.scope, ctx.portfolio)

      for {date, net, tax} <- [{~D[2026-03-01], 15, 5}, {~D[2025-12-31], 99, 0}] do
        transaction_fixture(ctx.scope, date,
          type: :dividend,
          account_id: account.id,
          security_id: security.id,
          amount: money(net),
          units: [%TransactionUnit{type: :tax, amount: money(tax), currency: "EUR"}]
        )
      end

      other = user_scope_fixture()
      deposit(other, account_fixture(other), @friday, 1)

      overview = Portfolios.overview(ctx.scope, :six_months, @saturday)

      assert {overview.net_worth_yesterday, overview.net_worth} == {money(2_114), money(2_134)}
      assert overview.dividends == money(20)
      assert_in_delta overview.ttwror, 2_134 / 2_114 - 1, 1.0e-12

      assert overview.irr ==
               IRR.calculate([
                 {~D[2026-04-03], -1_114.0},
                 {@friday, -1_000.0},
                 {@saturday, 2_134.0}
               ])

      assert [%{date: ~D[2026-04-03]} | _] = overview.chart

      assert List.last(overview.chart) == %{
               date: @saturday,
               net_worth: money(2_134),
               invested_capital: money(2_000)
             }
    end

    test "counts this year's dividends up to today only", ctx do
      account = account_fixture(ctx.scope)

      for date <- [~D[2026-03-01], ~D[2026-12-15]] do
        transaction_fixture(ctx.scope, date,
          type: :dividend,
          account_id: account.id,
          amount: money(20)
        )
      end

      assert Portfolios.overview(ctx.scope, :six_months, @saturday).dividends == money(20)
    end

    test "lists the portfolios with their value and TTWROR since 1 January", ctx do
      account = account_fixture(ctx.scope, %{name: "Konto Langfristig"})
      portfolio = Repo.update!(change(ctx.portfolio, reference_account_id: account.id))
      deposit(ctx.scope, account, ~D[2025-06-01], 240)
      shares_fixture(ctx.scope, portfolio)

      savings = account_fixture(ctx.scope, %{name: "Konto Sparplan"})
      deposit(ctx.scope, savings, @friday, 1_500)
      portfolio_fixture(ctx.scope, %{name: "Sparplan", reference_account_id: savings.id})

      assert [langfristig, sparplan] = Portfolios.overview(ctx.scope, :max, @saturday).portfolios

      assert %{account: ^account, balance: 24_000, securities: 1, value: 126_000} = langfristig
      assert langfristig.portfolio.id == portfolio.id
      assert_in_delta langfristig.ttwror, 1_260 / 1_240 - 1, 1.0e-12

      assert %{account: ^savings, securities: 0, value: 150_000, ttwror: +0.0} = sparplan
    end

    test "counts an account two portfolios settle against for the first of them", ctx do
      account = account_fixture(ctx.scope)
      deposit(ctx.scope, account, @friday, 50)

      [a, b] =
        for name <- ["A", "B"],
            do: portfolio_fixture(ctx.scope, %{name: name, reference_account_id: account.id})

      shares_fixture(ctx.scope, b, 1)

      assert [a_row, b_row, _langfristig] =
               Portfolios.overview(ctx.scope, :max, @saturday).portfolios

      assert {a_row.portfolio.id, a_row.account, a_row.value} == {a.id, account, money(50)}
      assert {b_row.portfolio.id, b_row.account, b_row.value} == {b.id, nil, money(102)}
    end

    test "gives nothing but zeros without any transaction", ctx do
      assert %{
               net_worth: 0,
               net_worth_yesterday: 0,
               chart: [%{date: @saturday, net_worth: 0, invested_capital: 0}],
               ttwror: +0.0,
               irr: +0.0,
               dividends: 0,
               portfolios: [%{value: 0, securities: 0, account: nil, ttwror: +0.0}]
             } = Portfolios.overview(ctx.scope, :six_months, @saturday)
    end

    test "keeps a retired portfolio while it holds shares", ctx do
      Repo.update!(change(ctx.portfolio, retired: true))
      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
      shares_fixture(ctx.scope, retired, 5)

      assert [%{portfolio: %{name: "Alt"}, value: 51_000}] =
               Portfolios.overview(ctx.scope, :max, @saturday).portfolios
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

    test "converts an account in another currency at the ECB rate of the day", ctx do
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

      assert Portfolios.net_worth(ctx.scope, [@friday, @saturday]) ==
               %{@friday => money(100), @saturday => money(88)}
    end
  end
end
