defmodule Zipfelfolio.NetWorthRealFileTest do
  @moduledoc """
  Compares net worth with PP's for the owner's real PP file:

      PP_FILE=/path/to/file.portfolio PP_NET_WORTH_DATE=2026-10-08 PP_NET_WORTH=123456.78 \\
        mix test --only pp_net_worth

  `PP_NET_WORTH` is the total of PP's statement of assets on that date, in euros, as
  `123.456,78` or `123456.78`. The test fetches the ECB's rates, as PP converts at them. No real
  numbers end up in the repository.
  """
  use Zipfelfolio.DataCase

  import Zipfelfolio.UsersFixtures

  alias Zipfelfolio.{ExchangeRates, Portfolios, PPImport}
  alias Zipfelfolio.MarketData.ECB

  @moduletag :pp_net_worth
  @moduletag timeout: :infinity

  test "net worth on the given date equals PP's" do
    scope = user_scope_fixture()
    date = Date.from_iso8601!(System.fetch_env!("PP_NET_WORTH_DATE"))
    expected = cents(System.fetch_env!("PP_NET_WORTH"))

    assert {:ok, _summary} = PPImport.run(scope, System.fetch_env!("PP_FILE"))
    assert {:ok, rates} = ECB.rates(Date.add(date, -14))
    ExchangeRates.store(rates)

    assert %{^date => net_worth} = Portfolios.net_worth(scope, [date])
    assert net_worth == expected, "zipfelfolio: #{net_worth} ct, PP: #{expected} ct"
  end

  defp cents(euros) do
    euros =
      if euros =~ ",",
        do: euros |> String.replace(".", "") |> String.replace(",", "."),
        else: euros

    euros |> Decimal.new() |> Decimal.mult(100) |> Decimal.to_integer()
  end
end
