defmodule Zipfelfolio.Securities.Price do
  @moduledoc """
  A closing price × 10⁸ per security and day. On the same day a price from PP wins over a manual
  one, a manual one over one from Yahoo.
  """
  use Zipfelfolio.Schema

  schema "prices" do
    belongs_to :security, Zipfelfolio.Securities.Security
    field :date, :date
    field :close, :integer
    field :source, Ecto.Enum, values: [:pp, :yahoo, :manual]
  end
end
