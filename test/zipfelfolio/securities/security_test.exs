defmodule Zipfelfolio.Securities.SecurityTest do
  use ExUnit.Case, async: true

  alias Zipfelfolio.Securities.Security

  defp security(attributes), do: %Security{attributes: attributes}

  test "the TER is PP's built-in attribute, as a fraction" do
    assert Decimal.equal?(Security.ter(security(%{"ter" => 0.0022})), Decimal.new("0.0022"))
    assert Decimal.equal?(Security.ter(security(%{"ter" => 0})), Decimal.new(0))
    assert Security.ter(security(%{"vendor" => "iShares"})) == nil
    assert Security.ter(security(%{"ter" => "0,22 %"})) == nil
    assert Security.ter(%Security{attributes: nil}) == nil
  end

  test "the fund size is PP's built-in attribute, in cents" do
    assert Security.fund_size(security(%{"aum" => 1_780_000_000_000})) == 1_780_000_000_000
    assert Security.fund_size(security(%{})) == nil
    assert Security.fund_size(security(%{"aum" => 1.5})) == nil
  end
end
