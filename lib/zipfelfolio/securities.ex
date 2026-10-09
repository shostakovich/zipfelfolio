defmodule Zipfelfolio.Securities do
  @moduledoc """
  Securities, their prices and attribute types. They are shared by all users, so every signed-in
  user may read and change them; the scope only says who is asking.
  """

  import Ecto.Query, warn: false

  alias Zipfelfolio.Repo
  alias Zipfelfolio.Securities.{Price, Security}
  alias Zipfelfolio.Users.Scope

  def list_securities(%Scope{}), do: Repo.all(from s in Security, order_by: [s.retired, s.name])

  def list_prices(%Scope{}, %Security{id: id}),
    do: Repo.all(from p in Price, where: p.security_id == ^id, order_by: p.date)

  @doc "Sets where prices come from; a later PP import keeps this choice."
  def update_quote_feed(%Scope{}, %Security{} = security, attrs) do
    security
    |> Security.quote_feed_changeset(attrs)
    |> Repo.update()
  end
end
