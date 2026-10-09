defmodule Zipfelfolio.MarketData.HTTP do
  @moduledoc "GET requests over OTP's `:httpc`, with certificate and host name checks."

  # Yahoo answers requests without a browser-like user agent with 429.
  @user_agent ~c"Mozilla/5.0 (compatible; zipfelfolio)"

  @doc "Returns the status and body, or `:unreachable` when there is no response at all."
  def get(url, params) do
    uri = url |> URI.new!() |> URI.append_query(URI.encode_query(params))
    request = {uri |> URI.to_string() |> String.to_charlist(), [{~c"user-agent", @user_agent}]}
    http_options = [timeout: 120_000, connect_timeout: 15_000, ssl: ssl_options(uri.host)]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, body}} -> {:ok, status, body}
      {:error, _reason} -> {:error, :unreachable}
    end
  end

  defp ssl_options(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      depth: 99,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end
end
