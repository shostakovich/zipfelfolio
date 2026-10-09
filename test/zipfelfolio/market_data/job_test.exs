defmodule Zipfelfolio.MarketData.JobTest do
  use Zipfelfolio.DataCase

  alias Zipfelfolio.{FakeRateSource, LocalTime, MarketData}
  alias Zipfelfolio.MarketData.{Job, JobRun}

  describe "at boot" do
    test "runs at once when a slot was missed" do
      Repo.insert!(%JobRun{
        name: "daily",
        ran_at: DateTime.add(DateTime.utc_now(:microsecond), -2, :day)
      })

      FakeRateSource.stub(fn _from -> {:ok, []} end)
      MarketData.subscribe()

      start_supervised!(Job)

      assert_receive :market_data_updated
      assert_received {:rates, _from}
    end

    test "waits when the last slot already ran" do
      Repo.insert!(%JobRun{name: "daily", ran_at: DateTime.utc_now(:microsecond)})
      FakeRateSource.stub(fn _from -> {:ok, []} end)

      start_supervised!(Job)

      refute_receive {:rates, _from}, 100
    end
  end

  test "local and UTC times convert both ways" do
    local = ~N[2026-10-09 18:00:00]
    assert local |> LocalTime.to_utc() |> LocalTime.from_utc() == local
  end

  describe "due?/2" do
    test "runs at boot when the last run is older than the last 18:00 slot" do
      assert Job.due?(~N[2026-10-08 18:00:05], ~N[2026-10-09 18:30:00])
      assert Job.due?(~N[2026-10-07 18:00:05], ~N[2026-10-09 10:00:00])
      assert Job.due?(nil, ~N[2026-10-09 10:00:00])
    end

    test "waits when the last slot already ran" do
      refute Job.due?(~N[2026-10-08 18:00:05], ~N[2026-10-09 10:00:00])
      refute Job.due?(~N[2026-10-09 18:00:00], ~N[2026-10-09 18:30:00])
    end
  end

  describe "next_run/1" do
    test "is today at 18:00 before then, and tomorrow from then on" do
      assert Job.next_run(~N[2026-10-09 17:59:59]) == ~N[2026-10-09 18:00:00]
      assert Job.next_run(~N[2026-10-09 18:00:00]) == ~N[2026-10-10 18:00:00]
      assert Job.next_run(~N[2026-10-24 23:00:00]) == ~N[2026-10-25 18:00:00]
    end
  end
end
