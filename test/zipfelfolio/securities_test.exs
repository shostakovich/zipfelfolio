defmodule Zipfelfolio.SecuritiesTest do
  use Zipfelfolio.DataCase

  import Zipfelfolio.SecuritiesFixtures

  alias Zipfelfolio.Securities
  alias Zipfelfolio.Users.Scope

  @scope %Scope{}

  describe "get_security/2" do
    test "gives any security by id, as securities are shared, and nil for an unknown one" do
      security = security_fixture()

      assert Securities.get_security(@scope, security.id) == security
      assert Securities.get_security(@scope, security.id + 1) == nil
    end
  end

  describe "store_yahoo_prices/2" do
    test "adds new days and replaces Yahoo prices, but keeps PP and manual ones" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-05], 100, :pp)
      price_fixture(security, ~D[2026-10-06], 200, :manual)
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)

      Securities.store_yahoo_prices(security, [
        {~D[2026-10-05], 101},
        {~D[2026-10-06], 201},
        {~D[2026-10-07], 301},
        {~D[2026-10-08], 401}
      ])

      assert prices_of(security) == [
               {~D[2026-10-05], 100, :pp},
               {~D[2026-10-06], 200, :manual},
               {~D[2026-10-07], 301, :yahoo},
               {~D[2026-10-08], 401, :yahoo}
             ]
    end
  end

  describe "claim_unchecked_yahoo_securities/2" do
    test "claims each unchecked Yahoo security once" do
      unchecked = security_fixture()
      security_fixture(symbol: "LDGL.DE", checked_at: ~U[2026-10-09 15:50:00.000000Z])
      security_fixture(quote_feed: :manual, symbol: nil)
      now = ~U[2026-10-09 16:00:00.000000Z]

      assert [%{id: id}] =
               Securities.claim_unchecked_yahoo_securities(~U[2026-10-09 15:45:00.000000Z], now)

      assert id == unchecked.id

      assert Securities.claim_unchecked_yahoo_securities(~U[2026-10-09 15:45:00.000000Z], now) ==
               []
    end
  end

  describe "with_same_yahoo_symbol/2" do
    test "skips a security whose symbol or feed changed" do
      security = security_fixture()

      assert Securities.with_same_yahoo_symbol(security, & &1.symbol) == "VGWL.DE"

      {:ok, _} =
        Securities.update_quote_feed(@scope, security, %{quote_feed: "yahoo", symbol: "VWRL.AS"})

      assert Securities.with_same_yahoo_symbol(security, & &1.symbol) == :skipped
    end
  end

  describe "list_closes_since/2" do
    test "starts at the last close on or before the date, or at the first one" do
      security = security_fixture()
      later = security_fixture(name: "Später notiert")

      for {date, close} <- [{~D[2026-10-01], 1}, {~D[2026-10-02], 2}, {~D[2026-10-05], 5}],
          do: price_fixture(security, date, close, :pp)

      price_fixture(later, ~D[2026-10-05], 50, :pp)
      price_fixture(security_fixture(name: "Nicht gefragt"), ~D[2026-10-05], 9, :pp)

      assert Enum.sort(Securities.list_closes_since([security.id, later.id], ~D[2026-10-03])) ==
               [
                 {security.id, ~D[2026-10-02], 2},
                 {security.id, ~D[2026-10-05], 5},
                 {later.id, ~D[2026-10-05], 50}
               ]
    end
  end

  describe "last_price_date/1" do
    test "is the date of the last price from any source" do
      security = security_fixture()
      assert Securities.last_price_date(security) == nil

      price_fixture(security, ~D[2026-10-01], 100, :pp)
      price_fixture(security, ~D[2026-09-01], 100, :yahoo)

      assert Securities.last_price_date(security) == ~D[2026-10-01]
    end
  end

  describe "update_quote_feed/3" do
    setup do
      security =
        security_fixture(fetched_at: ~U[2026-10-09 16:00:00.000000Z], fetch_error: "Fehler")

      price_fixture(security, ~D[2026-10-05], 100, :pp)
      price_fixture(security, ~D[2026-10-06], 200, :manual)
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)
      %{security: security}
    end

    test "a new symbol drops the Yahoo prices of the old one", %{security: security} do
      assert {:ok, updated} =
               Securities.update_quote_feed(@scope, security, %{
                 quote_feed: "yahoo",
                 symbol: "VWRL.AS"
               })

      assert updated.symbol == "VWRL.AS"
      assert updated.quote_feed_set_by_user
      assert {updated.fetched_at, updated.fetch_error} == {nil, nil}
      assert prices_of(security) == [{~D[2026-10-05], 100, :pp}, {~D[2026-10-06], 200, :manual}]
    end

    test "a switch back to Yahoo drops the Yahoo prices and the quote of the old symbol", %{
      security: security
    } do
      {:ok, manual} = Securities.update_quote_feed(@scope, security, %{quote_feed: "manual"})

      security
      |> Ecto.Changeset.change(latest_close: 1, latest_date: ~D[2026-10-07])
      |> Repo.update!()

      assert {:ok, updated} = Securities.update_quote_feed(@scope, manual, %{quote_feed: "yahoo"})

      assert {updated.latest_close, updated.latest_date} == {nil, nil}
      assert prices_of(security) == [{~D[2026-10-05], 100, :pp}, {~D[2026-10-06], 200, :manual}]
    end

    test "switching to manual keeps the Yahoo prices", %{security: security} do
      assert {:ok, updated} =
               Securities.update_quote_feed(@scope, security, %{quote_feed: "manual", symbol: ""})

      assert updated.quote_feed == :manual
      assert length(prices_of(security)) == 3
    end

    test "Yahoo needs a symbol", %{security: security} do
      assert {:error, changeset} =
               Securities.update_quote_feed(@scope, security, %{quote_feed: "yahoo", symbol: ""})

      assert "can't be blank" in errors_on(changeset).symbol
    end
  end

  describe "manual prices" do
    test "a manual price replaces one from Yahoo and accepts a decimal comma" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)

      assert {:ok, _price} =
               Securities.add_manual_price(@scope, security, %{
                 "date" => "2026-10-07",
                 "close" => "166,5"
               })

      assert prices_of(security) == [{~D[2026-10-07], 16_650_000_000, :manual}]
    end

    test "a day with a price from PP keeps it" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-05], 100, :pp)

      assert {:error, changeset} =
               Securities.add_manual_price(@scope, security, %{
                 "date" => "2026-10-05",
                 "close" => "1"
               })

      assert errors_on(changeset).date == ["hat schon einen Kurs aus Portfolio Performance"]
      assert prices_of(security) == [{~D[2026-10-05], 100, :pp}]
    end

    test "accepts German and English notation" do
      security = security_fixture()

      assert {:ok, _price} =
               Securities.add_manual_price(@scope, security, %{
                 "date" => "2026-10-06",
                 "close" => "1.234,56"
               })

      assert {:ok, _price} =
               Securities.add_manual_price(@scope, security, %{
                 "date" => "2026-10-07",
                 "close" => "1234.5"
               })

      assert prices_of(security) == [
               {~D[2026-10-06], 123_456_000_000, :manual},
               {~D[2026-10-07], 123_450_000_000, :manual}
             ]
    end

    test "refuses a day in the future and an absurd price" do
      security = security_fixture()
      tomorrow = Date.utc_today() |> Date.add(2) |> Date.to_iso8601()

      assert {:error, changeset} =
               Securities.add_manual_price(@scope, security, %{
                 "date" => tomorrow,
                 "close" => "1e30"
               })

      assert errors_on(changeset).date == ["darf nicht in der Zukunft liegen"]
      assert errors_on(changeset).close == ["must be less than 1000000000"]
    end

    test "the newest price is the latest quote of a security with manual prices" do
      security = security_fixture(quote_feed: :manual, symbol: nil)
      price_fixture(security, ~D[2026-10-01], 100, :pp)

      {:ok, price} =
        Securities.add_manual_price(@scope, security, %{"date" => "2026-10-07", "close" => "2"})

      assert %{latest_date: ~D[2026-10-07], latest_close: 200_000_000} = Repo.reload!(security)

      {:ok, _price} = Securities.delete_manual_price(@scope, security, price.id)
      assert %{latest_date: ~D[2026-10-01], latest_close: 100} = Repo.reload!(security)
    end

    test "needs a date and a positive price" do
      security = security_fixture()

      assert {:error, changeset} =
               Securities.add_manual_price(@scope, security, %{"date" => "", "close" => "-1"})

      assert errors_on(changeset).date == ["can't be blank"]
      assert errors_on(changeset).close == ["must be greater than 0"]
    end

    test "only manual prices can be listed and deleted" do
      security = security_fixture()
      manual = price_fixture(security, ~D[2026-10-06], 200, :manual)
      yahoo = price_fixture(security, ~D[2026-10-07], 300, :yahoo)

      assert Enum.map(Securities.list_manual_prices(@scope, security), & &1.id) == [manual.id]

      assert {:error, :not_found} = Securities.delete_manual_price(@scope, security, yahoo.id)

      assert {:ok, %{date: ~D[2026-10-06]}} =
               Securities.delete_manual_price(@scope, security, manual.id)

      assert prices_of(security) == [{~D[2026-10-07], 300, :yahoo}]
    end
  end

  describe "compositions" do
    test "replace_composition/3 stores one per security, and list_compositions/1 finds them" do
      [world, em, other] = for isin <- ~w(A B C), do: security_fixture(isin: isin)
      now = ~U[2026-10-09 16:00:00.000000Z]
      Securities.replace_composition(world, %{countries: %{"US" => 1}, sectors: %{}}, now)
      composition_fixture(em, %{"BR" => 1})
      composition_fixture(other, %{"JP" => 1})
      later = DateTime.add(now, 1, :day)

      Securities.replace_composition(
        world,
        %{countries: %{"JP" => 1}, sectors: %{"E" => 1}},
        later
      )

      compositions = Securities.list_compositions([world.id, em.id])

      assert compositions |> Map.keys() |> Enum.sort() == [world.id, em.id]
      assert %{countries: %{"JP" => 1}, sectors: %{"E" => 1}} = compositions[world.id]
      assert compositions[world.id].fetched_at == later
      assert %{countries: %{"BR" => 1}} = compositions[em.id]
    end

    test "list_securities_with_isin/0 leaves out securities without an ISIN and retired ones" do
      with_isin = security_fixture(isin: "IE00B3RBWM25")
      security_fixture(isin: nil)
      security_fixture(isin: "")
      security_fixture(isin: "IE00B4L5Y983", retired: true)

      assert Securities.list_securities_with_isin() == [with_isin]
    end
  end
end
