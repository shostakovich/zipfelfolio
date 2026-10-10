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

  test "keeps a retired portfolio that still holds shares until it is empty", ctx do
    retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
    security = holding(ctx.scope, retired, 5, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert lv |> element("#net-worth") |> render() =~ "500 €"
    assert lv |> element("#side-portfolio-#{retired.id}") |> render() =~ "500,00"

    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

    assert has_element?(lv, "#portfolio-#{retired.id}")
    assert has_element?(lv, "#side-portfolio-#{retired.id}", "Alt")

    transaction_fixture(ctx.scope, today(),
      type: :outbound_delivery,
      portfolio_id: retired.id,
      security_id: security.id,
      shares: shares(5)
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

    refute has_element?(lv, "#portfolio-#{retired.id}")
    refute has_element?(lv, "#side-portfolio-#{retired.id}")
  end

  describe "the portfolios and accounts" do
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "Konto Langfristig"})
      deposit(scope, account, 240)
      portfolio = portfolio_fixture(scope, %{reference_account_id: account.id})
      holding(scope, portfolio, 10, 100)
      savings = account_fixture(scope, %{name: "Tagesgeld"})
      deposit(scope, savings, 1_000)
      %{account: account, portfolio: portfolio, savings: savings}
    end

    test "list each portfolio with its account, then the accounts of no portfolio", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      assert lv |> element("#side-portfolio-#{ctx.portfolio.id}") |> render() =~ "1.240,00"
      assert lv |> element("#side-account-#{ctx.account.id}.app-sub") |> render() =~ "240,00"
      assert lv |> element("#side-account-#{ctx.savings.id}") |> render() =~ "1.000,00"
      assert lv |> element("#side-portfolios") |> render() =~ "1.240,00"
      assert lv |> element("#side-accounts") |> render() =~ "1.000,00"
      assert lv |> element("#net-worth") |> render() =~ "2.240 €"
    end

    test "link to the holdings, an account with its row marked", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      for {id, path} <- [
            {"#side-portfolio-#{ctx.portfolio.id}",
             ~p"/holdings?#{[portfolio: ctx.portfolio.id]}"},
            {"#side-account-#{ctx.account.id}",
             ~p"/holdings?#{[portfolio: ctx.portfolio.id, account: ctx.account.id]}"},
            {"#side-account-#{ctx.savings.id}", ~p"/holdings?#{[account: ctx.savings.id]}"}
          ] do
        assert has_element?(lv, ~s(#{id}[href="#{path}"]))
      end

      {:ok, lv, _html} =
        lv
        |> element("#side-account-#{ctx.account.id}")
        |> render_click()
        |> follow_redirect(ctx.conn)

      assert has_element?(lv, "#account-#{ctx.account.id}.table-active")
      assert has_element?(lv, "#side-account-#{ctx.account.id}.active[aria-current=page]")
      refute has_element?(lv, "#side-portfolio-#{ctx.portfolio.id}.active")
      refute has_element?(lv, "#side-holdings.active")
    end

    test "mark the open portfolio, or the screen", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/holdings?#{[portfolio: ctx.portfolio.id]}")

      assert has_element?(lv, "#side-portfolio-#{ctx.portfolio.id}.active[aria-current=page]")
      refute has_element?(lv, "#side-holdings.active")

      {:ok, lv, _html} = live(ctx.conn, ~p"/holdings")

      assert has_element?(lv, "#side-holdings.active[aria-current=page]")
      refute has_element?(lv, "#side-portfolio-#{ctx.portfolio.id}.active")

      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      assert has_element?(lv, "#side-overview.active[aria-current=page]")
    end

    test "update when new prices arrive, also on a page without prices", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/import")

      Repo.update_all(Zipfelfolio.Securities.Security,
        set: [latest_date: today(), latest_close: price(110)]
      )

      MarketData.run_daily()

      assert lv |> element("#side-portfolio-#{ctx.portfolio.id}") |> render() =~ "1.340,00"
    end
  end

  test "shows only the user's own portfolios and accounts", ctx do
    portfolio_fixture(ctx.scope, %{name: "Eigenes Depot"})
    other = Zipfelfolio.UsersFixtures.user_scope_fixture()
    deposit(other, account_fixture(other, %{name: "Fremdes Konto"}), 1)
    holding(other, portfolio_fixture(other, %{name: "Fremdes Depot"}), 1, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert has_element?(lv, "#sidebar", "Eigenes Depot")
    refute has_element?(lv, "#sidebar", "Fremd")
    refute has_element?(lv, "#side-accounts")
  end

  test "offers the account menu with passkeys and signing out", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert has_element?(lv, "#side-me", ctx.user.email)
    assert has_element?(lv, ~s(#side-menu a[href="/users/settings#passkeys"]), "Passkeys")

    assert has_element?(
             lv,
             ~s(#side-menu a[href="/users/log-out"][data-method=delete]),
             "Abmelden"
           )

    assert has_element?(lv, "#side-settings", "Einstellungen")
  end

  test "applies the collapse stored on this device before the first paint", ctx do
    [head, _body] = ctx.conn |> get(~p"/") |> html_response(200) |> String.split("</head>")

    # On the root element, outside the LiveView, so that live navigation keeps it.
    assert head =~ ~r/localStorage\.getItem\("sidebar"\)/
    assert head =~ ~r/matchMedia\("\(min-width: 1280px\)"\).*classList\.add\("app-rail"\)/s

    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert has_element?(lv, "aside#sidebar[phx-hook=Sidebar]")
    assert has_element?(lv, "#sidebar #side-toggle")
  end
end
