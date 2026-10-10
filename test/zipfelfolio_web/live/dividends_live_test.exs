defmodule ZipfelfolioWeb.DividendsLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures, UsersFixtures}

  alias Zipfelfolio.LocalTime
  alias Zipfelfolio.Portfolios.TransactionUnit
  alias Zipfelfolio.Repo

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()
  defp this_year, do: today().year

  defp dividend_fixture(scope, security, date, net, opts \\ []) do
    account = opts[:account] || account_fixture(scope)

    dividend =
      transaction_fixture(scope, date,
        type: :dividend,
        account_id: account.id,
        security_id: security.id,
        shares: shares(opts[:shares] || 10),
        amount: money(net)
      )

    for {type, amount} <- [tax: opts[:tax], fee: opts[:fee]], amount do
      Repo.insert!(%TransactionUnit{
        transaction_id: dividend.id,
        type: type,
        amount: money(amount),
        currency: "EUR"
      })
    end

    dividend
  end

  defp seed(scope) do
    portfolio_fixture(scope)
    security = security_fixture(name: "All-World")
    dividend_fixture(scope, security, Date.new!(this_year(), 1, 1), 81.5, tax: 18, fee: 0.5)
    dividend_fixture(scope, security, Date.new!(this_year() - 1, 7, 1), 40, tax: 10)
    security
  end

  test "shows this year's net dividends so far with last year's total", %{
    conn: conn,
    scope: scope
  } do
    seed(scope)

    {:ok, lv, _html} = live(conn, ~p"/dividends")

    assert lv |> element("#this-year .stat-label") |> render() =~ "#{this_year()} bisher"
    assert lv |> element("#this-year .stat-value") |> render() =~ "82\u00A0€"
    assert lv |> element("#this-year") |> render() =~ "#{this_year() - 1} gesamt 40\u00A0€"
    assert has_element?(lv, "#amount a.active", "Netto")
  end

  test "switches to gross, which survives a reload", %{conn: conn, scope: scope} do
    seed(scope)

    {:ok, lv, _html} = live(conn, ~p"/dividends")
    lv |> element("#amount a", "Brutto") |> render_click()
    assert_patch(lv, ~p"/dividends?amount=gross")

    {:ok, lv, _html} = live(conn, ~p"/dividends?amount=gross")

    assert has_element?(lv, "#amount a.active", "Brutto")
    assert lv |> element("#this-year .stat-value") |> render() =~ "100\u00A0€"
    assert lv |> element("#this-year") |> render() =~ "#{this_year() - 1} gesamt 50\u00A0€"
  end

  test "the tab survives a reload and keeps the amount", %{conn: conn, scope: scope} do
    seed(scope)

    {:ok, lv, _html} = live(conn, ~p"/dividends?amount=gross")
    lv |> element("#dividend-tabs a", "Erhalten") |> render_click()
    assert_patch(lv, ~p"/dividends?amount=gross&tab=received")

    {:ok, lv, _html} = live(conn, ~p"/dividends?tab=received&amount=gross")

    assert has_element?(lv, "#dividend-tabs a.active", "Erhalten")
    assert has_element?(lv, "#received")
    refute has_element?(lv, "#per-month")
    assert has_element?(lv, "#amount a.active", "Brutto")
  end

  test "switching tab or amount keeps the dividends; new market data reloads them", ctx do
    # Without a stale Yahoo quote, so that no refresh reloads the page on its own.
    portfolio_fixture(ctx.scope)
    security = security_fixture(name: "All-World", quote_feed: :manual)
    dividend_fixture(ctx.scope, security, Date.new!(this_year(), 1, 1), 81.5)

    {:ok, lv, _html} = live(ctx.conn, ~p"/dividends")
    dividend_fixture(ctx.scope, security, Date.new!(this_year(), 1, 2), 10)

    lv |> element("#dividend-tabs a", "Erhalten") |> render_click()
    lv |> element("#amount a", "Brutto") |> render_click()
    lv |> element("#amount a", "Netto") |> render_click()

    assert lv |> element("#this-year .stat-value") |> render() =~ "82\u00A0€"

    send(lv.pid, :market_data_updated)

    assert lv |> element("#this-year .stat-value") |> render() =~ "92\u00A0€"
  end

  test "lists every year since the first dividend with its months and total", ctx do
    security = seed(ctx.scope)
    dividend_fixture(ctx.scope, security, Date.new!(this_year() - 3, 3, 31), 12.34)

    {:ok, lv, _html} = live(ctx.conn, ~p"/dividends?tab=months")

    assert has_element?(lv, "#per-month")

    years =
      for year <- this_year()..(this_year() - 3)//-1,
          do: lv |> element("#year-#{year}") |> render()

    assert [this, last, empty, first] = years
    assert this =~ "82\u00A0€"
    assert this =~ "bis #{today().day}."
    assert this =~ "noch offen" or today().month == 12
    assert last =~ "40\u00A0€"
    assert empty =~ "–"
    assert first =~ "12\u00A0€"
  end

  test "shows each received dividend with shares, gross, taxes, fees and net", ctx do
    security = seed(ctx.scope)
    other = Zipfelfolio.UsersFixtures.user_scope_fixture()
    dividend_fixture(other, security, Date.new!(this_year(), 1, 1), 70)

    {:ok, lv, _html} = live(ctx.conn, ~p"/dividends?tab=received")

    row = lv |> element("#received tbody tr[data-date='#{this_year()}-01-01']") |> render()

    assert row =~ "All\u2011World"
    assert row =~ ~s(datetime="#{this_year()}-01-01")
    assert row =~ "10\u00A0Stück"
    assert row =~ "100,00\u00A0€"
    assert row =~ "18,00\u00A0€"
    assert row =~ "0,50\u00A0€"
    assert row =~ "81,50\u00A0€"
    assert lv |> element("#this-year .stat-value") |> render() =~ "82\u00A0€"
  end

  test "counts and lists a dividend booked without a security", ctx do
    seed(ctx.scope)

    transaction_fixture(ctx.scope, Date.new!(this_year(), 1, 2),
      type: :dividend,
      account_id: account_fixture(ctx.scope).id,
      amount: money(5)
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/dividends?tab=received")

    assert lv |> element("#this-year .stat-value") |> render() =~ "87\u00A0€"

    assert lv |> element("#received tbody tr[data-date='#{this_year()}-01-02']") |> render() =~
             "Ohne Wertpapier"
  end

  test "counts no interest", %{conn: conn, scope: scope} do
    seed(scope)

    transaction_fixture(scope, Date.new!(this_year(), 1, 31),
      type: :interest,
      account_id: account_fixture(scope).id,
      amount: money(7)
    )

    {:ok, lv, _html} = live(conn, ~p"/dividends")

    assert lv |> element("#this-year .stat-value") |> render() =~ "82\u00A0€"
  end

  test "says when no dividend is booked yet", %{conn: conn, scope: scope} do
    portfolio_fixture(scope)

    {:ok, lv, _html} = live(conn, ~p"/dividends")

    assert render(lv) =~ "Noch keine Dividenden gebucht und keine erwartet."
    refute has_element?(lv, "#this-year")
  end

  describe "calendar" do
    defp holding(scope, security, count \\ 100) do
      portfolio = portfolio_fixture(scope)

      transaction_fixture(scope, Date.add(today(), -365),
        type: :buy,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(count),
        amount: money(count * 40)
      )

      price_fixture(security, today(), price(50), :yahoo)
      portfolio
    end

    test "is the default tab and shows an announced dividend with its shares and amount", ctx do
      security = security_fixture(name: "All-World")
      holding(ctx.scope, security)
      pay_date = Date.add(today(), 10)

      divvy_diary_dividend_fixture(security, Date.add(today(), -1), pay_date, 0.5)

      {:ok, lv, _html} = live(ctx.conn, ~p"/dividends")

      assert has_element?(lv, "#dividend-tabs a.active", "Kalender")
      refute has_element?(lv, "#per-month")

      entry = lv |> element("#calendar li[data-pay-date='#{pay_date}']") |> render()

      assert entry =~ "All\u2011World"
      assert entry =~ "angekündigt"
      assert entry =~ "100\u00A0Stück × 0,50\u00A0€"
      assert entry =~ "50,00\u00A0€"
      assert entry =~ "brutto"

      assert lv |> element("#calendar-#{Calendar.strftime(pay_date, "%Y-%m")} h2") |> render() =~
               "50,00\u00A0€"
    end

    test "forecasts from the last 12 months and estimates net from them", ctx do
      security = security_fixture(name: "All-World")
      holding(ctx.scope, security)
      paid = Date.add(today(), -360)

      dividend_fixture(ctx.scope, security, paid, 163, tax: 37, shares: 100)
      divvy_diary_dividend_fixture(security, Date.add(paid, -10), paid, 2)

      {:ok, lv, _html} = live(ctx.conn, ~p"/dividends")

      entry = lv |> element("#calendar li[data-kind='forecast']") |> render()
      assert entry =~ "Prognose"
      assert entry =~ "~163,00\u00A0€"
      refute entry =~ "brutto"
      refute lv |> element(".app-kpis") |> render() =~ "brutto"

      {:ok, lv, _html} = live(ctx.conn, ~p"/dividends?amount=gross")

      assert lv |> element("#calendar li[data-kind='forecast']") |> render() =~ "~200,00\u00A0€"
    end

    test "shows the next 12 months, the yields and the next dividend", ctx do
      security = security_fixture(name: "All-World")
      holding(ctx.scope, security)
      pay_date = Date.add(today(), 10)
      divvy_diary_dividend_fixture(security, Date.add(today(), -1), pay_date, 1.25)
      other = user_scope_fixture()

      transaction_fixture(other, Date.add(today(), -365),
        type: :buy,
        portfolio_id: portfolio_fixture(other).id,
        security_id: security.id,
        shares: shares(1_000),
        amount: money(10_000)
      )

      dividend_fixture(other, security, Date.add(today(), -100), 500, shares: 1_000)

      {:ok, lv, _html} = live(ctx.conn, ~p"/dividends?amount=gross")

      assert lv |> element("#next-12-months .stat-value") |> render() =~ "125\u00A0€"
      assert lv |> element("#yield .stat-value") |> render() =~ "2,5\u00A0%"
      assert lv |> element("#yield") |> render() =~ "auf Einstand 3,1\u00A0%"
      assert lv |> element("#next-dividend .stat-value") |> render() =~ "125\u00A0€"
      assert lv |> element("#next-dividend") |> render() =~ "All\u2011World"
    end

    test "marks net amounts counted gross for want of a booked dividend", ctx do
      security = security_fixture(name: "All-World")
      holding(ctx.scope, security)
      divvy_diary_dividend_fixture(security, Date.add(today(), -1), Date.add(today(), 10), 1.25)

      {:ok, lv, _html} = live(ctx.conn, ~p"/dividends")

      assert lv |> element("#next-dividend .stat-value") |> render() =~ "brutto"
      assert lv |> element("#next-12-months .stat-value") |> render() =~ "teils brutto"
      assert lv |> element("#yield .stat-value") |> render() =~ "teils brutto"
      assert lv |> element("#coming-months-title") |> render() =~ "teils brutto"

      {:ok, lv, _html} = live(ctx.conn, ~p"/dividends?amount=gross")

      refute lv |> element(".app-kpis") |> render() =~ "brutto"
      refute lv |> element("#coming-months-title") |> render() =~ "teils brutto"
    end

    test "says when nothing is expected", ctx do
      seed(ctx.scope)

      {:ok, lv, _html} = live(ctx.conn, ~p"/dividends")

      assert render(lv) =~ "keine Dividende angekündigt oder zu erwarten"
      assert lv |> element("#next-dividend") |> render() =~ "keine erwartet"
    end
  end

  test "points to the import without portfolios", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dividends")

    assert render(lv) =~ "Import aus Portfolio Performance"
  end

  test "marks the dividends in the sidebar and the tab bar", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dividends")

    assert has_element?(lv, "#side-dividends.active[aria-current=page]")
    assert has_element?(lv, "#tab-dividends.active[aria-current=page]")
  end
end
