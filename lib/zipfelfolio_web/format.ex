defmodule ZipfelfolioWeb.Format do
  @moduledoc "German formats for amounts, dates and times; times in the host's local time."

  alias Zipfelfolio.LocalTime

  @doc "A price × 10⁸ with two to four decimal places, e.g. `1.234,5678 EUR`."
  def price(nil, _currency), do: "–"

  def price(close, currency) do
    amount =
      close
      |> Decimal.new()
      |> Decimal.div(100_000_000)
      |> Decimal.round(4)
      |> Decimal.normalize()

    places = -amount.exp |> max(2) |> min(4)

    [whole, fraction] =
      amount |> Decimal.round(places) |> Decimal.to_string(:normal) |> String.split(".")

    Enum.join([group_thousands(whole) <> "," <> fraction, currency], " ") |> String.trim()
  end

  @doc "Cents as whole euros, e.g. `149.118 €`."
  def euros(cents), do: number(Decimal.div(cents, 100), 0, "") <> " €"

  @doc "A change in cents as whole euros with its sign, e.g. `+562 €`."
  def signed_euros(cents), do: number(Decimal.div(cents, 100), 0, "+") <> " €"

  @doc "A change in percent with its sign, e.g. `+0,38 %`; the % never wraps onto a line of its own."
  def signed_percent(%Decimal{} = percent), do: number(percent, 2, "+") <> "\u00A0%"

  # German notation with a real minus sign; `plus` goes before a positive number.
  defp number(decimal, places, plus) do
    rounded = Decimal.round(decimal, places)

    sign =
      cond do
        Decimal.positive?(rounded) -> plus
        Decimal.negative?(rounded) -> "−"
        true -> ""
      end

    [whole | fraction] =
      rounded |> Decimal.abs() |> Decimal.to_string(:normal) |> String.split(".")

    sign <> group_thousands(whole) <> Enum.map_join(fraction, &("," <> &1))
  end

  defp group_thousands("-" <> digits), do: "-" <> group_thousands(digits)

  defp group_thousands(digits) do
    digits
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map_join(".", &Enum.join/1)
  end

  def date(nil), do: "–"
  def date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  def datetime(nil), do: "–"

  def datetime(%DateTime{} = utc),
    do: utc |> LocalTime.from_utc() |> Calendar.strftime("%d.%m.%Y, %H:%M")
end
