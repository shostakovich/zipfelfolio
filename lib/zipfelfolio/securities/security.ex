defmodule Zipfelfolio.Securities.Security do
  @moduledoc """
  A security, shared by all users. `quote_feed` and `symbol` say where prices come from; once a
  user sets them, a PP import leaves them alone. `latest_*` is the latest quote, `fetched_at` and
  `fetch_error` the last successful and the last failed fetch, `checked_at` the last attempt.
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
    field :latest_at, :utc_datetime_usec
    field :fetched_at, :utc_datetime_usec
    field :checked_at, :utc_datetime_usec
    field :fetch_error, :string

    timestamps()
  end

  # The ids of PP's built-in attributes, which PP fixes.
  @ter "ter"
  @fund_size "aum"

  @doc "The TER from PP's attribute as a fraction, e.g. 0.002 for 0.20 %; nil without one."
  def ter(%__MODULE__{attributes: %{@ter => ter}}) when is_float(ter), do: Decimal.from_float(ter)
  def ter(%__MODULE__{attributes: %{@ter => ter}}) when is_integer(ter), do: Decimal.new(ter)
  def ter(%__MODULE__{}), do: nil

  @doc """
  The fund size from PP's attribute in cents, PP's plain amount without a currency; nil without
  one.
  """
  def fund_size(%__MODULE__{attributes: %{@fund_size => size}}) when is_integer(size), do: size
  def fund_size(%__MODULE__{}), do: nil

  @doc """
  The attributes set on the security other than TER and fund size as `{type, value}`, in the
  order of `types`, PP's attribute types of securities; a value without its type is left out.
  """
  def attributes(%__MODULE__{attributes: attributes}, types) do
    attributes = attributes || %{}

    for %{pp_id: id} = type <- types,
        id not in [@ter, @fund_size],
        attributes[id] not in [nil, ""],
        do: {type, attributes[id]}
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
