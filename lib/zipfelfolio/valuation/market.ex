defmodule Zipfelfolio.Valuation.Market do
  @moduledoc """
  Closing prices, latest quotes and ECB rates for valuing holdings, looked up as PP does. Pure;
  the contexts load what it holds. Prices × 10⁸, amounts in cents.
  """

  alias Zipfelfolio.Securities.Security

  defstruct securities: %{}, closes: %{}, rates: %{}

  @doc """
  Builds a market from securities with their latest quote, closes as `{security_id, date, close}`
  and ECB rates as `{currency, date, rate}`.
  """
  def new(securities, closes, rates) do
    %__MODULE__{
      securities: Map.new(securities, &{&1.id, &1}),
      closes: newest_first(closes),
      rates: newest_first(rates)
    }
  end

  defp newest_first(rows) do
    rows
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
    |> Map.new(fn {key, series} -> {key, Enum.sort_by(series, &elem(&1, 0), {:desc, Date})} end)
  end

  def currency(%__MODULE__{securities: securities}, security_id),
    do: securities[security_id].currency

  @doc """
  The price of a security on `date`, as PP takes it: the latest quote from its day on unless a
  close is newer, else the close of the day or the last one before it, or the first close for an
  earlier day. Nil without any price.
  """
  def price(%__MODULE__{} = market, security_id, date) do
    closes = Map.get(market.closes, security_id, [])
    quote = latest_quote(market.securities[security_id])

    if quote_applies?(quote, closes, date), do: elem(quote, 1), else: on(closes, date)
  end

  defp latest_quote(%Security{latest_date: %Date{} = date, latest_close: close})
       when is_integer(close),
       do: {date, close}

  defp latest_quote(_security), do: nil

  defp quote_applies?(nil, _closes, _date), do: false
  defp quote_applies?(_quote, [] = _closes, _date), do: true

  defp quote_applies?({quote_date, _close}, [{last_close_date, _last_close} | _], date),
    do: not Date.before?(date, quote_date) and not Date.before?(quote_date, last_close_date)

  @doc """
  Converts an amount in `currency` to euro cents at the ECB rate on `date` as PP does: with the
  inverse rate to ten places, rounded half down; without any rate, it stays as it is.
  """
  def to_euros(_market, amount, "EUR", _date), do: amount

  def to_euros(%__MODULE__{rates: rates}, amount, currency, date) do
    case on(Map.get(rates, currency, []), date) do
      nil ->
        amount

      rate ->
        Decimal.new(1)
        |> Decimal.div(rate)
        |> Decimal.round(10, :half_down)
        |> Decimal.mult(amount)
        |> Decimal.round(0, :half_down)
        |> Decimal.to_integer()
    end
  end

  # The value on `date` or the last one before it; the first one for an earlier day, as in PP.
  defp on([], _date), do: nil

  defp on(series, date) do
    Enum.find_value(series, fn {day, value} -> if not Date.after?(day, date), do: value end) ||
      series |> List.last() |> elem(1)
  end
end
