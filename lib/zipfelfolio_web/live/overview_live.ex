defmodule ZipfelfolioWeb.OverviewLive do
  use ZipfelfolioWeb, :live_view

  import ZipfelfolioWeb.DividendComponents

  alias Zipfelfolio.{LocalTime, Portfolios}
  alias ZipfelfolioWeb.{Benchmark, Format, Sidebar}

  on_mount Benchmark

  # URL parameter, period and button label; the first is the default.
  @periods [
    {"6m", :six_months, "6 M"},
    {"ytd", :year_to_date, "YTD"},
    {"1y", :one_year, "1 J"},
    {"max", :max, "Max"}
  ]
  @period_params Map.new(@periods, fn {param, period, _label} -> {param, period} end)

  @upcoming_shown 4

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :periods, @periods)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:overview}
    >
      <.header class="flex-wrap">
        Übersicht
        <:actions :if={!@empty}>
          <Benchmark.toggle_button :if={@overview.benchmark} shown={@benchmark_shown} />
          <nav id="period" class="btn-group btn-group-sm app-periods" aria-label="Zeitraum">
            <.link
              :for={{param, period, label} <- @periods}
              patch={~p"/?#{[period: param]}"}
              class={["btn btn-outline-secondary", @period == period && "active"]}
              aria-current={@period == period && "true"}
            >
              {label}
            </.link>
          </nav>
        </:actions>
      </.header>

      <.card :if={@empty}>
        <p class="mb-0">
          Noch keine Depots. Sie kommen mit dem <.link navigate={~p"/settings/import"}>Import aus Portfolio Performance</.link>.
        </p>
      </.card>

      <%!-- The net worth card spans the phone's width, so that seven digits fit. --%>
      <div
        :if={!@empty}
        class={["row g-3 mb-4 app-stats", @overview.benchmark && "app-stats-benchmark"]}
      >
        <div class="col-12 col-sm-6 col-lg-3">
          <.stat id="net-worth" label="Vermögen" value={Format.euros(@overview.net_worth)}>
            <:note class={tone(change_note(@change, @change_percent))}>
              {change_note(@change, @change_percent)}
            </:note>
          </.stat>
        </div>
        <div class="col-6 col-lg-3">
          <.stat
            id="ttwror"
            label={"TTWROR · #{period_label(@period)}"}
            value={percent_text(@overview.ttwror, 2)}
            value_class={tone(percent_text(@overview.ttwror, 2))}
          >
            <:note class="text-body-secondary">
              <Benchmark.note
                :if={@benchmark_shown and @overview.benchmark}
                benchmark={@overview.benchmark}
              />
              <span :if={!(@benchmark_shown and @overview.benchmark)}>zeitgewichtet</span>
            </:note>
          </.stat>
        </div>
        <div class="col-6 col-lg-3">
          <.stat
            id="irr"
            label={"IZF · #{period_label(@period)}"}
            value={percent_text(@overview.irr, 2)}
            value_class={tone(percent_text(@overview.irr, 2))}
          >
            <:note class="text-body-secondary">{"p.\u00A0a."} · geldgewichtet</:note>
          </.stat>
        </div>
        <div class="col-12 col-sm-6 col-lg-3">
          <.stat
            id="dividends"
            label={"Dividenden #{@today.year}"}
            value={Format.euros(@overview.dividends)}
          >
            <:note class="text-body-secondary">
              erwartet {Format.euros(@overview.dividends + @upcoming_dividends.rest_of_year)} im Jahr · brutto
            </:note>
          </.stat>
        </div>
      </div>

      <div :if={!@empty} class="row g-4 mb-4">
        <div class={if @upcoming_dividends.upcoming != [], do: "col-lg-8", else: "col-12"}>
          <section class="card h-100" aria-labelledby="history-title">
            <div class="card-header d-flex flex-wrap align-items-center justify-content-between gap-2">
              <h2 class="app-card-title mb-0" id="history-title">Wertentwicklung</h2>
              <span class="small text-body-secondary d-flex flex-wrap column-gap-3 row-gap-1 app-legend">
                <span class="text-nowrap"><span class="app-swatch app-swatch-primary"></span> Vermögen</span>
                <span class="text-nowrap">
                  <span class="app-swatch app-swatch-secondary"></span> Investiert
                </span>
                <Benchmark.legend
                  :if={@benchmark_shown and @overview.benchmark}
                  security={@overview.benchmark.security}
                />
              </span>
            </div>
            <div class="card-body">
              <div
                role="img"
                aria-label={chart_label(@period, @benchmark_shown && @overview.benchmark)}
              >
                <div
                  id="net-worth-chart"
                  class="app-chart"
                  phx-hook="NetWorthChart"
                  phx-update="ignore"
                >
                  <canvas></canvas>
                </div>
              </div>
            </div>
          </section>
        </div>
        <div :if={@upcoming_dividends.upcoming != []} class="col-lg-4">
          <.upcoming_dividends dividends={@upcoming_dividends} />
        </div>
      </div>

      <section
        :if={!@empty and @overview.portfolios != []}
        class="card mb-4"
        aria-labelledby="portfolios-title"
      >
        <div class="card-header">
          <h2 class="app-card-title mb-0" id="portfolios-title">Depots</h2>
        </div>
        <div class="list-group list-group-flush">
          <.link
            :for={row <- @overview.portfolios}
            id={"portfolio-#{row.portfolio.id}"}
            navigate={Sidebar.portfolio_path(row.portfolio)}
            class="list-group-item list-group-item-action d-flex align-items-center gap-3"
          >
            <span class="app-avatar rounded-circle bg-primary-subtle text-primary-emphasis d-flex align-items-center justify-content-center">
              <.icon name="layers" />
            </span>
            <span class="me-auto overflow-hidden">
              <span class="d-block fw-semibold">{row.portfolio.name}</span>
              <span class="d-block small text-body-secondary">{portfolio_note(row)}</span>
            </span>
            <span class="text-end text-nowrap">
              <span class="d-block fw-bold tabular-nums">{Format.euros(row.value, 2)}</span>
              <span
                :if={row.securities > 0}
                class={["small tabular-nums", tone(percent_text(row.ttwror, 1))]}
              >
                {percent_text(row.ttwror, 1)} YTD
              </span>
              <span :if={row.securities == 0} class="small text-body-secondary">nur Cash</span>
            </span>
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :dividends, :map, required: true, doc: "see `Portfolios.upcoming_dividends/2`"

  defp upcoming_dividends(assigns) do
    assigns =
      assign(assigns,
        shown: Enum.take(assigns.dividends.upcoming, @upcoming_shown),
        three_months: assigns.dividends.next_three_months
      )

    ~H"""
    <section id="upcoming-dividends" class="card h-100" aria-labelledby="upcoming-dividends-title">
      <div class="card-header d-flex align-items-center justify-content-between gap-2">
        <h2 class="app-card-title mb-0" id="upcoming-dividends-title">
          Nächste Dividenden <span class="fw-normal text-body-secondary">· brutto</span>
        </h2>
        <.link
          navigate={~p"/dividends?amount=gross"}
          class="small text-nowrap text-decoration-none app-quiet-link"
        >
          Kalender<.icon name="chevron" class="app-icon-sm" />
        </.link>
      </div>
      <ul class="list-group list-group-flush">
        <li
          :for={dividend <- @shown}
          class="list-group-item app-next-dividend"
          data-kind={dividend.kind}
        >
          <time class="app-next-dividend-date" datetime={Date.to_iso8601(dividend.pay_date)}>
            <span class="app-next-dividend-day">{dividend.pay_date.day}</span>
            <span class="small text-body-secondary">{Format.month_abbr(dividend.pay_date)}</span>
          </time>
          <.security_link security={dividend.security} class="app-next-dividend-name" />
          <.kind_tag kind={dividend.kind} class="app-next-dividend-tag" />
          <span class="app-next-dividend-amount fw-semibold tabular-nums text-nowrap">
            {expected(dividend, :gross, 2)}
          </span>
        </li>
      </ul>
      <div class="card-footer small text-body-secondary mt-auto">
        Nächste 3 Monate:
        <strong class="tabular-nums text-body">{expected_total(@three_months, :gross, 0)}</strong>
      </div>
    </section>
    """
  end

  defp change_note(change, nil), do: "#{Format.signed_euros(change)} heute"

  defp change_note(change, percent),
    do: "#{Format.signed_euros(change)} heute (#{Format.signed_percent(percent)})"

  defp period_text(:six_months), do: "der letzten sechs Monate"
  defp period_text(:year_to_date), do: "seit Jahresbeginn"
  defp period_text(:one_year), do: "des letzten Jahres"
  defp period_text(:max), do: "seit der ersten Buchung"

  defp chart_label(period, %{security: security}),
    do:
      "Vermögen, investiertes Kapital und Schattendepot in #{security.name} #{period_text(period)}"

  defp chart_label(period, _hidden),
    do: "Vermögen und investiertes Kapital #{period_text(period)}"

  defp period_label(period),
    do: Enum.find_value(@periods, fn {_param, p, label} -> p == period && label end)

  # A rate of return as a fraction, in percent; nil where there is none.
  defp percent_text(nil, _places), do: "–"
  defp percent_text(rate, places), do: rate |> in_percent() |> Format.signed_percent(places)

  defp in_percent(rate), do: Decimal.from_float(rate * 100)

  # Each part stays on one line.
  defp portfolio_note(%{securities: count, account: account, balance: balance}) do
    Enum.join(
      [securities(count) | List.wrap(account && "Konto\u00A0#{Format.euros(balance, 2)}")],
      " · "
    )
  end

  defp securities(0), do: "keine\u00A0Wertpapiere"
  defp securities(1), do: "1\u00A0Wertpapier"
  defp securities(count), do: "#{count}\u00A0Wertpapiere"

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    empty = Portfolios.list_portfolios(scope) == [] and Portfolios.list_accounts(scope) == []

    {:ok, assign(socket, page_title: "Übersicht", empty: empty)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(period: period(params["period"]))
    |> load_overview()
    |> load_upcoming_once()
    |> then(&{:noreply, &1})
  end

  defp period(param), do: Map.get(@period_params, param, :six_months)

  @impl true
  def handle_info(:market_data_updated, socket),
    do: {:noreply, socket |> load_overview() |> load_upcoming()}

  defp load_overview(%{assigns: %{empty: true}} = socket), do: socket

  defp load_overview(socket) do
    today = LocalTime.today()
    scope = socket.assigns.current_scope
    overview = Portfolios.overview(scope, socket.assigns.period, today)
    change = overview.net_worth - overview.net_worth_yesterday

    socket
    |> assign(
      today: today,
      overview: overview,
      change: change,
      change_percent: change_percent(change, overview.net_worth_yesterday)
    )
    |> push_chart(overview.chart)
  end

  defp load_upcoming_once(%{assigns: %{upcoming_dividends: _}} = socket), do: socket
  defp load_upcoming_once(socket), do: load_upcoming(socket)

  defp load_upcoming(%{assigns: %{empty: true}} = socket), do: socket

  defp load_upcoming(%{assigns: assigns} = socket) do
    upcoming = Portfolios.upcoming_dividends(assigns.current_scope, assigns.today)
    assign(socket, upcoming_dividends: upcoming)
  end

  # Relative to yesterday's net worth, when there was any.
  defp change_percent(_change, before) when before <= 0, do: nil
  defp change_percent(change, before), do: Format.percent_of(change, before)

  # The hook draws the chart once connected; amounts in cents.
  defp push_chart(socket, chart) do
    if connected?(socket) do
      push_event(socket, "net-worth-chart", %{
        dates: Enum.map(chart, & &1.date),
        net_worth: Enum.map(chart, & &1.net_worth),
        invested_capital: Enum.map(chart, & &1.invested_capital),
        benchmark: socket.assigns.overview.benchmark && Enum.map(chart, & &1.benchmark),
        benchmark_name: benchmark_name(socket.assigns.overview.benchmark),
        benchmark_shown: socket.assigns.benchmark_shown
      })
    else
      socket
    end
  end

  defp benchmark_name(nil), do: nil
  defp benchmark_name(benchmark), do: Benchmark.short_name(benchmark.security.name)
end
