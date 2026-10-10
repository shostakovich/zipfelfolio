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

  @doc "A currency as prices name it: `€` for euros, otherwise its code."
  def currency("EUR"), do: "€"
  def currency(code), do: code

  @doc "A change of a price × 10⁸ with its sign, e.g. `−1,06 €`; none when it rounds to zero."
  def signed_price(change, currency) do
    unchanged = price(0, currency)

    case price(abs(change), currency) do
      ^unchanged -> unchanged
      shown when change > 0 -> "+" <> shown
      shown -> "−" <> shown
    end
  end

  @doc """
  Cents as whole euros, e.g. `149.118 €`, or with `places` decimal places; the € never wraps onto
  a line of its own.
  """
  def euros(cents, places \\ 0), do: number(Decimal.div(cents, 100), places, "") <> "\u00A0€"

  @doc "Cents as euros with two decimal places and without the € sign, e.g. `146.617,58`."
  def amount(cents), do: number(Decimal.div(cents, 100), 2, "")

  @doc "A change in cents as whole euros with its sign, e.g. `+562 €`, or with `places`."
  def signed_euros(cents, places \\ 0),
    do: number(Decimal.div(cents, 100), places, "+") <> "\u00A0€"

  @doc "Shares × 10⁸ with as many decimal places as they have, e.g. `6.200` or `93,207`."
  def shares(shares) do
    shares = shares |> Decimal.div(100_000_000) |> Decimal.normalize()
    number(shares, max(-shares.exp, 0), "")
  end

  @doc "A share of a total in percent, e.g. `58,1 %`; the % never wraps onto a line of its own."
  def percent(%Decimal{} = percent, places \\ 1), do: number(percent, places, "") <> "\u00A0%"

  @doc """
  A fund size in cents in billions with one decimal place, e.g. `17,8 Mrd. €`, below 100 million
  in whole millions, e.g. `85 Mio. €`; it never wraps.
  """
  def fund_size(nil, _currency), do: "–"

  def fund_size(cents, currency) do
    amount =
      if cents >= 10_000_000_000,
        do: number(Decimal.div(cents, 100_000_000_000), 1, "") <> "\u00A0Mrd.",
        else: number(Decimal.div(cents, 100_000_000), 0, "") <> "\u00A0Mio."

    amount <> "\u00A0" <> currency(currency)
  end

  @doc "A TER, a fraction, in percent with two decimal places, e.g. `0,22 %`."
  def ter(nil), do: "–"
  def ter(%Decimal{} = ter), do: ter |> Decimal.mult(100) |> percent(2)

  @doc "An exchange rate with the decimal places it has, e.g. `1,1652`."
  def rate(%Decimal{} = rate) do
    rate = Decimal.normalize(rate)
    number(rate, max(-rate.exp, 0), "")
  end

  @doc """
  A change in percent with its sign and two or `places` decimal places, e.g. `+0,38 %`; the %
  never wraps onto a line of its own.
  """
  def signed_percent(%Decimal{} = percent, places \\ 2),
    do: number(percent, places, "+") <> "\u00A0%"

  @doc "`part` in percent of `whole`, for `percent/2` and `signed_percent/2`."
  def percent_of(part, whole), do: part |> Decimal.mult(100) |> Decimal.div(whole)

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

  def date(%DateTime{} = utc),
    do: utc |> LocalTime.from_utc() |> NaiveDateTime.to_date() |> date()

  def datetime(nil), do: "–"

  def datetime(%DateTime{} = utc),
    do: utc |> LocalTime.from_utc() |> Calendar.strftime("%d.%m.%Y, %H:%M")
end
