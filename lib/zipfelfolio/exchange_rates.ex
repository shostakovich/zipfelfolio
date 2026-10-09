defmodule Zipfelfolio.ExchangeRates do
  @moduledoc """
  ECB reference rates, as quoted: 1 EUR = rate × currency. Shared by all users; the daily job
  stores them, calculations look them up.
  """

  import Ecto.Query, warn: false

  alias Zipfelfolio.ExchangeRates.ExchangeRate
  alias Zipfelfolio.Repo

  @doc "Stores `{currency, date, rate}` tuples; a rate stored again replaces the old one."
  def store(rates) do
    rates
    |> Enum.map(fn {currency, date, rate} -> %{currency: currency, date: date, rate: rate} end)
    |> Enum.chunk_every(5000)
    |> Enum.each(
      &Repo.insert_all(ExchangeRate, &1,
        on_conflict: {:replace, [:rate]},
        conflict_target: [:currency, :date]
      )
    )
  end

  @doc "The last rate on or before `date`, so weekends and holidays get the one before."
  def rate_on("EUR", _date), do: Decimal.new(1)

  def rate_on(currency, date) do
    Repo.one(
      from r in ExchangeRate,
        where: r.currency == ^currency and r.date <= ^date,
        order_by: [desc: r.date],
        limit: 1,
        select: r.rate
    )
  end

  def last_date, do: Repo.one(from r in ExchangeRate, select: max(r.date))
end
