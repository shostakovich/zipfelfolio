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
        Zipfelfolio.Receipts.Recognition,
        ZipfelfolioWeb.Endpoint
      ] ++ daily_job() ++ resume_recognition() ++ paperless_job()

    Supervisor.start_link(children, strategy: :one_for_one, name: Zipfelfolio.Supervisor)
  end

  defp daily_job do
    if Application.fetch_env!(:zipfelfolio, Zipfelfolio.MarketData)[:daily_job],
      do: [Zipfelfolio.MarketData.Job],
      else: []
  end

  defp resume_recognition do
    if Application.fetch_env!(:zipfelfolio, Zipfelfolio.Receipts)[:resume_on_start],
      do: [{Task, &Zipfelfolio.Receipts.resume_recognition/0}],
      else: []
  end

  defp paperless_job do
    if Application.fetch_env!(:zipfelfolio, Zipfelfolio.Receipts)[:paperless_job],
      do: [Zipfelfolio.Receipts.PaperlessJob],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    ZipfelfolioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
