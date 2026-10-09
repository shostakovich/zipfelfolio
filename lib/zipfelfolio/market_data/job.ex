defmodule Zipfelfolio.MarketData.Job do
  @moduledoc """
  Runs `Zipfelfolio.MarketData.run_daily/1` every day at 18:00 local time: Xetra closes at 17:30,
  the ECB publishes around 16:00. At boot it runs at once when the last run is older than the
  last 18:00 slot. There are no retries; the next run fills the gaps.
  """
  use GenServer

  require Logger

  alias Zipfelfolio.{LocalTime, MarketData}

  @at ~T[18:00:00]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    last_run = MarketData.last_run()
    now = LocalTime.now()

    if due?(last_run && LocalTime.from_utc(last_run.ran_at), now),
      do: send(self(), :run),
      else: schedule(now)

    {:ok, nil}
  end

  @impl true
  def handle_info(:run, state) do
    # The next slot counts from the start, so a run across 18:00 does not skip that slot.
    started = LocalTime.now()
    run()
    schedule(started)
    {:noreply, state}
  end

  # A crash would restart the job, which would run again at once.
  defp run do
    MarketData.run_daily()
  rescue
    error ->
      Logger.error(
        "Daily market data run failed: " <> Exception.format(:error, error, __STACKTRACE__)
      )
  end

  defp schedule(now) do
    delay = DateTime.diff(LocalTime.to_utc(next_run(now)), DateTime.utc_now(), :millisecond)
    Process.send_after(self(), :run, max(delay, 0))
  end

  @doc "Whether the last run, in local time, is older than the last slot before `now`."
  def due?(nil, _now), do: true

  def due?(last_run, now),
    do: NaiveDateTime.before?(last_run, NaiveDateTime.add(next_run(now), -1, :day))

  @doc "The first slot after `now`, in local time."
  def next_run(now) do
    today = NaiveDateTime.new!(NaiveDateTime.to_date(now), @at)
    if NaiveDateTime.before?(now, today), do: today, else: NaiveDateTime.add(today, 1, :day)
  end
end
