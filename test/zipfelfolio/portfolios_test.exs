defmodule Zipfelfolio.PortfoliosTest do
  use Zipfelfolio.DataCase

  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures, TaxonomiesFixtures, UsersFixtures}

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

  describe "holdings/3" do
    defp security_at(close, name, attrs \\ []) do
      security = security_fixture([quote_feed: :manual, name: name] ++ attrs)
      price_fixture(security, @friday, price(close), :pp)
      security
    end

    defp buy(scope, portfolio, security, count, amount) do
      transaction_fixture(scope, @friday,
        type: :buy,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(count),
        amount: money(amount)
      )
    end

    defp deposit_on_friday(scope, account, amount) do
      transaction_fixture(scope, @friday,
        type: :deposit,
        account_id: account.id,
        amount: money(amount)
      )
    end

    defp group_names(holdings),
      do: Enum.map(holdings.groups, &(&1.portfolio && &1.portfolio.name))

    defp account_names(group), do: Enum.map(group.accounts, & &1.account.name)

    defp dividends_by_name(holdings) do
      for group <- holdings.groups, row <- group.holdings do
        {group.portfolio.name, row.security.name, row.dividends}
      end
      |> Enum.sort()
    end

    test "gives each portfolio's holdings by value, then its reference account", ctx do
      account = account_fixture(ctx.scope, %{name: "Konto Langfristig"})
      deposit_on_friday(ctx.scope, account, 2_000)
      portfolio = Repo.update!(change(ctx.portfolio, reference_account_id: account.id))
      small = security_at(10, "Klein")
      large = security_at(100, "Groß")
      buy(ctx.scope, portfolio, small, 10, 120)
      buy(ctx.scope, portfolio, large, 10, 800)

      assert %{groups: [group], portfolio: nil, net_worth: 310_000} =
               Portfolios.holdings(ctx.scope, nil, @saturday)

      assert [
               %{security: ^large, shares: 1_000_000_000, price: 10_000_000_000} = groß,
               %{security: ^small} = klein
             ] = group.holdings

      assert {groß.value, groß.purchase_value, groß.gain} ==
               {money(1_000), money(800), money(200)}

      assert {klein.value, klein.purchase_value, klein.gain} ==
               {money(100), money(120), money(-20)}

      assert [%{account: ^account, value: 200_000}] = group.accounts

      assert {group.value, group.purchase_value, group.gain} ==
               {money(3_100), money(920), money(180)}
    end

    test "shows an account two portfolios settle against under the first or the selected", ctx do
      account = account_fixture(ctx.scope, %{name: "K"})
      deposit_on_friday(ctx.scope, account, 50)

      [a, b] =
        for name <- ["A", "B"],
            do: portfolio_fixture(ctx.scope, %{name: name, reference_account_id: account.id})

      all = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert group_names(all) == ["A", "B", "Langfristig"]
      assert Enum.map(all.groups, &account_names/1) == [["K"], [], []]
      assert Enum.map(all.portfolios, & &1.name) == ["A", "B", "Langfristig"]

      selected = Portfolios.holdings(ctx.scope, b.id, @saturday)

      assert selected.portfolio == b
      assert group_names(selected) == ["B"]
      assert Enum.map(selected.groups, &account_names/1) == [["K"]]
      assert %{value: 5_000, purchase_value: 0, gain: 0} = selected.total
      assert selected.net_worth == money(50)
      assert Portfolios.holdings(ctx.scope, a.id, @saturday).portfolio == a
    end

    test "groups the accounts of no portfolio last, without retired ones once empty", ctx do
      savings = account_fixture(ctx.scope, %{name: "Tagesgeld"})
      deposit_on_friday(ctx.scope, savings, 1_000)
      account_fixture(ctx.scope, %{name: "Geschlossen", retired: true})
      kept = account_fixture(ctx.scope, %{name: "Noch offen", retired: true})
      deposit_on_friday(ctx.scope, kept, 1)
      buy(ctx.scope, ctx.portfolio, security_at(100, "Groß"), 10, 1_000)

      holdings = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert group_names(holdings) == ["Langfristig", nil]
      assert account_names(List.last(holdings.groups)) == ["Noch offen", "Tagesgeld"]

      assert %{value: 200_100, purchase_value: 100_000, gain: 0} = holdings.total

      assert group_names(Portfolios.holdings(ctx.scope, ctx.portfolio.id, @saturday)) ==
               ["Langfristig"]
    end

    test "leaves out holdings without shares and retired portfolios once empty", ctx do
      sold = security_at(100, "Verkauft")
      buy(ctx.scope, ctx.portfolio, sold, 1, 100)

      transaction_fixture(ctx.scope, @saturday,
        type: :sell,
        portfolio_id: ctx.portfolio.id,
        security_id: sold.id,
        shares: shares(1)
      )

      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
      buy(ctx.scope, retired, security_at(100, "Groß"), 1, 100)
      empty = portfolio_fixture(ctx.scope, %{name: "Leer", retired: true})

      holdings = Portfolios.holdings(ctx.scope, empty.id, @saturday)

      assert holdings.portfolio == nil
      assert group_names(holdings) == ["Alt", "Langfristig"]
      assert [[_held], []] = Enum.map(holdings.groups, & &1.holdings)
    end

    test "gives the costs of the funds shown, a fund in several portfolios once", ctx do
      account = account_fixture(ctx.scope)
      deposit_on_friday(ctx.scope, account, 5_000)
      plan = portfolio_fixture(ctx.scope, %{name: "Sparplan", reference_account_id: account.id})
      world = security_at(100, "Welt", attributes: %{"ter" => 0.002})
      em = security_at(10, "Schwellenländer", attributes: %{"ter" => 0.005})
      buy(ctx.scope, ctx.portfolio, world, 60, 6_000)
      buy(ctx.scope, plan, world, 20, 2_000)
      buy(ctx.scope, plan, em, 200, 2_000)

      all = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert [%{security: ^world, value: 800_000}, %{security: ^em, value: 200_000}] =
               all.costs.funds

      assert Decimal.equal?(all.costs.ter, Decimal.new("0.0026"))
      assert all.costs.per_year == money(26)

      selected = Portfolios.holdings(ctx.scope, plan.id, @saturday)

      assert [%{security: ^em, value: 200_000}, %{security: ^world, value: 200_000}] =
               selected.costs.funds

      assert Decimal.equal?(selected.costs.ter, Decimal.new("0.0035"))
      assert selected.costs.per_year == money(14)
    end

    test "gives the allocation of the securities shown, without accounts", ctx do
      account = account_fixture(ctx.scope)
      deposit_on_friday(ctx.scope, account, 1_000)
      plan = portfolio_fixture(ctx.scope, %{name: "Sparplan", reference_account_id: account.id})
      world = security_at(100, "Welt")
      brazil = security_at(10, "Brasilien")
      composition_fixture(world, %{"US" => 0.6, "JP" => 0.4}, %{"Energy" => 1})
      composition_fixture(brazil, %{"BR" => 1})
      buy(ctx.scope, ctx.portfolio, world, 60, 6_000)
      buy(ctx.scope, plan, brazil, 400, 4_000)

      regions = fn holdings ->
        Enum.map(holdings.allocation.regions, &{&1.key, Decimal.to_float(&1.share)})
      end

      all = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert regions.(all) == [emerging_markets: 0.4, usa: 0.36, japan: 0.24]
      assert [%{key: "Energy"}, %{key: nil}] = all.allocation.sectors
      assert all.allocation.as_of == ~U[2026-10-08 12:00:00.000000Z]

      assert regions.(Portfolios.holdings(ctx.scope, plan.id, @saturday)) ==
               [emerging_markets: 1.0]
    end

    test "gives the allocation into each taxonomy of the user with value shown in it", ctx do
      account = account_fixture(ctx.scope)
      deposit_on_friday(ctx.scope, account, 1_000)
      plan = portfolio_fixture(ctx.scope, %{name: "Sparplan", reference_account_id: account.id})
      world = security_at(100, "Welt")
      buy(ctx.scope, ctx.portfolio, world, 30, 3_000)
      buy(ctx.scope, plan, world, 10, 1_000)

      {taxonomy, root} = taxonomy_fixture(ctx.scope, "Anlageklassen")
      equity = classification_fixture(root, "Aktien", 8_000, 0)
      assignment_fixture(equity, world)
      cash = classification_fixture(root, "Cash", 2_000, 1)
      assignment_fixture(cash, account)
      {_held_by_none, nobody} = taxonomy_fixture(ctx.scope, "Branchen")

      assignment_fixture(
        classification_fixture(nobody, "Technologie", 10_000),
        security_at(1, "X")
      )

      {_foreign, foreign} = taxonomy_fixture(user_scope_fixture(), "Fremd")
      assignment_fixture(classification_fixture(foreign, "Alles", 10_000), world)

      shares = fn holdings ->
        for %{taxonomy: %{name: name}, classifications: rows} <- holdings.allocation.taxonomies,
            do: {name, Enum.map(rows, &{&1.classification.name, Decimal.to_float(&1.share)})}
      end

      all = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert shares.(all) == [{"Anlageklassen", [{"Aktien", 0.8}, {"Cash", 0.2}]}]
      assert [%{taxonomy: %{id: id}}] = all.allocation.taxonomies
      assert id == taxonomy.id

      assert shares.(Portfolios.holdings(ctx.scope, plan.id, @saturday)) ==
               [{"Anlageklassen", [{"Aktien", 0.5}, {"Cash", 0.5}]}]

      assert shares.(Portfolios.holdings(ctx.scope, ctx.portfolio.id, @saturday)) ==
               [{"Anlageklassen", [{"Aktien", 1.0}, {"Cash", 0.0}]}]
    end

    test "gives each holding its part of its security's dividends of the next 12 months", ctx do
      paying = security_at(100, "Ausschüttend")
      accumulating = security_at(50, "Thesaurierend")
      pension = portfolio_fixture(ctx.scope, %{name: "Altersvorsorge"})
      buy(ctx.scope, ctx.portfolio, paying, 30, 3_000)
      buy(ctx.scope, pension, paying, 10, 1_000)
      buy(ctx.scope, ctx.portfolio, accumulating, 10, 500)
      divvy_diary_dividend_fixture(paying, nil, ~D[2026-10-20], 2)

      holdings = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert dividends_by_name(holdings) == [
               {"Altersvorsorge", "Ausschüttend", money(20)},
               {"Langfristig", "Ausschüttend", money(60)},
               {"Langfristig", "Thesaurierend", 0}
             ]

      assert holdings.total.dividends == money(80)
      assert holdings.total.securities_value == money(4_500)

      assert Portfolios.holdings(ctx.scope, pension.id, @saturday).total.dividends == money(20)
    end

    test "shows all portfolios for one of another user", ctx do
      other = portfolio_fixture(user_scope_fixture(), %{name: "Fremd"})

      holdings = Portfolios.holdings(ctx.scope, other.id, @saturday)

      assert holdings.portfolio == nil
      assert group_names(holdings) == ["Langfristig"]
    end
  end

  describe "dividends/2" do
    defp dividend(scope, security, date, net, tax) do
      transaction_fixture(scope, date,
        type: :dividend,
        account_id: account_fixture(scope).id,
        security_id: security.id,
        shares: shares(10),
        amount: money(net),
        units: [%TransactionUnit{type: :tax, amount: money(tax), currency: "EUR"}]
      )
    end

    test "gives the user's dividends received, per year, this year and last", ctx do
      security = security_fixture(quote_feed: :manual)
      dividend(ctx.scope, security, ~D[2026-03-01], 15, 5)
      dividend(ctx.scope, security, ~D[2025-07-01], 40, 10)
      dividend(user_scope_fixture(), security, ~D[2026-04-01], 70, 0)

      result = Portfolios.dividends(ctx.scope, @saturday)

      assert Enum.map(result.received, &{&1.date, &1.security.id, &1.gross, &1.net}) == [
               {~D[2026-03-01], security.id, money(20), money(15)},
               {~D[2025-07-01], security.id, money(50), money(40)}
             ]

      assert Enum.map(result.years, &{&1.year, &1.gross, &1.net}) == [
               {2026, money(20), money(15)},
               {2025, money(50), money(40)}
             ]

      assert result.this_year == %{gross: money(20), net: money(15)}
      assert result.last_year == %{gross: money(50), net: money(40)}
    end

    test "gives the user's dividends expected and the value of their holdings", ctx do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(100), :pp)

      transaction_fixture(ctx.scope, @friday,
        type: :buy,
        portfolio_id: ctx.portfolio.id,
        security_id: security.id,
        shares: shares(10),
        amount: money(900)
      )

      dividend(ctx.scope, security, ~D[2026-03-01], 8, 2)
      divvy_diary_dividend_fixture(security, nil, ~D[2026-10-20], 1)
      other = user_scope_fixture()
      deliver(other, portfolio_fixture(other), security, ~D[2025-01-02], 1_000)
      dividend(other, security, ~D[2026-04-01], 100, 0)

      result = Portfolios.dividends(ctx.scope, @saturday)

      assert [%{pay_date: ~D[2026-10-20], shares: shares, gross: gross, net: net}] =
               result.upcoming

      assert {shares, gross, net} == {shares(10), money(10), money(8)}
      assert result.total == %{gross: money(10), net: money(8)}
      assert hd(result.months).announced == %{gross: money(10), net: money(8)}
      assert {result.value, result.purchase_value} == {money(1_000), money(900)}
    end
  end

  describe "security/4" do
    defp trade(scope, type, portfolio, security, date, count, amount) do
      transaction_fixture(scope, date,
        type: type,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(count),
        amount: money(amount)
      )
    end

    defp chart_dates(security) do
      for period <- [:one_year, :five_years, :max] do
        chart = Portfolios.security(security.scope, security.security, period, @saturday).chart
        Enum.map(chart.prices, & &1.date)
      end
    end

    test "gives the user's holdings of the security by portfolio name and their total", ctx do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(120), :pp)
      pension = portfolio_fixture(ctx.scope, %{name: "Altersvorsorge"})
      trade(ctx.scope, :buy, ctx.portfolio, security, ~D[2026-09-01], 10, 1_000)
      trade(ctx.scope, :buy, pension, security, ~D[2026-09-02], 5, 550)
      trade(ctx.scope, :sell, pension, security, ~D[2026-09-03], 1, 115)
      other = user_scope_fixture()
      trade(other, :buy, portfolio_fixture(other), security, ~D[2026-09-01], 7, 700)

      %{holdings: holdings, total: total} =
        Portfolios.security(ctx.scope, security, :one_year, @saturday)

      assert Enum.map(holdings, &{&1.portfolio.name, &1.shares, &1.value, &1.purchase_value}) ==
               [
                 {"Altersvorsorge", shares(4), money(480), money(440)},
                 {"Langfristig", shares(10), money(1_200), money(1_000)}
               ]

      assert Enum.map(holdings, & &1.gain) == [money(40), money(200)]

      assert total == %{
               shares: shares(14),
               value: money(1_680),
               purchase_value: money(1_440),
               gain: money(240)
             }
    end

    test "values a holding in pence at a hundredth of the pound's ECB rate", ctx do
      security = security_fixture(quote_feed: :manual, currency: "GBX")
      price_fixture(security, @friday, price(500), :pp)
      ExchangeRates.store([{"GBP", @friday, Decimal.new("0.85")}])
      deliver(ctx.scope, ctx.portfolio, security, @friday, 1_000)

      assert Portfolios.security(ctx.scope, security, :one_year, @saturday).total.value ==
               money(5_882.35)
    end

    test "gives nothing held of a security the user does not hold", ctx do
      security = security_fixture(quote_feed: :manual)
      other = user_scope_fixture()
      trade(other, :buy, portfolio_fixture(other), security, @friday, 7, 700)

      result = Portfolios.security(ctx.scope, security, :one_year, @saturday)

      assert result.holdings == []
      assert result.total == %{shares: 0, value: 0, purchase_value: 0, gain: 0}
      assert result.chart.trades == []
    end

    test "gives the price today and yesterday", ctx do
      security =
        security_fixture(quote_feed: :manual, latest_date: @saturday, latest_close: price(102))

      price_fixture(security, @friday, price(100), :pp)

      result = Portfolios.security(ctx.scope, security, :one_year, @saturday)

      assert {result.price, result.price_yesterday} == {price(102), price(100)}
    end

    test "gives the price chart of the period with the user's purchases and sales", ctx do
      security = security_fixture(quote_feed: :manual)

      for {date, close} <- [{~D[2020-10-01], 50}, {~D[2025-10-01], 90}, {@friday, 100}],
          do: price_fixture(security, date, price(close), :pp)

      trade(ctx.scope, :buy, ctx.portfolio, security, ~D[2026-09-01], 10, 950)
      other = user_scope_fixture()
      trade(other, :buy, portfolio_fixture(other), security, ~D[2026-09-02], 7, 700)

      assert chart_dates(%{scope: ctx.scope, security: security}) == [
               [@friday],
               [~D[2025-10-01], @friday],
               [~D[2020-10-01], ~D[2025-10-01], @friday]
             ]

      assert [%{date: ~D[2026-09-01], type: :buy, shares: shares(10), price: price(95)}] ==
               Portfolios.security(ctx.scope, security, :one_year, @saturday).chart.trades
    end

    test "gives the distributions from the user's dividends and the costs a year", ctx do
      security = security_fixture(quote_feed: :manual, attributes: %{"ter" => 0.002})
      price_fixture(security, @friday, price(100), :pp)
      trade(ctx.scope, :buy, ctx.portfolio, security, ~D[2026-03-02], 100, 9_000)

      for scope <- [ctx.scope, user_scope_fixture()] do
        transaction_fixture(scope, ~D[2026-09-30],
          type: :dividend,
          account_id: account_fixture(scope).id,
          security_id: security.id,
          shares: shares(100),
          amount: money(50)
        )
      end

      result = Portfolios.security(ctx.scope, security, :one_year, @saturday)

      assert [%{date: ~D[2026-09-30], shares: shares, per_share: per_share}] =
               result.distributions

      assert {shares, per_share} == {shares(100), price(0.5)}
      assert result.costs_per_year == money(20)
    end

    test "gives the dividends expected of the security, at the latest ECB rate", ctx do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(100), :pp)
      trade(ctx.scope, :buy, ctx.portfolio, security, ~D[2026-03-02], 100, 9_000)
      divvy_diary_dividend_fixture(security, ~D[2026-10-10], ~D[2026-10-20], 0.5, "USD")
      ExchangeRates.store([{"USD", @friday, Decimal.new("1.25")}])

      assert [%{kind: :announced, pay_date: ~D[2026-10-20], gross: gross}] =
               Portfolios.security(ctx.scope, security, :one_year, @saturday).upcoming

      assert gross == money(40)
    end

    test "starts Max at the first trade before the first price", ctx do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(100), :pp)
      trade(ctx.scope, :buy, ctx.portfolio, security, ~D[2024-05-02], 1, 80)

      chart = Portfolios.security(ctx.scope, security, :max, @saturday).chart

      assert [%{date: ~D[2024-05-02], price: 8_000_000_000}] = chart.trades
      assert Enum.map(chart.prices, & &1.date) == [@friday]
    end
  end

  describe "upcoming_dividends/2" do
    test "gives the dividends expected, those of the rest of the year and of three months", ctx do
      security = security_fixture(quote_feed: :manual)
      deliver(ctx.scope, ctx.portfolio, security, ~D[2025-01-02], 100)
      divvy_diary_dividend_fixture(security, ~D[2026-10-10], ~D[2026-10-20], 0.5)
      divvy_diary_dividend_fixture(security, nil, ~D[2025-12-15], 1)
      divvy_diary_dividend_fixture(security, nil, ~D[2026-01-15], 1)
      other = user_scope_fixture()
      deliver(other, portfolio_fixture(other), security, ~D[2025-01-02], 1_000)

      result = Portfolios.upcoming_dividends(ctx.scope, @saturday)

      assert Enum.map(result.upcoming, &{&1.pay_date, &1.gross}) == [
               {~D[2026-10-20], money(50)},
               {~D[2026-12-15], money(100)},
               {~D[2027-01-15], money(100)}
             ]

      assert result.rest_of_year == money(150)
      assert Enum.map(result.next_three_months, & &1.pay_date) == [~D[2026-10-20], ~D[2026-12-15]]
    end
  end

  describe "sidebar/2" do
    defp held(scope, portfolio, count, close) do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(close), :pp)
      deliver(scope, portfolio, security, @friday, count)
      security
    end

    defp deposit_into(scope, account, amount) do
      transaction_fixture(scope, @friday,
        type: :deposit,
        account_id: account.id,
        amount: money(amount)
      )
    end

    test "gives each portfolio with its reference account, then the accounts of no portfolio",
         ctx do
      account = account_fixture(ctx.scope, %{name: "Konto Langfristig"})
      deposit_into(ctx.scope, account, 2_000)
      portfolio = Repo.update!(change(ctx.portfolio, reference_account_id: account.id))
      held(ctx.scope, portfolio, 10, 100)
      savings = account_fixture(ctx.scope, %{name: "Tagesgeld"})
      deposit_into(ctx.scope, savings, 1_000)
      portfolio_fixture(ctx.scope, %{name: "Sparplan"})

      sidebar = Portfolios.sidebar(ctx.scope, @saturday)

      assert [
               %{portfolio: %{name: "Langfristig"}, value: 300_000} = langfristig,
               %{portfolio: %{name: "Sparplan"}, value: 0, account: nil}
             ] = sidebar.portfolios

      assert langfristig.account == %{account: account, value: 200_000}
      assert sidebar.accounts == [%{account: savings, value: 100_000}]

      holdings = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert Enum.map(holdings.groups, & &1.value) ==
               Enum.map(sidebar.portfolios, & &1.value) ++ [money(1_000)]
    end

    test "lists an account two portfolios settle against under the first of them", ctx do
      account = account_fixture(ctx.scope, %{name: "K"})
      deposit_into(ctx.scope, account, 50)

      for name <- ["A", "B"],
          do: portfolio_fixture(ctx.scope, %{name: name, reference_account_id: account.id})

      assert [%{account: %{account: ^account}}, %{account: nil}, %{account: nil}] =
               Portfolios.sidebar(ctx.scope, @saturday).portfolios
    end

    test "keeps a retired portfolio while it holds shares", ctx do
      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
      security = held(ctx.scope, retired, 5, 100)

      assert [%{portfolio: %{name: "Alt"}, value: 50_000}, %{portfolio: %{name: "Langfristig"}}] =
               Portfolios.sidebar(ctx.scope, @saturday).portfolios

      transaction_fixture(ctx.scope, @saturday,
        type: :outbound_delivery,
        portfolio_id: retired.id,
        security_id: security.id,
        shares: shares(5)
      )

      assert [%{portfolio: %{name: "Langfristig"}}] =
               Portfolios.sidebar(ctx.scope, @saturday).portfolios
    end

    test "leaves out retired accounts once empty and other users' portfolios and accounts",
         ctx do
      account_fixture(ctx.scope, %{name: "Geschlossen", retired: true})
      other = user_scope_fixture()
      deposit_into(other, account_fixture(other, %{name: "Fremdes Konto"}), 1)
      held(other, portfolio_fixture(other, %{name: "Fremd"}), 1, 100)

      assert %{portfolios: [%{portfolio: %{name: "Langfristig"}, value: 0}], accounts: []} =
               Portfolios.sidebar(ctx.scope, @saturday)
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
