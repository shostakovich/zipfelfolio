defmodule Zipfelfolio.Performance do
  @moduledoc """
  The true time-weighted rate of return (TTWROR) and the internal rate of return (IRR) of a
  user's portfolios and accounts, or of a `Filter` of them, over an interval such as
  `Zipfelfolio.Period.interval/3` gives. Pure, and computed as PP 0.88 does, so that its figures
  match PP's; PP's `ClientIndex`, `ClientIRRYield` and `IRR` were read, not copied:

  - The interval's first day is the reference day: the returns start from its closing value, and
    what happens on it counts no further.
  - Money in and out are deposits and removals, inbound and outbound deliveries, and what crosses
    the filter's edge as `Filter` converts it, each in euros at the ECB rate of its day.
  - TTWROR: each day returns (value + money out) / (previous day's value + money in) − 1, so
    money comes in at the start of the day and goes out at its end; a day with neither value
    before it nor money coming in returns 0. The days are chained.
  - IRR: XIRR of the reference day's value paid in, the money in and out after it including both
    sides of transfers inside, and the last day's value paid out; values of nothing are left out,
    and without any cash flow the IRR is 0. `IRR` solves it as PP does.
  """

  alias Zipfelfolio.Performance.IRR
  alias Zipfelfolio.Valuation
  alias Zipfelfolio.Valuation.{Filter, Market}

  @enforce_keys [:days, :cash_flows]
  defstruct [:days, :cash_flows]

  @doc """
  Every day of `interval` as `%{date, value, invested_capital, inbound, outbound}` in euro cents,
  and the IRR's cash flows after the reference day as `{date, euros}` with money in negative, in
  order of time.
  """
  def index(
        transactions,
        accounts,
        %Market{} = market,
        %Filter{} = filter,
        %Date.Range{} = interval
      ) do
    flows = flows(transactions, market, filter, interval)
    per_day = Enum.group_by(flows, &elem(&1, 0), &Tuple.delete_at(&1, 0))

    days =
      transactions
      |> Valuation.history(accounts, market, Enum.to_list(interval), filter)
      |> Enum.map(fn point ->
        day_flows = Map.get(per_day, point.date, [])

        %{
          date: point.date,
          value: point.net_worth,
          invested_capital: point.invested_capital,
          inbound: sum(day_flows, :inbound),
          outbound: sum(day_flows, :outbound)
        }
      end)

    cash_flows =
      for {date, kind, cents} <- flows,
          Date.after?(date, interval.first),
          do: {date, if(kind in [:inbound, :transfer_in], do: -cents, else: cents) / 100}

    %__MODULE__{days: days, cash_flows: cash_flows}
  end

  # `{date, kind, cents}` per side of each transaction in the interval, in order of time.
  defp flows(transactions, market, filter, interval) do
    for t <- Enum.sort_by(transactions, & &1.date_time, NaiveDateTime),
        date = NaiveDateTime.to_date(t.date_time),
        date in interval,
        {kind, amount, currency} <- Filter.flows(filter, t),
        do: {date, kind, Market.to_euros(market, amount, currency, date)}
  end

  defp sum(day_flows, kind),
    do: for({^kind, cents} <- day_flows, reduce: 0, do: (sum -> sum + cents))

  @doc "The TTWROR as a fraction, 0.1 for 10 %."
  def ttwror(%__MODULE__{days: [reference_day | days]}) do
    days
    |> Enum.reduce({0.0, reference_day.value}, fn day, {accumulated, previous} ->
      {(accumulated + 1) * (daily_return(previous, day) + 1) - 1, day.value}
    end)
    |> elem(0)
  end

  defp daily_return(previous, %{inbound: inbound}) when previous + inbound == 0, do: 0.0

  defp daily_return(previous, day),
    do: (day.value + day.outbound) / (previous + day.inbound) - 1

  @doc "The IRR per year as a fraction, 0.1 for 10 %; nil where PP gets no number."
  def irr(%__MODULE__{days: [reference_day | _] = days, cash_flows: cash_flows}) do
    last_day = List.last(days)

    cash_flows =
      value_flow(reference_day.date, -reference_day.value) ++
        cash_flows ++ value_flow(last_day.date, last_day.value)

    if cash_flows == [], do: 0.0, else: IRR.calculate(cash_flows)
  end

  defp value_flow(_date, 0), do: []
  defp value_flow(date, cents), do: [{date, cents / 100}]
end
