defmodule Zipfelfolio.MarketData.HTTPTest do
  use ExUnit.Case, async: true

  alias Zipfelfolio.MarketData.HTTP

  # Redirects to `to`, or tells the test about the request it got.
  defmodule Stub do
    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, {:redirect, to}),
      do: conn |> put_resp_header("location", to) |> send_resp(302, "")

    def call(conn, {:record, test}) do
      send(test, {:request, conn.req_headers})
      send_resp(conn, 200, "redirected")
    end
  end

  defp serve(opts) do
    server = {Bandit, plug: {Stub, opts}, ip: :loopback, port: 0, startup_log: false}
    pid = start_supervised!(server, id: make_ref())
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/"
  end

  test "does not follow a redirect of a request with headers, which may carry an API key" do
    url = serve({:redirect, serve({:record, self()})})

    assert {:ok, 302, _body} = HTTP.get(url, [], [{"x-api-key", "secret"}])
    refute_received {:request, _headers}
  end

  test "follows a redirect of a request without headers" do
    url = serve({:redirect, serve({:record, self()})})

    assert HTTP.get(url, []) == {:ok, 200, "redirected"}
  end
end
