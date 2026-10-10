defmodule Zipfelfolio.Receipts.PaperlessJob do
  @moduledoc """
  Polls the Paperless of every user who entered one, see `Zipfelfolio.Receipts.poll_paperless/1`,
  at boot and then every 15 minutes, one user after the other; one failing instance does not stop
  the others. A user who has just entered their Paperless is polled at once.
  """
  use GenServer

  require Logger

  alias Zipfelfolio.{Receipts, Users}

  @every :timer.minutes(15)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    send(self(), :poll)
    {:ok, nil}
  end

  @doc "Polls the user's Paperless soon; nothing happens where the job does not run, as in tests."
  def poll_soon(user), do: GenServer.cast(__MODULE__, {:poll, user})

  @impl true
  def handle_cast({:poll, user}, state) do
    poll(user)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    poll_all()
    Process.send_after(self(), :poll, @every)
    {:noreply, state}
  end

  @doc "Polls the Paperless of every user who entered one."
  def poll_all, do: Enum.each(Users.list_paperless_users(), &poll/1)

  # A crash would restart the job, which would poll again at once.
  defp poll(user) do
    Receipts.poll_paperless(user)
  rescue
    error ->
      Logger.error(
        "polling Paperless of user #{user.id} failed: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )
  catch
    :exit, reason ->
      Logger.error("polling Paperless of user #{user.id} failed: #{inspect(reason)}")
  end
end
