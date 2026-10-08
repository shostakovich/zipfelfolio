defmodule Zipfelfolio.Securities do
  @moduledoc "Securities, their prices and attribute types; shared by all users."

  import Ecto.Query, warn: false

  alias Zipfelfolio.Repo
  alias Zipfelfolio.Securities.{Price, Security}

  def list_securities, do: Repo.all(from s in Security, order_by: [s.retired, s.name])

  def list_prices(%Security{id: id}),
    do: Repo.all(from p in Price, where: p.security_id == ^id, order_by: p.date)

  @doc "Sets where prices come from; a later PP import keeps this choice."
  def update_quote_feed(%Security{} = security, attrs) do
    security
    |> Security.quote_feed_changeset(attrs)
    |> Repo.update()
  end
end
