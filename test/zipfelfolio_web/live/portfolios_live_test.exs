defmodule ZipfelfolioWeb.PortfoliosLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.PortfoliosFixtures

  alias Zipfelfolio.{LocalTime, Repo}
  alias Zipfelfolio.Portfolios.Portfolio

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

  describe "depot numbers" do
    test "shows each active portfolio's depot number masked with its reference account", ctx do
      account = account_fixture(ctx.scope, %{name: "Konto Sparplan"})

      portfolio =
        portfolio_fixture(ctx.scope, %{
          name: "Sparplan",
          depot_number: "123 456 4472",
          reference_account_id: account.id
        })

      other = portfolio_fixture(ctx.scope, %{name: "Langfristig"})
      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})

      {:ok, lv, _html} = live(ctx.conn, ~p"/portfolios")

      assert has_element?(
               lv,
               "#depot-number-#{portfolio.id}",
               "Depotnummer …4472 · Referenzkonto „Konto Sparplan“"
             )

      refute render(lv) =~ "123 456 4472"
      assert has_element?(lv, "#depot-number-#{other.id}", "Keine Depotnummer")
      assert has_element?(lv, "#depot-number-#{other.id} button", "Eintragen")
      refute has_element?(lv, "#depot-number-#{retired.id}")
    end

    test "edits a depot number in place and refuses the digits of another portfolio", ctx do
      portfolio_fixture(ctx.scope, %{name: "Sparplan", depot_number: "4472"})
      portfolio = portfolio_fixture(ctx.scope, %{name: "Langfristig"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/portfolios")
      lv |> element("#depot-number-#{portfolio.id} button", "Eintragen") |> render_click()

      assert lv
             |> form("#depot-number-form", portfolio: %{depot_number: "44-72"})
             |> render_change() =~ "gehört schon zu „Sparplan“"

      lv
      |> form("#depot-number-form", portfolio: %{depot_number: "DE 0815 4471"})
      |> render_submit()

      assert render(lv) =~ "Depotnummer von „Langfristig“ gespeichert."
      refute has_element?(lv, "#depot-number-form")
      assert has_element?(lv, "#depot-number-#{portfolio.id}", "Depotnummer …4471")
      assert Repo.get!(Portfolio, portfolio.id).depot_number == "DE 0815 4471"

      lv |> element("#depot-number-#{portfolio.id} button", "Ändern") |> render_click()
      assert has_element?(lv, "#depot-number-form input[value='DE 0815 4471']")
      lv |> form("#depot-number-form", portfolio: %{depot_number: ""}) |> render_submit()

      assert has_element?(lv, "#depot-number-#{portfolio.id}", "Keine Depotnummer")
    end

    test "cancels editing", ctx do
      portfolio = portfolio_fixture(ctx.scope, %{name: "Sparplan"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/portfolios")
      lv |> element("#depot-number-#{portfolio.id} button") |> render_click()
      lv |> element("#depot-number-form button", "Abbrechen") |> render_click()

      refute has_element?(lv, "#depot-number-form")
    end

    test "is reachable from the settings on the desktop", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#depots a[href='/portfolios']", "Depotnummern bearbeiten")
    end
  end
end
