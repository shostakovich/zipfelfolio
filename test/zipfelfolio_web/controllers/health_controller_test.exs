defmodule ZipfelfolioWeb.HealthControllerTest do
  use ZipfelfolioWeb.ConnCase

  test "GET /up reports the database as up", %{conn: conn} do
    assert conn |> get(~p"/up") |> json_response(200) == %{"status" => "up"}
  end
end
