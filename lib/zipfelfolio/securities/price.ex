defmodule Zipfelfolio.Securities.Price do
  @moduledoc "A closing price × 10⁸ per security and day. A price from PP wins over a fetched one."
  use Zipfelfolio.Schema

  schema "prices" do
    belongs_to :security, Zipfelfolio.Securities.Security
    field :date, :date
    field :close, :integer
    field :source, Ecto.Enum, values: [:pp, :yahoo, :manual]
  end
end
