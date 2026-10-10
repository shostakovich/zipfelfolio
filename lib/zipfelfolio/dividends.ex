defmodule Zipfelfolio.Dividends do
  @moduledoc """
  The dividends a user received, converted at the ECB rate of the pay date. Interest does not
  count. Pure; amounts in euro cents, shares × 10⁸.
  """

  alias Zipfelfolio.Portfolios.Transaction
  alias Zipfelfolio.Valuation
  alias Zipfelfolio.Valuation.Market

  @doc """
  The dividends of `transactions`, newest first, each with its pay `date`, `security`, `shares`
  (0 where PP booked none), `gross`, `taxes`, `fees` and `net`.
  """
  def received(transactions, %Market{} = market) do
    transactions
    |> Enum.filter(&(&1.type == :dividend))
    |> Enum.sort_by(& &1.date_time, {:desc, NaiveDateTime})
    |> Enum.map(&dividend(&1, market))
  end

  defp dividend(%Transaction{currency: currency} = t, market) do
    date = NaiveDateTime.to_date(t.date_time)
    euros = &Market.to_euros(market, &1, currency, date)

    %{
      date: date,
      security: Market.security(market, t.security_id),
      shares: t.shares || 0,
      gross: euros.(Valuation.gross_value(t, currency)),
      taxes: euros.(units(t, :tax)),
      fees: euros.(units(t, :fee)),
      net: euros.(t.amount)
    }
  end

  defp units(t, type), do: t.units |> Enum.filter(&(&1.type == type)) |> Enum.sum_by(& &1.amount)

  @doc """
  The dividends of `received` per year, newest first, from the first dividend's year to today's,
  each with its twelve `months`; every total as `gross` and `net`.
  """
  def by_year([], _today), do: []

  def by_year(received, %Date{} = today) do
    first = received |> Enum.map(& &1.date.year) |> Enum.min()
    last = received |> Enum.map(& &1.date.year) |> Enum.max() |> max(today.year)
    per_month = Enum.group_by(received, &{&1.date.year, &1.date.month})

    for year <- last..first//-1 do
      months = for month <- 1..12, do: total(Map.get(per_month, {year, month}, []))
      Map.merge(%{year: year, months: months}, total(months))
    end
  end

  def total(received, %Date.Range{} = range),
    do: received |> Enum.filter(&(&1.date in range)) |> total()

  defp total(rows), do: %{gross: Enum.sum_by(rows, & &1.gross), net: Enum.sum_by(rows, & &1.net)}
end
