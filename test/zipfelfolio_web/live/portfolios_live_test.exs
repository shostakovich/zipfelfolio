defmodule ZipfelfolioWeb.PortfoliosLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.PortfoliosFixtures

  alias Zipfelfolio.LocalTime

  setup :register_and_log_in_user

  defp deposit(scope, account, amount) do
    transaction_fixture(scope, LocalTime.today(),
      type: :deposit,
      account_id: account.id,
      amount: money(amount)
    )
  end

  test "lists the total, the portfolios with their accounts and the accounts of no portfolio",
       ctx do
    account = account_fixture(ctx.scope, %{name: "Konto Langfristig"})
    deposit(ctx.scope, account, 240)
    portfolio = portfolio_fixture(ctx.scope, %{reference_account_id: account.id})
    savings = account_fixture(ctx.scope, %{name: "Tagesgeld"})
    deposit(ctx.scope, savings, 1_000)

    {:ok, lv, _html} = live(ctx.conn, ~p"/portfolios")

    assert has_element?(lv, ~s(#tree-total[href="/holdings"]), "Gesamt")
    assert lv |> element("#tree-total") |> render() =~ "1.240,00 €"

    assert has_element?(
             lv,
             ~s(#tree-portfolio-#{portfolio.id}[href="#{~p"/holdings?#{[portfolio: portfolio.id]}"}"]),
             "Langfristig"
           )

    assert has_element?(
             lv,
             ~s(#tree-account-#{account.id}.app-sub[href="#{~p"/holdings?#{[portfolio: portfolio.id, account: account.id]}"}"])
           )

    assert has_element?(
             lv,
             ~s(#tree-account-#{savings.id}[href="#{~p"/holdings?#{[account: savings.id]}"}"]),
             "Tagesgeld"
           )

    assert has_element?(lv, "#tab-portfolios.active[aria-current=page]")
  end

  test "shows a portfolio without a name, as PP may store one, with an empty chip", ctx do
    portfolio = portfolio_fixture(ctx.scope, %{name: ""})

    {:ok, lv, _html} = live(ctx.conn, ~p"/portfolios")
    assert has_element?(lv, "#tree-portfolio-#{portfolio.id} .app-chip")

    {:ok, lv, _html} = live(ctx.conn, ~p"/users/settings")
    assert has_element?(lv, "#side-portfolio-#{portfolio.id} .app-chip")
  end

  test "keeps the „Depots“ tab active on the holdings", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/holdings")

    assert has_element?(lv, "#tab-portfolios.active")
    refute has_element?(lv, "#tab-overview.active")
  end

  test "points to the import while there are no portfolios", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/portfolios")

    refute has_element?(lv, "#tree-total")
    assert has_element?(lv, "a[href='/settings/import']", "Import aus Portfolio Performance")
  end
end
