defmodule Zipfelfolio.MarketData do
  @moduledoc """
  Fetches prices, exchange rates and the compositions of the funds and stores them. The daily job
  calls `run_daily/1`; pages refresh stale quotes in the background and hear about every update
  over PubSub. Screens never call a source themselves.
  """

  require Logger

  alias Zipfelfolio.{ExchangeRates, Repo, Securities}
  alias Zipfelfolio.MarketData.JobRun

  @topic "market_data"
  @first_rate_date ~D[1999-01-04]
  @stale_after_seconds 15 * 60

  def subscribe, do: Phoenix.PubSub.subscribe(Zipfelfolio.PubSub, @topic)

  @doc "Tells every page that prices or holdings changed, so that it loads them again."
  def broadcast, do: Phoenix.PubSub.broadcast(Zipfelfolio.PubSub, @topic, :market_data_updated)

  @doc """
  Fetches the exchange rates, the prices of every Yahoo security and, with an API key, the
  composition of every security with an ISIN, then records the run. A step that fails, even with
  an exception or an exit, is recorded or logged and does not stop the others.
  """
  def run_daily(now \\ DateTime.utc_now()) do
    rates_error = update_rates()

    for security <- Securities.list_yahoo_securities() do
      update_prices_safely(security, Securities.last_price_date(security), now)
    end

    if compositions_available?() do
      Enum.each(Securities.list_securities_with_isin(), &update_composition(&1, now))
    end

    record_run(now, rates_error)
    broadcast()
  end

  @doc "Whether compositions can be fetched, i.e. their source has its API key."
  def compositions_available?, do: composition_source().available?()

  def last_run, do: Repo.get_by(JobRun, name: "daily")

  defp record_run(now, error) do
    Repo.insert!(%JobRun{name: "daily", ran_at: now, error: error},
      on_conflict: {:replace, [:ran_at, :error]},
      conflict_target: :name
    )
  end

  # From the last stored day on, which may still change; the ECB refuses a start in the future.
  defp update_rates do
    case rate_source().rates(ExchangeRates.last_date() || @first_rate_date) do
      {:ok, rates} ->
        ExchangeRates.store(rates)
        nil

      {:error, reason} ->
        source_error("Die EZB", reason)
    end
  rescue
    exception -> log_and_describe(exception, __STACKTRACE__, "Die Wechselkurse")
  catch
    :exit, _reason -> exited("the exchange rates", "Die Wechselkurse")
  end

  @doc """
  Fetches, in the background, the prices of a security from `from` on, the whole history when
  `from` is nil, e.g. after a new symbol.
  """
  def fetch_in_background(security, from \\ nil),
    do: in_background(fn -> update_prices_safely(security, from, DateTime.utc_now()) end)

  @doc """
  Refreshes, in the background, every Yahoo quote not checked for 15 minutes, failed ones too.
  Each check is claimed first, so pages opened together fetch a quote once.
  """
  def refresh_stale_quotes(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@stale_after_seconds)

    case Securities.claim_unchecked_yahoo_securities(cutoff, now) do
      [] -> :ok
      stale -> in_background(fn -> Enum.each(stale, &refresh_quote(&1, now)) end)
    end
  end

  defp in_background(fun) do
    {:ok, _pid} =
      Task.Supervisor.start_child(Zipfelfolio.TaskSupervisor, fn ->
        fun.()
        broadcast()
      end)

    :ok
  end

  defp update_prices_safely(security, from, now) do
    update_prices(security, from, now)
  rescue
    exception ->
      message = log_and_describe(exception, __STACKTRACE__, "Die Kurse")
      record_failure(security, message, now)
  catch
    :exit, _reason ->
      record_failure(security, exited("the prices of #{security.symbol}", "Die Kurse"), now)
  end

  # Recording fails too when the database is the problem; the log has it then.
  defp record_failure(security, message, now) do
    Securities.with_same_yahoo_symbol(security, &Securities.record_fetch_error(&1, message, now))
  rescue
    _exception -> :error
  end

  defp update_prices(security, from, now) do
    with {:ok, chart} <- fetch(security, not_after(from, DateTime.to_date(now)), now) do
      Securities.with_same_yahoo_symbol(security, fn current ->
        Securities.store_yahoo_prices(current, chart.closes)
        Securities.record_quote(current, chart.quote, now)
      end)
    end
  end

  # A failed fetch keeps the stored composition; one DivvyDiary does not know is no error.
  defp update_composition(security, now) do
    case composition_source().composition(security.isin) do
      {:ok, composition} ->
        Securities.replace_composition(security, composition, now)

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        Logger.warning("No composition for #{security.isin}: #{inspect(reason)}")
    end
  rescue
    exception -> Logger.error(Exception.format(:error, exception, __STACKTRACE__))
  catch
    # The reason of an exit from `:httpc` holds the request, the API key with it.
    :exit, _reason -> Logger.error("No composition for #{security.isin}: the request exited")
  end

  # Yahoo refuses a start after the end.
  defp not_after(nil, _today), do: nil
  defp not_after(date, today), do: Enum.min([date, today], Date)

  # Only the latest quote: today's closing price comes with the daily run.
  defp refresh_quote(security, now) do
    with {:ok, chart} <- fetch(security, DateTime.to_date(now), now) do
      Securities.with_same_yahoo_symbol(security, &Securities.record_quote(&1, chart.quote, now))
    end
  end

  # A changed symbol makes the result void, the error included.
  defp fetch(security, from, now) do
    with {:ok, chart} <- price_feed().chart(security.symbol, from, now),
         :ok <- check_currency(chart, security) do
      {:ok, chart}
    else
      {:error, reason} ->
        message = fetch_error(reason, security)

        Securities.with_same_yahoo_symbol(
          security,
          &Securities.record_fetch_error(&1, message, now)
        )

        {:error, reason}
    end
  end

  defp log_and_describe(exception, stacktrace, what) do
    Logger.error(Exception.format(:error, exception, stacktrace))
    "#{what} ließen sich nicht speichern: #{Exception.message(exception)}"
  end

  # The reason of an exit, e.g. from `:httpc`, may hold the request with its credentials.
  defp exited(logged, what) do
    Logger.error("The request for #{logged} exited")
    "#{what} ließen sich nicht abrufen."
  end

  defp check_currency(%{currency: currency}, %{currency: expected})
       when expected in [nil, currency], do: :ok

  defp check_currency(%{currency: currency}, _security),
    do: {:error, {:currency_mismatch, currency}}

  defp fetch_error(:not_found, security), do: "Yahoo kennt das Symbol #{security.symbol} nicht."

  defp fetch_error({:currency_mismatch, currency}, security),
    do:
      "Yahoo notiert #{security.symbol} in #{currency}, das Wertpapier ist in #{security.currency}."

  defp fetch_error(reason, _security), do: source_error("Yahoo", reason)

  defp source_error(source, :unreachable), do: "#{source} ist nicht erreichbar."
  defp source_error(source, {:http_status, status}), do: "#{source} antwortet mit HTTP #{status}."
  defp source_error(source, :invalid_response), do: "#{source} liefert eine unerwartete Antwort."

  defp price_feed, do: config(:price_feed)
  defp rate_source, do: config(:rate_source)
  defp composition_source, do: config(:composition_source)
  defp config(key), do: Application.fetch_env!(:zipfelfolio, __MODULE__)[key]
end
