defmodule Zipfelfolio.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Zipfelfolio.Repo,
        {Phoenix.PubSub, name: Zipfelfolio.PubSub},
        {Task.Supervisor, name: Zipfelfolio.TaskSupervisor},
        ZipfelfolioWeb.Endpoint
      ] ++ daily_job()

    Supervisor.start_link(children, strategy: :one_for_one, name: Zipfelfolio.Supervisor)
  end

  defp daily_job do
    if Application.fetch_env!(:zipfelfolio, Zipfelfolio.MarketData)[:daily_job],
      do: [Zipfelfolio.MarketData.Job],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    ZipfelfolioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
