defmodule Zipfelfolio.LocalTime do
  @moduledoc "The host's local time (`TZ` in the container), without a time zone database."

  def now, do: NaiveDateTime.local_now()

  def today, do: NaiveDateTime.to_date(now())

  def from_utc(%DateTime{} = utc) do
    utc
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
    |> NaiveDateTime.from_erl!(utc.microsecond)
  end

  def to_utc(%NaiveDateTime{} = local) do
    [utc | _] = local |> NaiveDateTime.to_erl() |> :calendar.local_time_to_universal_time_dst()
    utc |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
  end
end
