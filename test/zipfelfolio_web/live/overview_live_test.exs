defmodule ZipfelfolioWeb.OverviewLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures}

  alias Zipfelfolio.{LocalTime, Repo}
  alias Zipfelfolio.Portfolios.TransactionUnit
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

  test "shows a change that rounds to 0 € without a colour", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 100)
    Repo.update!(Ecto.Changeset.change(security, latest_close: price(99.996)))

    {:ok, lv, _html} = live(conn, ~p"/")

    assert lv |> element("#net-worth .text-body-secondary") |> render() =~ ~r/>\s*0\s€ heute/u
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

    # The shares came in at 100 € yesterday and are quoted at 102 € today: 1,510 € on 1,500 €.
    test "shows TTWROR and IRR for the period", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert lv |> element("#ttwror .stat-label") |> render() =~ "TTWROR · 6 M"
      assert lv |> element("#ttwror .stat-value.text-success") |> render() =~ "+0,67\u00A0%"
      assert lv |> element("#irr .stat-label") |> render() =~ "IZF · 6 M"
      assert lv |> element("#irr .stat-value.text-success") |> render() =~ ~r/\+\d+,\d\x{00A0}%/u
      assert lv |> element("#irr") |> render() =~ "p. a., geldgewichtet"

      lv |> element("#period a", "Max") |> render_click()

      assert lv |> element("#ttwror .stat-label") |> render() =~ "TTWROR · Max"
      assert lv |> element("#ttwror .stat-value") |> render() =~ "+0,67\u00A0%"
      assert lv |> element("#irr .stat-label") |> render() =~ "IZF · Max"
    end

    test "updates the returns when new prices arrive", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      Repo.update_all(Security, set: [latest_close: price(97)])
      send(lv.pid, :market_data_updated)

      assert lv |> element("#ttwror .stat-value.text-danger") |> render() =~ "−1,00\u00A0%"
    end
  end

  test "shows this year's dividends before taxes and fees", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    account = account_fixture(scope)

    for {date, net, tax, fee} <- [
          {today(), 15, 4, 1},
          {Date.new!(today().year, 1, 1), 30, 0, 0},
          {Date.new!(today().year - 1, 12, 31), 99, 0, 0}
        ] do
      transaction_fixture(scope, date,
        type: :dividend,
        account_id: account.id,
        security_id: security.id,
        amount: money(net),
        units: [
          %TransactionUnit{type: :tax, amount: money(tax), currency: "EUR"},
          %TransactionUnit{type: :fee, amount: money(fee), currency: "EUR"}
        ]
      )
    end

    {:ok, lv, _html} = live(conn, ~p"/")

    assert lv |> element("#dividends .stat-label") |> render() =~ "Dividenden #{today().year}"
    assert lv |> element("#dividends .stat-value") |> render() =~ "50\u00A0€"
    assert lv |> element("#dividends") |> render() =~ "brutto"
  end

  describe "Depots" do
    # 240 € on the reference account since last year, 10 shares delivered yesterday at 100 €,
    # 102 € today: 1,260 € on 1,240 € since 31 December.
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "Konto Langfristig"})

      transaction_fixture(scope, Date.shift(today(), year: -1),
        type: :deposit,
        account_id: account.id,
        amount: money(240)
      )

      portfolio =
        portfolio_fixture(scope, %{name: "Langfristig", reference_account_id: account.id})

      deliver(scope, portfolio, 10, money(1_000))
      %{portfolio: portfolio}
    end

    defp deliver(scope, portfolio, count, amount) do
      security =
        security_fixture(quote_feed: :manual, latest_date: today(), latest_close: price(102))

      price_fixture(security, Date.add(today(), -1), price(100), :pp)

      transaction_fixture(scope, Date.add(today(), -1),
        type: :inbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(count),
        amount: amount
      )
    end

    test "lists each portfolio with its value and TTWROR since 1 January", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      row = lv |> element("#portfolio-#{ctx.portfolio.id}") |> render()

      assert row =~ "Langfristig"
      assert row =~ "1\u00A0Wertpapier · Konto\u00A0240,00\u00A0€"
      assert row =~ "1.260,00\u00A0€"

      assert lv |> element("#portfolio-#{ctx.portfolio.id} .text-success") |> render() =~
               "+1,6\u00A0% YTD"
    end

    test "shows a portfolio without shares as cash only and hides retired ones once empty", ctx do
      cash = portfolio_fixture(ctx.scope, %{name: "Sparplan"})
      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
      empty = portfolio_fixture(ctx.scope, %{name: "Leer", retired: true})
      deliver(ctx.scope, retired, 1, money(100))

      {:ok, lv, _html} = live(ctx.conn, ~p"/")

      assert lv |> element("#portfolio-#{cash.id}") |> render() =~ "nur Cash"
      assert lv |> element("#portfolio-#{cash.id}") |> render() =~ "keine\u00A0Wertpapiere"
      assert has_element?(lv, "#portfolio-#{retired.id}", "102,00\u00A0€")
      refute has_element?(lv, "#portfolio-#{empty.id}")
    end
  end

  test "points to the import while there are no portfolios", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    refute has_element?(lv, "#net-worth")
    assert has_element?(lv, "a[href='/settings/import']", "Import aus Portfolio Performance")
  end
end
