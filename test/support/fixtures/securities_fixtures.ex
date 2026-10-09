defmodule Zipfelfolio.SecuritiesFixtures do
  @moduledoc "Securities and prices for tests."

  alias Zipfelfolio.Repo
  alias Zipfelfolio.Securities.{Price, Security}

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

  @doc "The stored prices of a security as `{date, close, source}`, oldest first."
  def prices_of(%Security{} = security) do
    security
    |> then(&Zipfelfolio.Securities.list_prices(%Zipfelfolio.Users.Scope{}, &1))
    |> Enum.map(&{&1.date, &1.close, &1.source})
  end
end
