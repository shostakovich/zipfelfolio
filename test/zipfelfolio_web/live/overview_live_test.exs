defmodule ZipfelfolioWeb.OverviewLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures}

  alias Zipfelfolio.{LocalTime, Repo}
  alias Zipfelfolio.Securities.Security

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  defp holding_fixture(scope, count, attrs \\ []) do
    security =
      security_fixture(quote_feed: :manual, latest_date: today(), latest_close: price(102))

    price_fixture(security, Date.add(today(), -1), price(100), :pp)

    transaction_fixture(
      scope,
      Date.add(today(), -1),
      [
        type: :inbound_delivery,
        portfolio_id: portfolio_fixture(scope).id,
        security_id: security.id,
        shares: shares(count)
      ] ++ attrs
    )

    security
  end

  test "shows net worth and its change since yesterday", %{conn: conn, scope: scope} do
    holding_fixture(scope, 10)

    {:ok, lv, _html} = live(conn, ~p"/")

    assert lv |> element("#net-worth") |> render() =~ "1.020\u00A0€"

    assert lv |> element("#net-worth .text-success") |> render() =~
             "+20\u00A0€ heute (+2,00\u00A0%)"
  end

  test "shows a loss since yesterday in red", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    Repo.update!(Ecto.Changeset.change(security, latest_close: price(97.5)))

    {:ok, lv, _html} = live(conn, ~p"/")

    assert lv |> element("#net-worth") |> render() =~ "975\u00A0€"

    assert lv |> element("#net-worth .text-danger") |> render() =~
             "−25\u00A0€ heute (−2,50\u00A0%)"
  end

  test "shows the change without a percentage when there was nothing yesterday", ctx do
    account = account_fixture(ctx.scope)

    transaction_fixture(ctx.scope, today(),
      type: :deposit,
      account_id: account.id,
      amount: money(500)
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/")

    assert lv |> element("#net-worth .text-success") |> render() =~ ~r/\+500\x{00A0}€ heute\s*</u
  end

  test "updates when new prices arrive", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    {:ok, lv, _html} = live(conn, ~p"/")

    Repo.update!(Ecto.Changeset.change(security, latest_close: price(110)))
    send(lv.pid, :market_data_updated)

    assert lv |> element("#net-worth") |> render() =~ "1.100\u00A0€"
  end

  describe "Wertentwicklung" do
    # 1,000 € deposited two years ago, 500 € of shares delivered yesterday, quoted at 102 € today.
    setup %{scope: scope} do
      account = account_fixture(scope)

      transaction_fixture(scope, Date.shift(today(), year: -2),
        type: :deposit,
        account_id: account.id,
        amount: money(1_000)
      )

      holding_fixture(scope, 5, amount: money(500))
      :ok
    end

    test "shows net worth against invested capital for six months", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#period a.active[aria-current]", "6 M")
      assert_push_event(lv, "net-worth-chart", %{dates: dates} = chart)
      assert dates == Enum.to_list(Date.range(Date.shift(today(), month: -6), today()))
      assert List.last(chart.net_worth) == money(1_510)
      assert List.last(chart.invested_capital) == money(1_500)
      assert Enum.at(chart.invested_capital, -3) == money(1_000)
    end

    test "keeps the period in the URL, so that it survives a reload", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      assert_push_event(lv, "net-worth-chart", _six_months)

      lv |> element("#period a", "YTD") |> render_click()

      assert_patch(lv, ~p"/?period=ytd")
      assert_push_event(lv, "net-worth-chart", %{dates: [first | _]})
      assert first == Date.new!(today().year, 1, 1)

      {:ok, lv, _html} = live(conn, ~p"/?period=ytd")

      assert has_element?(lv, "#period a.active", "YTD")
      assert_push_event(lv, "net-worth-chart", %{dates: [^first | _]})
    end

    test "shows everything since the first transaction as Max", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/?period=max")

      assert has_element?(lv, "#period a.active", "Max")
      assert_push_event(lv, "net-worth-chart", %{dates: [first | _] = dates})
      assert first == Date.shift(today(), year: -2)
      assert List.last(dates) == today()
    end

    test "falls back to six months for an unknown period", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/?period=decade")

      assert has_element?(lv, "#period a.active", "6 M")
    end

    test "updates when new prices arrive", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      assert_push_event(lv, "net-worth-chart", _before)

      Repo.update_all(Security, set: [latest_close: price(110)])
      send(lv.pid, :market_data_updated)

      assert_push_event(lv, "net-worth-chart", %{net_worth: net_worth})
      assert List.last(net_worth) == money(1_550)
    end
  end

  test "points to the import while there are no portfolios", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    refute has_element?(lv, "#net-worth")
    assert has_element?(lv, "a[href='/settings/import']", "Import aus Portfolio Performance")
  end
end
