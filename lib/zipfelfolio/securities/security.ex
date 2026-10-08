defmodule Zipfelfolio.Securities.Security do
  @moduledoc """
  A security, shared by all users. `quote_feed` and `symbol` say where prices come from; once a
  user sets them, a PP import leaves them alone.
  """
  use Zipfelfolio.Schema

  import Ecto.Changeset

  schema "securities" do
    field :name, :string
    field :isin, :string
    field :wkn, :string
    field :currency, :string
    field :note, :string
    field :retired, :boolean, default: false
    field :attributes, :map, default: %{}
    field :pp_feed, :string
    field :pp_ticker, :string
    field :quote_feed, Ecto.Enum, values: [:yahoo, :manual], default: :manual
    field :symbol, :string
    field :quote_feed_set_by_user, :boolean, default: false
    field :latest_date, :date
    field :latest_close, :integer

    has_many :prices, Zipfelfolio.Securities.Price

    timestamps()
  end

  def quote_feed_changeset(security, attrs) do
    security
    |> cast(attrs, [:quote_feed, :symbol])
    |> validate_required([:quote_feed])
    |> then(fn cs ->
      if get_field(cs, :quote_feed) == :yahoo, do: validate_required(cs, [:symbol]), else: cs
    end)
    |> put_change(:quote_feed_set_by_user, true)
  end
end
