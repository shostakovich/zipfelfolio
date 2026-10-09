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

  test "dates are German" do
    assert Format.date(~D[2026-10-09]) == "09.10.2026"
  end
end
