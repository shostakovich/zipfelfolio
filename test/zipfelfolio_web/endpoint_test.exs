defmodule ZipfelfolioWeb.EndpointTest do
  use ZipfelfolioWeb.ConnCase

  test "serves setzkasten's Figtree font", %{conn: conn} do
    conn = get(conn, "/setzkasten/fonts/Figtree-Variable.woff2")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["font/woff2"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
  end
end
