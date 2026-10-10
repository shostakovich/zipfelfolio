defmodule ZipfelfolioWeb.SecurityLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures, UsersFixtures}

  alias Zipfelfolio.{LocalTime, Repo}

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  # Closes of 90 € two years ago and 100 € yesterday, quoted at 102 € today.
  defp security_fixture_with_prices do
    security =
      security_fixture(
        quote_feed: :manual,
        isin: "IE00B3RBWM25",
        wkn: "A1JX52",
        latest_date: today(),
        latest_close: price(102)
      )

    price_fixture(security, Date.shift(today(), year: -2), price(90), :pp)
    price_fixture(security, Date.add(today(), -1), price(100), :pp)
    security
  end

  defp trade(scope, type, portfolio, security, date, count, amount) do
    transaction_fixture(scope, date,
      type: type,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count),
      amount: money(amount)
    )
  end

  describe "a security" do
    setup %{scope: scope} do
      security = security_fixture_with_prices()
      portfolio = portfolio_fixture(scope)
      trade(scope, :buy, portfolio, security, Date.add(today(), -30), 10, 950)
      trade(scope, :sell, portfolio, security, Date.add(today(), -10), 2, 196)
      trade(scope, :inbound_delivery, portfolio, security, Date.shift(today(), year: -2), 1, 90)
      other = user_scope_fixture()
      trade(other, :buy, portfolio_fixture(other), security, Date.add(today(), -20), 7, 700)

      %{security: security, portfolio: portfolio}
    end

    test "shows its price with the change since yesterday", %{conn: conn, security: security} do
      {:ok, lv, _html} = live(conn, ~p"/securities/#{security}")

      assert page_title(lv) =~ "Vanguard FTSE All-World"
      assert has_element?(lv, "h1", "Vanguard FTSE All-World")
      assert has_element?(lv, "header", "IE00B3RBWM25 · WKN A1JX52 · EUR")
      assert lv |> element("#price") |> render() =~ "102,00 €"
      assert lv |> element("#price .text-success") |> render() =~ "+2,00 € (+2,00\u00A0%) heute"
    end

    test "charts a year of prices with the user's purchases and sales", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/securities/#{ctx.security}")

      assert has_element?(lv, "#period a.active[aria-current]", "1 J")
      assert_push_event(lv, "price-chart", chart)
      assert chart.currency == "€"
      assert chart.dates == [Date.add(today(), -1), today()]
      assert chart.prices == [price(100), price(102)]

      assert chart.trades == [
               %{date: Date.add(today(), -30), type: :buy, shares: shares(10), price: price(95)},
               %{date: Date.add(today(), -10), type: :sell, shares: shares(2), price: price(98)}
             ]

      assert has_element?(lv, "#price-chart-legend", "Kauf")
    end

    test "keeps the period in the URL, so that it survives a reload", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/securities/#{ctx.security}")
      assert_push_event(lv, "price-chart", _one_year)

      lv |> element("#period a", "5 J") |> render_click()

      assert_patch(lv, ~p"/securities/#{ctx.security}?period=5y")
      assert_push_event(lv, "price-chart", %{dates: [first | _], trades: [delivery | _]})
      assert first == Date.shift(today(), year: -2)
      assert delivery.type == :inbound_delivery

      {:ok, lv, _html} = live(ctx.conn, ~p"/securities/#{ctx.security}?period=5y")

      assert has_element?(lv, "#period a.active", "5 J")
      assert_push_event(lv, "price-chart", %{dates: [^first | _]})
    end

    test "shows the holding of the user", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/securities/#{ctx.security}")

      assert texts(lv, "#holding dt, #holding dd") == [
               "Stück",
               "9",
               "Wert",
               "918,00\u00A0€",
               "Einstand",
               "855,00\u00A0€",
               "Gewinn",
               "+63,00\u00A0€ +7,4\u00A0%"
             ]

      refute has_element?(lv, "#holding-portfolios")
    end

    test "shows the holding per portfolio when it is in several", ctx do
      pension = portfolio_fixture(ctx.scope, %{name: "Altersvorsorge"})
      trade(ctx.scope, :buy, pension, ctx.security, Date.add(today(), -5), 1, 99)

      {:ok, lv, _html} = live(ctx.conn, ~p"/securities/#{ctx.security}")

      assert texts(lv, "#holding dd") |> hd() == "10"

      assert portfolio_texts(lv, pension) ==
               ["Altersvorsorge", "1 Stück", "102,00\u00A0€", "+3,00\u00A0€"]

      assert portfolio_texts(lv, ctx.portfolio) ==
               ["Langfristig", "9 Stück", "918,00\u00A0€", "+63,00\u00A0€"]

      assert has_element?(
               lv,
               "#holding-portfolios a:first-child[href='/holdings?portfolio=#{pension.id}']"
             )
    end

    test "updates when new prices arrive", %{conn: conn, security: security} do
      {:ok, lv, _html} = live(conn, ~p"/securities/#{security}")
      assert_push_event(lv, "price-chart", _before)

      Repo.update!(Ecto.Changeset.change(security, latest_close: price(110)))
      send(lv.pid, :market_data_updated)

      assert lv |> element("#price") |> render() =~ "110,00 €"
      assert_push_event(lv, "price-chart", %{prices: [_yesterday, today]})
      assert today == price(110)
    end

    test "marks the holdings in the navigation", %{conn: conn, security: security} do
      {:ok, lv, _html} = live(conn, ~p"/securities/#{security}")

      assert has_element?(lv, "#side-holdings.active")
      assert has_element?(lv, "#tab-portfolios.active")
      assert has_element?(lv, "main a[href='/holdings']", "Bestand")
    end
  end

  test "says so for a security the user does not hold", %{conn: conn} do
    security = security_fixture_with_prices()

    {:ok, lv, _html} = live(conn, ~p"/securities/#{security}")

    assert has_element?(lv, "#holding", "Nicht im Bestand")
    refute has_element?(lv, "#price-chart-legend")
  end

  test "shows a change in price too small to show without a sign or colour", %{conn: conn} do
    security = security_fixture_with_prices()
    Repo.update!(Ecto.Changeset.change(security, latest_close: price(100) + 150))

    {:ok, lv, _html} = live(conn, ~p"/securities/#{security}")

    assert lv |> element("#price .text-body-secondary") |> render() =~
             ~r/>\s*0,00\s€ \(0,00\s%\) heute/u
  end

  test "says so when there is no price in the period", %{conn: conn} do
    security = security_fixture(quote_feed: :manual)
    price_fixture(security, Date.shift(today(), year: -3), price(50), :pp)

    {:ok, lv, _html} = live(conn, ~p"/securities/#{security}")

    assert has_element?(lv, "#price-chart-empty", "Keine Kurse")
    assert_push_event(lv, "price-chart", %{dates: []})

    lv |> element("#period a", "Max") |> render_click()

    refute has_element?(lv, "#price-chart-empty")
  end

  test "shows that an unknown security does not exist", %{conn: conn} do
    for id <- [System.unique_integer([:positive]), "unknown", "0", "9223372036854775808"] do
      {:ok, lv, _html} = live(conn, ~p"/securities/#{id}")

      assert has_element?(lv, "h1", "Wertpapier nicht gefunden")
      assert has_element?(lv, "main a[href='/holdings']")
      refute has_element?(lv, "#period")
    end
  end

  defp portfolio_texts(lv, portfolio),
    do: texts(lv, "#holding-#{portfolio.id} :is(.fw-semibold, .small)")

  defp texts(lv, selector) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
  end
end
