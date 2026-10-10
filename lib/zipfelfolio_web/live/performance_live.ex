defmodule ZipfelfolioWeb.PerformanceLive do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{LocalTime, Portfolios}
  alias ZipfelfolioWeb.{Benchmark, Format}

  on_mount Benchmark

  # URL parameter, period, button label and its long form; the default is the year to date.
  @periods [
    {"1m", :one_month, "1\u202FM", "1 Monat"},
    {"6m", :six_months, "6\u202FM", "6 Monate"},
    {"ytd", :year_to_date, "YTD", "Seit Jahresbeginn"},
    {"1y", :one_year, "1\u202FJ", "1 Jahr"},
    {"3y", :three_years, "3\u202FJ", "3 Jahre"},
    {"max", :max, "Max", "Seit der ersten Buchung"}
  ]
  @period_params Map.new(@periods, fn {param, period, _label, _long} -> {param, period} end)
  @default_period :year_to_date

  @impl true
  def render(assigns) do
    assigns = assign(assigns, periods: @periods, per_year: "p.\u00A0a.")

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:performance}
    >
      <%!-- On a phone the switcher stays beside the title and the periods take a row of their own. --%>
      <header class="app-head">
        <h1 class="h2 mb-0 app-head-title">Performance</h1>
        <p :if={!@empty} class="small text-body-secondary mb-0 app-head-subtitle">
          <span class="d-block d-sm-inline text-nowrap">{days(@performance.interval)}</span>
          <span class="d-none d-sm-inline">·</span>
          <span class="d-block d-sm-inline text-nowrap">
            {portfolio_name(@performance.portfolio)}
          </span>
        </p>
        <div :if={!@empty} class="app-head-switcher">
          <Layouts.portfolio_switcher
            portfolios={@performance.portfolios}
            portfolio={@performance.portfolio}
            path={&performance_path(period_param(@period), &1)}
          />
        </div>
        <nav
          :if={!@empty}
          id="period"
          class="btn-group btn-group-sm app-periods app-head-periods"
          aria-label="Zeitraum"
        >
          <.link
            :for={{param, period, label, long} <- @periods}
            patch={performance_path(param, @performance.portfolio)}
            class={["btn btn-outline-secondary", @period == period && "active"]}
            aria-current={@period == period && "true"}
            title={long}
          >
            {label}
          </.link>
        </nav>
        <div :if={!@empty and @performance.benchmark} class="app-head-benchmark">
          <Benchmark.toggle_button shown={@benchmark_shown} />
        </div>
      </header>

      <.card :if={@empty}>
        <p class="mb-0">
          Noch keine Depots. Sie kommen mit dem <.link navigate={~p"/settings/import"}>Import aus Portfolio Performance</.link>.
        </p>
      </.card>

      <div
        :if={!@empty}
        class={[
          "row row-cols-2 row-cols-lg-4 g-3 mb-3 app-stats",
          @performance.benchmark && "app-stats-benchmark"
        ]}
      >
        <div class="col">
          <.stat
            id="ttwror"
            label="TTWROR"
            value={percent_text(@performance.ttwror, 2)}
            value_class={tone(percent_text(@performance.ttwror, 2))}
          >
            <:note class="text-body-secondary">
              <Benchmark.note
                :if={@benchmark_shown and @performance.benchmark}
                benchmark={@performance.benchmark}
              />
              <span :if={!(@benchmark_shown and @performance.benchmark)}>
                {percent_text(@performance.ttwror_per_year, 2)} {@per_year}
              </span>
            </:note>
          </.stat>
        </div>
        <div class="col">
          <.stat
            id="irr"
            label="IZF"
            value={percent_text(@performance.irr, 2)}
            value_class={tone(percent_text(@performance.irr, 2))}
          >
            <:note class="text-body-secondary">
              {@per_year} · geldgewichtet
            </:note>
          </.stat>
        </div>
        <div class="col">
          <.stat
            id="drawdown"
            label="Max. Drawdown"
            value={percent_text(-@performance.drawdown.max, 2)}
            value_class={tone(percent_text(-@performance.drawdown.max, 2))}
          >
            <:note class="text-body-secondary">
              <.drawdown_days {@performance.drawdown} year={@performance.interval.last.year} />
            </:note>
          </.stat>
        </div>
        <div class="col">
          <.stat
            id="volatility"
            label="Volatilität"
            value={@performance.volatility |> in_percent() |> Format.percent(2)}
          >
            <:note class="text-body-secondary">
              nicht annualisiert
            </:note>
          </.stat>
        </div>
      </div>

      <div :if={!@empty} class="row g-3">
        <div class="col-lg-6 app-col-breakdown">
          <.breakdown breakdown={@performance.breakdown} interval={@performance.interval} />
        </div>
        <div class="col-12 app-col-heatmap">
          <.monthly_returns years={@performance.monthly_returns} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :breakdown, :map, required: true
  attr :interval, Date.Range, required: true

  # PP's performance calculation, from the initial to the final value; currency gains only when
  # there are any.
  defp breakdown(assigns) do
    ~H"""
    <section id="breakdown" class="card h-100 app-breakdown" aria-labelledby="breakdown-title">
      <div class="card-header">
        <h2 class="stat-label mb-0" id="breakdown-title">Berechnung</h2>
      </div>
      <ul class="list-group list-group-flush tabular-nums">
        <.item class="fw-semibold" value={@breakdown.initial_value} total>
          Anfangswert <.day date={@interval.first} />
        </.item>
        <.item value={@breakdown.capital_gains}>Unrealisierte Kursgewinne</.item>
        <.item value={@breakdown.realized_capital_gains}>Realisierte Kursgewinne</.item>
        <.item value={@breakdown.earnings}>Erträge</.item>
        <.item value={-@breakdown.fees}>Gebühren</.item>
        <.item value={-@breakdown.taxes}>Steuern</.item>
        <.item :if={@breakdown.currency_gains != 0} value={@breakdown.currency_gains}>
          Währungsgewinne
        </.item>
        <.item value={@breakdown.transfers}>Einlagen und Entnahmen</.item>
        <.item class="fw-bold app-breakdown-total" value={@breakdown.final_value} total>
          Endwert <.day date={@interval.last} />
        </.item>
      </ul>
    </section>
    """
  end

  # Month abbreviation and name.
  @months Enum.map(1..12, &{Format.month_abbr(&1), Format.month_name(&1)})

  attr :years, :list, required: true

  # The TTWROR of every month since the first transaction as a heatmap, the newest year on top;
  # on a phone each year folds into two rows of six months.
  defp monthly_returns(assigns) do
    assigns = assign(assigns, months: @months)

    ~H"""
    <section
      id="monthly-returns"
      class="card h-100 app-heatmap"
      aria-labelledby="monthly-returns-title"
    >
      <div class="card-header">
        <h2 class="stat-label mb-0" id="monthly-returns-title">Monatsrenditen</h2>
      </div>
      <div class="card-body d-flex flex-column">
        <table class="app-heatmap-table tabular-nums">
          <thead>
            <tr>
              <th scope="col"><span class="visually-hidden">Jahr</span></th>
              <th :for={{short, long} <- @months} scope="col">
                <abbr title={long}>{short}</abbr>
              </th>
              <th scope="col" class="app-heatmap-total">
                <abbr title="Jahr, aus den Monaten verkettet">Jahr</abbr>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- Enum.reverse(@years)} id={"monthly-returns-#{row.year}"}>
              <th scope="row">{row.year}</th>
              <.heat
                :for={{rate, {short, long}} <- Enum.zip(row.months, @months)}
                rate={rate}
                places={1}
                scale={0.035}
                label={short}
                title={"#{long} #{row.year}"}
              />
              <.heat
                rate={row.total}
                places={2}
                scale={0.1}
                label="Jahr"
                title={"Jahr #{row.year}"}
                class="app-heatmap-total"
              />
            </tr>
          </tbody>
        </table>
        <p class="small text-body-secondary mb-0 mt-auto pt-3 app-heatmap-note">
          TTWROR je Monat in %, verkettet zum Jahr
        </p>
      </div>
    </section>
    """
  end

  attr :rate, :float, required: true, doc: "nil for a month without returns"
  attr :places, :integer, required: true
  attr :scale, :float, required: true, doc: "the rate shown in the strongest colour"
  attr :label, :string, required: true, doc: "shown with the value on a phone"
  attr :title, :string, required: true
  attr :class, :string, default: nil

  defp heat(%{rate: nil} = assigns) do
    ~H"""
    <td class={@class} title={"#{@title}: keine Daten"}>
      <span class="app-heat app-heat-none" data-label={@label}>
        <span class="visually-hidden">keine Daten</span>
      </span>
    </td>
    """
  end

  defp heat(assigns) do
    rounded = assigns.rate |> in_percent() |> Decimal.round(assigns.places)

    assigns =
      assign(assigns,
        text: heat_text(rounded, assigns.places),
        tone: tone_class(rounded),
        strength: strength(assigns.rate, assigns.scale)
      )

    ~H"""
    <td class={@class} title={"#{@title}: #{@text}\u00A0%"}>
      <span class={["app-heat", @tone]} style={"--heat: #{@strength}"} data-label={@label}>
        {@text}
      </span>
    </td>
    """
  end

  # How strong a cell's colour is, from 0 to 1 at `scale`; the root spreads the small rates, which
  # are the most.
  defp strength(rate, scale), do: Float.round(:math.sqrt(min(abs(rate) / scale, 1.0)), 2)

  # Zero as ±0,0, so that it lines up with the signed figures.
  defp heat_text(rounded, places) do
    if Decimal.eq?(rounded, 0),
      do: "±" <> Format.signed_number(rounded, places),
      else: Format.signed_number(rounded, places)
  end

  defp tone_class(rounded) do
    cond do
      Decimal.positive?(rounded) -> "app-heat-up"
      Decimal.negative?(rounded) -> "app-heat-down"
      true -> nil
    end
  end

  attr :value, :integer, required: true
  attr :total, :boolean, default: false, doc: "a value, not a change, so without a sign"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp item(assigns) do
    ~H"""
    <li class={["list-group-item d-flex align-items-baseline gap-3", @class]}>
      <span class="me-auto">{render_slot(@inner_block)}</span>
      <span class="text-nowrap app-breakdown-value">
        {if @total, do: Format.euros(@value, 2), else: Format.signed_euros(@value, 2)}
      </span>
    </li>
    """
  end

  attr :date, Date, required: true

  defp day(assigns) do
    ~H"""
    <span class="d-block small fw-normal text-body-secondary app-breakdown-date">
      {Format.date(@date)}
    </span>
    """
  end

  # The days after the reference day.
  defp days(interval), do: Format.days(Date.add(interval.first, 1), interval.last)

  defp portfolio_name(nil), do: "alle Depots und Konten"
  defp portfolio_name(%{reference_account_id: nil} = portfolio), do: portfolio.name
  defp portfolio_name(portfolio), do: "#{portfolio.name} mit Referenzkonto"

  attr :max, :float, required: true
  attr :from, Date, required: true
  attr :to, Date, required: true
  attr :year, :integer, required: true, doc: "left out of the days when they are in it"

  defp drawdown_days(%{max: max} = assigns) when max == 0, do: ~H"kein Rückgang"

  defp drawdown_days(assigns) do
    ~H"""
    <span class="text-nowrap" title={Format.date_span(@from, @to)}>
      {Format.date_span(@from, @to, @from.year != @year or @to.year != @year)}
    </span>
    · <span class="text-nowrap">{days_count(Date.diff(@to, @from))}</span>
    """
  end

  defp days_count(1), do: "1 Tag"
  defp days_count(days), do: "#{days} Tage"

  # A rate as a fraction, in percent with its sign; nil where there is none.
  defp percent_text(nil, _places), do: "–"
  defp percent_text(rate, places), do: rate |> in_percent() |> Format.signed_percent(places)

  defp in_percent(rate), do: Decimal.from_float(rate * 100)

  defp performance_path(period_param, portfolio) do
    query =
      Enum.reject(
        [period: period_param, portfolio: portfolio_id(portfolio)],
        &is_nil(elem(&1, 1))
      )

    ~p"/performance?#{query}"
  end

  defp portfolio_id(%{id: id}), do: id
  defp portfolio_id(id), do: id

  defp period_param(period),
    do: Enum.find_value(@periods, fn {param, p, _label, _long} -> p == period && param end)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    empty = Portfolios.list_portfolios(scope) == [] and Portfolios.list_accounts(scope) == []

    {:ok, assign(socket, page_title: "Performance", empty: empty)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(
      period: Map.get(@period_params, params["period"], @default_period),
      portfolio_id: parse_id(params["portfolio"])
    )
    |> load_performance()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_performance(socket)}

  defp load_performance(%{assigns: %{empty: true}} = socket), do: socket

  defp load_performance(socket) do
    %{current_scope: scope, period: period, portfolio_id: portfolio_id} = socket.assigns

    assign(
      socket,
      :performance,
      Portfolios.performance(scope, period, portfolio_id, LocalTime.today())
    )
  end
end
