defmodule ZipfelfolioWeb.HealthController do
  @moduledoc false
  use ZipfelfolioWeb, :controller

  alias Ecto.Adapters.SQL

  def show(conn, _params) do
    case SQL.query(Zipfelfolio.Repo, "SELECT 1", []) do
      {:ok, _result} ->
        json(conn, %{status: "up"})

      {:error, error} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "down", error: Exception.message(error)})
    end
  end
end
