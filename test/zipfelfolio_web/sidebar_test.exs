defmodule ZipfelfolioWeb.SidebarTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures}

  alias Zipfelfolio.{LocalTime, MarketData, Repo}

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  defp holding(scope, portfolio, count, close) do
    security = security_fixture(quote_feed: :manual)
    price_fixture(security, Date.add(today(), -1), price(close), :pp)

    transaction_fixture(scope, Date.add(today(), -1),
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count)
    )

    security
  end

  defp deposit(scope, account, amount) do
    transaction_fixture(scope, Date.add(today(), -1),
      type: :deposit,
      account_id: account.id,
      amount: money(amount)
    )
  end

  test "lists the views, the active portfolios and accounts, then the settings", ctx do
    retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
    holding(ctx.scope, retired, 5, 100)
    closed = account_fixture(ctx.scope, %{name: "Geschlossen", retired: true})
    deposit(ctx.scope, closed, 50)
    portfolio_fixture(ctx.scope, %{name: "Aktiv"})
    account_fixture(ctx.scope, %{name: "Tagesgeld"})

    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

    labels =
      lv
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(aside nav[aria-label="Hauptnavigation"] li))
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> hd()))

    assert labels ==
             ~w(Übersicht Bestand Dividenden Buchungen Performance Depots Aktiv Konten Tagesgeld) ++
               ["Einstellungen"]

    assert has_element?(lv, "#holdings-portfolio-#{retired.id}")
    refute has_element?(lv, sidebar_link(~p"/holdings?#{[portfolio: retired.id]}"))
    refute has_element?(lv, sidebar_link(~p"/holdings?#{[account: closed.id]}"))
  end

  test "marks „Bestand“ for a retired portfolio or account, which it leaves out", ctx do
    retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
    holding(ctx.scope, retired, 5, 100)
    closed = account_fixture(ctx.scope, %{name: "Geschlossen", retired: true})
    deposit(ctx.scope, closed, 50)

    for path <- [~p"/holdings?#{[portfolio: retired.id]}", ~p"/holdings?#{[account: closed.id]}"] do
      {:ok, lv, _html} = live(ctx.conn, path)
      assert has_element?(lv, sidebar_link("/holdings") <> "[aria-current=page]")
    end
  end

  describe "the portfolios and accounts" do
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "Konto Langfristig"})
      deposit(scope, account, 240)
      portfolio = portfolio_fixture(scope, %{reference_account_id: account.id})
      holding(scope, portfolio, 10, 100)
      savings = account_fixture(scope, %{name: "Tagesgeld"})
      deposit(scope, savings, 1_000)

      %{
        account: account,
        portfolio: portfolio,
        savings: savings,
        portfolio_path: ~p"/holdings?#{[portfolio: portfolio.id]}",
        account_path: ~p"/holdings?#{[portfolio: portfolio.id, account: account.id]}",
        savings_path: ~p"/holdings?#{[account: savings.id]}"
      }
    end

    test "show each portfolio's securities and each account's balance, adding up to net worth",
         ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      assert lv |> element(sidebar_link(ctx.portfolio_path)) |> render() =~ "1.000,00"
      assert lv |> element(sidebar_link(ctx.account_path)) |> render() =~ "240,00"
      assert lv |> element(sidebar_link(ctx.savings_path)) |> render() =~ "1.000,00"
      assert lv |> element("#net-worth") |> render() =~ "2.240 €"
    end

    test "stay out of the icon rail, which keeps the views and the settings", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      rail = "aside.xl\\:hidden"
      refute has_element?(lv, "#{rail} a[href='#{ctx.portfolio_path}']")
      refute has_element?(lv, "#{rail} a[href='#{ctx.savings_path}']")
      assert has_element?(lv, "#{rail} a[href='/holdings']")
      assert has_element?(lv, "#{rail} a[href='/users/settings']")
      assert has_element?(lv, sidebar_link(ctx.portfolio_path))
    end

    test "link to the holdings, an account with its row marked", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      {:ok, lv, _html} =
        lv
        |> element(sidebar_link(ctx.account_path))
        |> render_click()
        |> follow_redirect(ctx.conn)

      assert has_element?(lv, "#account-#{ctx.account.id}[aria-current=true]")
      assert has_element?(lv, sidebar_link(ctx.account_path) <> "[aria-current=page]")
      refute has_element?(lv, sidebar_link(ctx.portfolio_path) <> "[aria-current]")
      refute has_element?(lv, sidebar_link("/holdings") <> "[aria-current]")
    end

    test "mark the open portfolio, or the screen", ctx do
      {:ok, lv, _html} = live(ctx.conn, ctx.portfolio_path)

      assert has_element?(lv, sidebar_link(ctx.portfolio_path) <> "[aria-current=page]")
      refute has_element?(lv, sidebar_link("/holdings") <> "[aria-current]")

      {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

      assert has_element?(lv, sidebar_link("/holdings") <> "[aria-current=page]")
      refute has_element?(lv, sidebar_link(ctx.portfolio_path) <> "[aria-current]")

      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      assert has_element?(lv, sidebar_link("/") <> "[aria-current=page]")
    end

    test "update when new prices arrive, also on a page without prices", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/import")

      Repo.update_all(Zipfelfolio.Securities.Security,
        set: [latest_date: today(), latest_close: price(110)]
      )

      MarketData.run_daily()

      assert lv |> element(sidebar_link(ctx.portfolio_path)) |> render() =~ "1.100,00"
    end
  end

  test "shows only the user's own portfolios and accounts", ctx do
    portfolio_fixture(ctx.scope, %{name: "Eigenes Depot"})
    other = Zipfelfolio.UsersFixtures.user_scope_fixture()
    deposit(other, account_fixture(other, %{name: "Fremdes Konto"}), 1)
    holding(other, portfolio_fixture(other, %{name: "Fremdes Depot"}), 1, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    sidebar = ~s(aside nav[aria-label="Hauptnavigation"])
    assert has_element?(lv, sidebar, "Eigenes Depot")
    refute has_element?(lv, sidebar, "Fremd")
    refute has_element?(lv, sidebar, "Konten")
  end

  test "offers the account menu with passkeys and signing out", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert has_element?(lv, "#account-sidebar summary", ctx.user.email)

    assert has_element?(
             lv,
             ~s(#account-sidebar a[href="/users/settings#passkeys"]),
             "Passkeys"
           )

    assert has_element?(
             lv,
             ~s(#account-sidebar a[href="/users/log-out"][data-method=delete]),
             "Abmelden"
           )

    assert has_element?(lv, sidebar_link("/users/settings"), "Einstellungen")
  end

  test "shows no count on „Buchungen“ while the inbox is empty", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert lv |> element(sidebar_link("/transactions")) |> render() =~
             ~r/Buchungen\s*<\/span>\s*<\/a>/
  end
end
