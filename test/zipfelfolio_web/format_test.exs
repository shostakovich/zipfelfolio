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

  test "euros can have cents" do
    assert Format.euros(14_661_758, 2) == "146.617,58\u00A0€"
    assert Format.euros(-5, 2) == "−0,05\u00A0€"
  end

  test "amounts have cents and no € sign, as the sidebar lists them" do
    assert Format.amount(14_661_758) == "146.617,58"
    assert Format.amount(-1_230) == "−12,30"
    assert Format.amount(0) == "0,00"
  end

  test "changes in euros carry their sign" do
    assert Format.signed_euros(56_200) == "+562\u00A0€"
    assert Format.signed_euros(-123_450) == "−1.235\u00A0€"
    assert Format.signed_euros(-40) == "0\u00A0€"
  end

  test "changes in euros can have cents" do
    assert Format.signed_euros(3_850_280, 2) == "+38.502,80\u00A0€"
    assert Format.signed_euros(-2_000, 2) == "−20,00\u00A0€"
    assert Format.signed_euros(0, 2) == "0,00\u00A0€"
  end

  test "shares have German separators and only the decimal places they need" do
    assert Format.shares(52_000_000_000) == "520"
    assert Format.shares(620_000_000_000) == "6.200"
    assert Format.shares(9_320_700_000) == "93,207"
    assert Format.shares(12_345_678) == "0,12345678"
    assert Format.shares(-150_000_000_000) == "−1.500"
    assert Format.shares(-150_000_000) == "−1,5"
  end

  test "shares of a total are in percent with one decimal place by default" do
    assert Format.percent(Decimal.new("58.07")) == "58,1\u00A0%"
    assert Format.percent(Decimal.new("0.04")) == "0,0\u00A0%"
    assert Format.percent(Decimal.new("100"), 0) == "100\u00A0%"
  end

  test "changes in percent carry their sign and two decimal places" do
    assert Format.signed_percent(Decimal.new("0.38")) == "+0,38\u00A0%"
    assert Format.signed_percent(Decimal.new("-2.505")) == "−2,51\u00A0%"
    assert Format.signed_percent(Decimal.new("1234.5")) == "+1.234,50\u00A0%"
    assert Format.signed_percent(Decimal.new("0")) == "0,00\u00A0%"
  end

  test "changes in percent can have one decimal place" do
    assert Format.signed_percent(Decimal.new("12.64"), 1) == "+12,6\u00A0%"
    assert Format.signed_percent(Decimal.new("-0.04"), 1) == "0,0\u00A0%"
  end

  test "dates are German" do
    assert Format.date(~D[2026-10-09]) == "09.10.2026"
  end
end
