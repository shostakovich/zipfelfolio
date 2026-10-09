defmodule ZipfelfolioWeb.Format do
  @moduledoc "German formats for prices, dates and times; times in the host's local time."

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
