defmodule ZipfelfolioWeb.OverviewLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures}

  alias Zipfelfolio.{LocalTime, Repo}

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  defp holding_fixture(scope, count) do
    security =
      security_fixture(quote_feed: :manual, latest_date: today(), latest_close: price(102))

    price_fixture(security, Date.add(today(), -1), price(100), :pp)

    transaction_fixture(scope, Date.add(today(), -1),
      type: :inbound_delivery,
      portfolio_id: portfolio_fixture(scope).id,
      security_id: security.id,
      shares: shares(count)
    )

    security
  end

  test "shows net worth and its change since yesterday", %{conn: conn, scope: scope} do
    holding_fixture(scope, 10)

    {:ok, lv, _html} = live(conn, ~p"/")

    assert lv |> element("#net-worth") |> render() =~ "1.020 €"
    assert lv |> element("#net-worth .text-success") |> render() =~ "+20 € heute (+2,00\u00A0%)"
  end

  test "shows a loss since yesterday in red", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    Repo.update!(Ecto.Changeset.change(security, latest_close: price(97.5)))

    {:ok, lv, _html} = live(conn, ~p"/")

    assert lv |> element("#net-worth") |> render() =~ "975 €"
    assert lv |> element("#net-worth .text-danger") |> render() =~ "−25 € heute (−2,50\u00A0%)"
  end

  test "shows the change without a percentage when there was nothing yesterday", ctx do
    account = account_fixture(ctx.scope)

    transaction_fixture(ctx.scope, today(),
      type: :deposit,
      account_id: account.id,
      amount: money(500)
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert lv |> element("#net-worth .text-success") |> render() =~ ~r/\+500 € heute\s*</
  end

  test "updates when new prices arrive", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    {:ok, lv, _html} = live(conn, ~p"/")

    Repo.update!(Ecto.Changeset.change(security, latest_close: price(110)))
    send(lv.pid, :market_data_updated)

    assert lv |> element("#net-worth") |> render() =~ "1.100 €"
  end

  test "points to the import while there are no portfolios", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    refute has_element?(lv, "#net-worth")
    assert has_element?(lv, "a[href='/settings/import']", "Import aus Portfolio Performance")
  end
end
