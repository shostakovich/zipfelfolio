defmodule Zipfelfolio.SecuritiesFixtures do
  @moduledoc "Securities, prices and compositions for tests."

  alias Zipfelfolio.Repo
  alias Zipfelfolio.Securities.{AttributeType, Composition, Price, Security}

  def security_fixture(attrs \\ %{}) do
    Repo.insert!(
      struct!(
        %Security{
          name: "Vanguard FTSE All-World",
          currency: "EUR",
          quote_feed: :yahoo,
          symbol: "VGWL.DE"
        },
        attrs
      )
    )
  end

  def price_fixture(%Security{id: id}, date, close, source) do
    Repo.insert!(%Price{security_id: id, date: date, close: close, source: source})
  end

  @doc """
  An attribute type as PP defines it, for securities unless `target` names another class;
  `converter` is the short name of PP's converter, e.g. `StringConverter`.
  """
  def attribute_type_fixture(pp_id, name, converter, target \\ "Security") do
    Repo.insert!(%AttributeType{
      pp_id: pp_id,
      name: name,
      column_label: name,
      target: "name.abuchen.portfolio.model." <> target,
      converter: "name.abuchen.portfolio.model.AttributeType$" <> converter
    })
  end

  @doc "A composition of the security as DivvyDiary delivered it at `fetched_at`."
  def composition_fixture(
        %Security{id: id},
        countries,
        sectors \\ %{},
        fetched_at \\ ~U[2026-10-08 12:00:00.000000Z]
      ) do
    Repo.insert!(%Composition{
      security_id: id,
      countries: countries,
      sectors: sectors,
      fetched_at: fetched_at
    })
  end

  def composition_of(%Security{id: id}), do: Repo.get_by(Composition, security_id: id)

  @doc "A price as stored, × 10⁸."
  def price(value), do: round(value * 100_000_000)

  @doc "The stored prices of a security as `{date, close, source}`, oldest first."
  def prices_of(%Security{} = security) do
    security
    |> then(&Zipfelfolio.Securities.list_prices(%Zipfelfolio.Users.Scope{}, &1))
    |> Enum.map(&{&1.date, &1.close, &1.source})
  end
end
