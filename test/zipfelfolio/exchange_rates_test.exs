defmodule Zipfelfolio.ExchangeRatesTest do
  use Zipfelfolio.DataCase

  alias Zipfelfolio.ExchangeRates

  defp rate(currency, date, value), do: {currency, date, Decimal.new(value)}

  test "a lookup on a Saturday returns Friday's rate" do
    ExchangeRates.store([
      rate("USD", ~D[2026-10-08], "1.1652"),
      rate("USD", ~D[2026-10-09], "1.1701")
    ])

    assert ExchangeRates.rate_on("USD", ~D[2026-10-10]) == Decimal.new("1.1701")
    assert ExchangeRates.rate_on("USD", ~D[2026-10-08]) == Decimal.new("1.1652")
  end

  test "there is no rate before the first one, and the euro is always 1" do
    ExchangeRates.store([rate("USD", ~D[2026-10-08], "1.1652")])

    assert ExchangeRates.rate_on("USD", ~D[2026-10-07]) == nil
    assert ExchangeRates.rate_on("EUR", ~D[1990-01-01]) == Decimal.new(1)
  end

  test "the latest rate of a currency comes with its date" do
    ExchangeRates.store([
      rate("USD", ~D[2026-10-08], "1.1652"),
      rate("USD", ~D[2026-10-09], "1.1701"),
      rate("JPY", ~D[2026-10-10], "161.2")
    ])

    assert %{date: ~D[2026-10-09], rate: rate} = ExchangeRates.latest("USD")
    assert rate == Decimal.new("1.1701")
    assert ExchangeRates.latest("CHF") == nil
  end

  test "storing a rate again replaces it" do
    ExchangeRates.store([rate("USD", ~D[2026-10-08], "1.1652")])

    ExchangeRates.store([
      rate("USD", ~D[2026-10-08], "1.1653"),
      rate("JPY", ~D[2026-10-09], "161.2")
    ])

    assert ExchangeRates.rate_on("USD", ~D[2026-10-08]) == Decimal.new("1.1653")
    assert ExchangeRates.last_date() == ~D[2026-10-09]
  end

  test "rates since a date start at the last one on or before it, or at the first one" do
    ExchangeRates.store([
      rate("USD", ~D[2026-10-01], "1.1"),
      rate("USD", ~D[2026-10-02], "1.2"),
      rate("USD", ~D[2026-10-05], "1.5"),
      rate("JPY", ~D[2026-10-05], "160"),
      rate("CHF", ~D[2026-10-05], "0.9")
    ])

    assert Enum.sort(ExchangeRates.list_rates_since(["USD", "JPY"], ~D[2026-10-03])) == [
             rate("JPY", ~D[2026-10-05], "160"),
             rate("USD", ~D[2026-10-02], "1.2"),
             rate("USD", ~D[2026-10-05], "1.5")
           ]
  end

  test "without rates there is no last date" do
    assert ExchangeRates.last_date() == nil
  end
end
