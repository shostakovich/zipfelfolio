defmodule ZipfelfolioWeb.HoldingsLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures}

  alias Zipfelfolio.{LocalTime, Repo}
  alias Zipfelfolio.Portfolios.TransactionUnit

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  defp security(close, attrs \\ []) do
    security = security_fixture([quote_feed: :manual, isin: "IE00B3RBWM25"] ++ attrs)

    price_fixture(security, Date.add(today(), -1), price(close), :pp)
    security
  end

  defp deliver(scope, portfolio, security, count, amount) do
    transaction_fixture(scope, Date.add(today(), -1),
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count),
      amount: money(amount)
    )
  end

  defp deposit(scope, account, amount) do
    transaction_fixture(scope, Date.add(today(), -1),
      type: :deposit,
      account_id: account.id,
      amount: money(amount)
    )
  end

  test "values the remaining shares after a partial sale at their FIFO purchase value", ctx do
    account = account_fixture(ctx.scope)
    portfolio = portfolio_fixture(ctx.scope, %{reference_account_id: account.id})
    security = security(130)
    trade = [portfolio_id: portfolio.id, account_id: account.id, security_id: security.id]

    transaction_fixture(
      ctx.scope,
      Date.add(today(), -30),
      [type: :buy, shares: shares(10), amount: money(1_000)] ++ trade
    )

    transaction_fixture(
      ctx.scope,
      Date.add(today(), -20),
      [
        type: :buy,
        shares: shares(10),
        amount: money(1_210),
        units: [%TransactionUnit{type: :fee, amount: money(10), currency: "EUR"}]
      ] ++ trade
    )

    transaction_fixture(
      ctx.scope,
      Date.add(today(), -10),
      [type: :sell, shares: shares(15), amount: money(1_800)] ++ trade
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

    row = lv |> element("#holding-#{portfolio.id}-#{security.id}") |> render()

    assert row =~ "Vanguard FTSE All-World"
    assert row =~ "IE00B3RBWM25"
    assert row =~ ~r/>\s*5\s*</
    assert row =~ "130,00 €"
    assert row =~ "650,00\u00A0€"
    assert row =~ "605,00\u00A0€"
    assert row =~ "+45,00\u00A0€"
    assert row =~ "+7,4\u00A0%"
  end

  describe "an account two portfolios settle against" do
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "K"})
      deposit(scope, account, 50)

      [a, b] =
        for name <- ["A", "B"],
            do: portfolio_fixture(scope, %{name: name, reference_account_id: account.id})

      deliver(scope, b, security(100), 1, 100)
      %{account: account, a: a, b: b}
    end

    test "appears once, under the first portfolio, while all are shown", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

      assert has_element?(lv, "#portfolio-menu-toggle", "Gesamt")
      assert has_element?(lv, "#portfolio-menu a[href$='=#{ctx.b.id}'] .app-chip", "B")
      assert has_element?(lv, "#portfolio-#{ctx.a.id} #account-#{ctx.account.id}", "K")
      refute has_element?(lv, "#portfolio-#{ctx.b.id} #account-#{ctx.account.id}")
      refute has_element?(lv, "#accounts")
      assert has_element?(lv, "#total", "150,00\u00A0€")
    end

    test "appears under the selected portfolio", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

      lv |> element("#portfolio-menu a", "B") |> render_click()

      assert_patch(lv, ~p"/holdings?portfolio=#{ctx.b.id}")
      assert has_element?(lv, "#portfolio-menu-toggle", "B")
      assert has_element?(lv, "#portfolio-#{ctx.b.id} #account-#{ctx.account.id}", "K")
      refute has_element?(lv, "#portfolio-#{ctx.a.id}")
      assert has_element?(lv, "#total", "150,00\u00A0€")
    end

    test "keeps the selected portfolio in the URL, so that it survives a reload", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")
      lv |> element("#portfolio-menu a", "B") |> render_click()
      url = assert_patch(lv)

      {:ok, lv, _html} = live(ctx.conn, url)

      assert has_element?(lv, "#portfolio-menu-toggle", "B")
      assert has_element?(lv, "#portfolio-menu a.active", "B")
      assert has_element?(lv, "#portfolio-#{ctx.b.id}")
      refute has_element?(lv, "#portfolio-#{ctx.a.id}")

      lv |> element("#portfolio-menu a", "Gesamt") |> render_click()

      assert_patch(lv, ~p"/holdings")
      assert has_element?(lv, "#portfolio-#{ctx.a.id}")
    end

    test "marks the row of the account it was opened for", ctx do
      {:ok, lv, _html} =
        live(ctx.conn, ~p"/holdings?portfolio=#{ctx.a.id}&account=#{ctx.account.id}")

      assert has_element?(lv, "#account-#{ctx.account.id}.table-active[aria-current]")
    end
  end

  test "groups the accounts of no portfolio as „Konten“", ctx do
    savings = account_fixture(ctx.scope, %{name: "Tagesgeld"})
    deposit(ctx.scope, savings, 1_000)
    portfolio = portfolio_fixture(ctx.scope)
    deliver(ctx.scope, portfolio, security(100), 10, 1_000)

    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings?account=#{savings.id}")

    assert has_element?(lv, "#accounts", "Konten")
    assert has_element?(lv, "#accounts #account-#{savings.id}.table-active", "Tagesgeld")
    assert lv |> element("#account-#{savings.id}") |> render() =~ "1.000,00\u00A0€"
    assert lv |> element("#account-#{savings.id}") |> render() =~ "50,0\u00A0%"

    lv |> element("#portfolio-menu a", "Langfristig") |> render_click()

    refute has_element?(lv, "#accounts")
    assert lv |> element("#total") |> render() =~ "50,0\u00A0%"
  end

  test "hides holdings without shares, and retired portfolios and accounts once empty", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    sold = security(100, name: "Verkauft")
    deliver(ctx.scope, portfolio, sold, 1, 100)

    transaction_fixture(ctx.scope, today(),
      type: :outbound_delivery,
      portfolio_id: portfolio.id,
      security_id: sold.id,
      shares: shares(1)
    )

    retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
    deliver(ctx.scope, retired, security(100), 1, 100)
    empty = portfolio_fixture(ctx.scope, %{name: "Leer", retired: true})
    closed = account_fixture(ctx.scope, %{name: "Geschlossen", retired: true})
    kept = account_fixture(ctx.scope, %{name: "Noch offen", retired: true})
    deposit(ctx.scope, kept, 1)

    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

    refute has_element?(lv, "#holding-#{portfolio.id}-#{sold.id}")
    assert has_element?(lv, "#portfolio-#{portfolio.id}", "Keine Wertpapiere")
    assert has_element?(lv, "#portfolio-#{retired.id}")
    assert has_element?(lv, "#portfolio-menu a", "Alt")
    refute has_element?(lv, "#portfolio-#{empty.id}")
    refute has_element?(lv, "#portfolio-menu a", "Leer")
    refute has_element?(lv, "#account-#{closed.id}")
    assert has_element?(lv, "#account-#{kept.id}")
  end

  test "shows all portfolios for a portfolio that is not the user's", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    other = Zipfelfolio.UsersFixtures.user_scope_fixture()
    foreign = portfolio_fixture(other, %{name: "Fremd"})

    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings?portfolio=#{foreign.id}")

    assert has_element?(lv, "#portfolio-menu-toggle", "Gesamt")
    assert has_element?(lv, "#portfolio-#{portfolio.id}")
    refute render(lv) =~ "Fremd"
  end

  test "updates when new prices arrive", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    security = security(100)
    deliver(ctx.scope, portfolio, security, 10, 1_000)
    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

    Repo.update!(Ecto.Changeset.change(security, latest_date: today(), latest_close: price(110)))
    send(lv.pid, :market_data_updated)

    assert lv |> element("#holding-#{portfolio.id}-#{security.id}") |> render() =~
             "1.100,00\u00A0€"
  end

  test "is reached from the overview's portfolios", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    deliver(ctx.scope, portfolio, security(100), 1, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert {:ok, lv, _html} =
             lv
             |> element("#portfolio-#{portfolio.id}")
             |> render_click()
             |> follow_redirect(ctx.conn, ~p"/holdings?portfolio=#{portfolio.id}")

    assert has_element?(lv, "#portfolio-menu-toggle", "Langfristig")
  end

  test "points to the import while there are no portfolios", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/holdings")

    refute has_element?(lv, "#holdings")
    assert has_element?(lv, "a[href='/settings/import']", "Import aus Portfolio Performance")
  end

  test "is not shown to a visitor who is not signed in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/holdings")
  end
end
