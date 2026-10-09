defmodule Zipfelfolio.FakePriceFeed do
  @moduledoc """
  The price feed in tests. Answers with the function given to `stub/1` and tells the test about
  each call as `{:chart, symbol, from}`; without a stub, Yahoo is unreachable.
  """
  @behaviour Zipfelfolio.MarketData.PriceFeed

  def stub(fun) do
    Application.put_env(:zipfelfolio, __MODULE__, {self(), fun})
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:zipfelfolio, __MODULE__) end)
  end

  @doc "A chart in EUR with the given closes and a latest quote of `quote_close`."
  def chart_result(closes, quote_close \\ 16_666_000_000, currency \\ "EUR") do
    %{
      currency: currency,
      closes: closes,
      quote: %{at: ~U[2026-10-09 15:35:00.000000Z], date: ~D[2026-10-09], close: quote_close}
    }
  end

  @impl true
  def chart(symbol, from, now) do
    case Application.get_env(:zipfelfolio, __MODULE__) do
      {test, fun} ->
        send(test, {:chart, symbol, from})
        fun.(symbol, from, now)

      nil ->
        {:error, :unreachable}
    end
  end
end

defmodule Zipfelfolio.FakeRateSource do
  @moduledoc "The rate source in tests, like `Zipfelfolio.FakePriceFeed`; reports `{:rates, from}`."
  @behaviour Zipfelfolio.MarketData.RateSource

  def stub(fun) do
    Application.put_env(:zipfelfolio, __MODULE__, {self(), fun})
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:zipfelfolio, __MODULE__) end)
  end

  @impl true
  def rates(from) do
    case Application.get_env(:zipfelfolio, __MODULE__) do
      {test, fun} ->
        send(test, {:rates, from})
        fun.(from)

      nil ->
        {:ok, []}
    end
  end
end
