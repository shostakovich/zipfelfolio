defmodule Zipfelfolio.MarketData.HTTP do
  @moduledoc "GET requests over OTP's `:httpc`, with certificate and host name checks."

  # Yahoo answers requests without a browser-like user agent with 429.
  @user_agent "Mozilla/5.0 (compatible; zipfelfolio)"

  @doc """
  Returns the status and body, or `:unreachable` when there is no response at all. `headers` are
  `{name, value}` strings; a request with them does not follow redirects, as `:httpc` would send
  them, an API key among them, on to wherever a redirect points.
  """
  def get(url, params, headers \\ []) do
    uri = url |> URI.new!() |> with_query(params)
    request_headers = [{"user-agent", @user_agent} | headers]
    request = {to_charlist(URI.to_string(uri)), Enum.map(request_headers, &charlists/1)}

    http_options = [
      timeout: 120_000,
      connect_timeout: 15_000,
      ssl: ssl_options(uri.host),
      autoredirect: headers == []
    ]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, body}} -> {:ok, status, body}
      {:error, _reason} -> {:error, :unreachable}
    end
  end

  defp with_query(uri, []), do: uri
  defp with_query(uri, params), do: URI.append_query(uri, URI.encode_query(params))

  defp charlists({name, value}), do: {to_charlist(name), to_charlist(value)}

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
