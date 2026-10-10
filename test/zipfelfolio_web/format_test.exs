defmodule ZipfelfolioWeb.FormatTest do
  use ExUnit.Case, async: true

  alias ZipfelfolioWeb.Format

  test "prices have two to four decimal places and German separators" do
    assert Format.price(16_666_000_000, "EUR") == "166,66 EUR"
    assert Format.price(16_600_000_000, "EUR") == "166,00 EUR"
    assert Format.price(123_456_780_000, "USD") == "1.234,5678 USD"
    assert Format.price(123_456_789_999, "USD") == "1.234,5679 USD"
    assert Format.price(100_000_000_000_000, nil) == "1.000.000,00"
    assert Format.price(nil, "EUR") == "–"
  end

  test "euros are whole, with German separators, a real minus and a € that never wraps" do
    assert Format.euros(14_911_750) == "149.118\u00A0€"
    assert Format.euros(14_911_749) == "149.117\u00A0€"
    assert Format.euros(-123_456) == "−1.235\u00A0€"
    assert Format.euros(0) == "0\u00A0€"
  end

  test "changes in euros carry their sign" do
    assert Format.signed_euros(56_200) == "+562\u00A0€"
    assert Format.signed_euros(-123_450) == "−1.235\u00A0€"
    assert Format.signed_euros(-40) == "0\u00A0€"
  end

  test "changes in percent carry their sign and two decimal places" do
    assert Format.signed_percent(Decimal.new("0.38")) == "+0,38\u00A0%"
    assert Format.signed_percent(Decimal.new("-2.505")) == "−2,51\u00A0%"
    assert Format.signed_percent(Decimal.new("1234.5")) == "+1.234,50\u00A0%"
    assert Format.signed_percent(Decimal.new("0")) == "0,00\u00A0%"
  end

  test "dates are German" do
    assert Format.date(~D[2026-10-09]) == "09.10.2026"
  end
end
