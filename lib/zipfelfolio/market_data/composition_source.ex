defmodule Zipfelfolio.MarketData.CompositionSource do
  @moduledoc """
  A source of the composition of a security by its ISIN: its weights per country, as ISO 3166 code,
  and per sector. Without its API key it is not available and must not be asked.
  """

  @type composition :: %{countries: %{String.t() => number}, sectors: %{String.t() => number}}
  @type reason :: :not_found | :unreachable | :invalid_response | {:http_status, pos_integer}

  @callback available?() :: boolean
  @callback composition(isin :: String.t()) :: {:ok, composition} | {:error, reason}
end
