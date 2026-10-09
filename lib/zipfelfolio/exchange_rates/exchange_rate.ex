defmodule Zipfelfolio.ExchangeRates.ExchangeRate do
  @moduledoc "An ECB reference rate as quoted: 1 EUR = `rate` units of `currency` on `date`."
  use Zipfelfolio.Schema

  schema "exchange_rates" do
    field :currency, :string
    field :date, :date
    field :rate, :decimal
  end
end
