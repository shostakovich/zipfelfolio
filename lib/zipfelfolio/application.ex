defmodule Zipfelfolio.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Zipfelfolio.Repo,
      {Phoenix.PubSub, name: Zipfelfolio.PubSub},
      ZipfelfolioWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Zipfelfolio.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ZipfelfolioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
