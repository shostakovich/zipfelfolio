defmodule ZipfelfolioWeb.SecurityLive do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{LocalTime, Portfolios, Securities}
  alias ZipfelfolioWeb.{Format, Sidebar}

  # URL parameter, period and button label; the first is the default.
  @periods [
    {"1y", :one_year, "1 J"},
    {"5y", :five_years, "5 J"},
    {"max", :max, "Max"}
  ]
  @period_params Map.new(@periods, fn {param, period, _label} -> {param, period} end)

  # The sidebar marks „Bestand“, which the page belongs to, as in the click dummy.
  @current {:holdings, nil, nil}

  @impl true
  def render(%{security: nil} = assigns) do
    assigns = assign(assigns, :current, @current)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar} current={@current}>
      <.header>Wertpapier nicht gefunden</.header>
      <.card>
        <p class="mb-0">
          Unter dieser Adresse gibt es kein Wertpapier. Zurück zum <.link navigate={~p"/holdings"}>Bestand</.link>.
        </p>
      </.card>
    </Layouts.app>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, periods: @periods, current: @current)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar} current={@current}>
      <.link navigate={~p"/holdings"} class="d-inline-flex align-items-center gap-1 small mb-2">
        <.icon name="back" class="app-icon-sm" />Bestand
      </.link>
      <.header class="flex-wrap align-items-end">
        {@security.name}
        <:subtitle>{subtitle(@security)}</:subtitle>
        <:actions :if={@price}>
          <div id="price" class="text-end text-nowrap tabular-nums">
            <div class="fs-3 fw-bold">{Format.price(@price, currency(@security))}</div>
            <div
              :if={@price_yesterday}
              class={["small", tone(change_note(@price, @price_yesterday, currency(@security)))]}
            >
              {change_note(@price, @price_yesterday, currency(@security))}
            </div>
          </div>
        </:actions>
      </.header>

      <div class="row g-4 mb-4">
        <div class="col-lg-8">
          <section class="card h-100" aria-labelledby="chart-title">
            <div class="card-header d-flex flex-wrap align-items-center justify-content-between gap-2">
              <h2 class="fs-6 fw-semibold mb-0" id="chart-title">Kurs</h2>
              <nav id="period" class="btn-group btn-group-sm" aria-label="Zeitraum">
                <.link
                  :for={{param, period, label} <- @periods}
                  patch={~p"/securities/#{@security}?#{[period: param]}"}
                  class={["btn btn-outline-secondary", @period == period && "active"]}
                  aria-current={@period == period && "true"}
                >
                  {label}
                </.link>
              </nav>
            </div>
            <div class="card-body">
              <p :if={@chart.prices == []} id="price-chart-empty" class="text-body-secondary mb-0">
                Keine Kurse in diesem Zeitraum.
              </p>
              <div
                class={@chart.prices == [] && "d-none"}
                role="img"
                aria-label={"Kursverlauf #{period_text(@period)}"}
              >
                <div id="price-chart" class="app-chart" phx-hook="PriceChart" phx-update="ignore">
                  <canvas></canvas>
                </div>
              </div>
            </div>
            <div
              :if={@chart.prices != [] and @chart.trades != []}
              id="price-chart-legend"
              class="card-footer small text-body-secondary"
            >
              <span class="text-nowrap"><span class="app-dot"></span> Kauf</span>
              <span class="text-nowrap ms-2"><span class="app-dot app-dot-sale"></span> Verkauf</span>
              · zum Preis je Stück vor Gebühren und Steuern
            </div>
          </section>
        </div>
        <div class="col-lg-4">
          <.holding holdings={@holdings} total={@total} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :holdings, :list, required: true
  attr :total, :map, required: true

  # Over all portfolios, then per portfolio when it is in several.
  defp holding(assigns) do
    ~H"""
    <section id="holding" class="card h-100" aria-labelledby="holding-title">
      <div class="card-header">
        <h2 class="fs-6 fw-semibold mb-0" id="holding-title">Position</h2>
      </div>
      <p :if={@holdings == []} class="card-body text-body-secondary mb-0">Nicht im Bestand.</p>
      <dl
        :if={@holdings != []}
        class="row align-content-start flex-grow-0 mb-0 card-body tabular-nums"
      >
        <dt class="col-6 fw-normal text-body-secondary">Stück</dt>
        <dd class="col-6 text-end">{Format.shares(@total.shares)}</dd>
        <dt class="col-6 fw-normal text-body-secondary">Wert</dt>
        <dd class="col-6 text-end fw-semibold text-nowrap">{Format.euros(@total.value, 2)}</dd>
        <dt class="col-6 fw-normal text-body-secondary">Einstand</dt>
        <dd class="col-6 text-end text-nowrap">{Format.euros(@total.purchase_value, 2)}</dd>
        <dt class="col-6 fw-normal text-body-secondary">Gewinn</dt>
        <dd class={["col-6 text-end text-nowrap mb-0", tone(Format.signed_euros(@total.gain, 2))]}>
          {Format.signed_euros(@total.gain, 2)}
          <div :if={@total.purchase_value > 0} class="small">
            {@total.gain |> Format.percent_of(@total.purchase_value) |> Format.signed_percent(1)}
          </div>
        </dd>
      </dl>
      <div :if={length(@holdings) > 1} id="holding-portfolios" class="list-group list-group-flush">
        <.link
          :for={row <- @holdings}
          id={"holding-#{row.portfolio.id}"}
          navigate={Sidebar.portfolio_path(row.portfolio)}
          class="list-group-item list-group-item-action d-flex align-items-center gap-2"
        >
          <Layouts.chip portfolio={row.portfolio} />
          <span class="me-auto">
            <span class="d-block fw-semibold">{row.portfolio.name}</span>
            <span class="small text-body-secondary">{Format.shares(row.shares)} Stück</span>
          </span>
          <span class="text-end text-nowrap tabular-nums">
            <span class="d-block fw-semibold">{Format.euros(row.value, 2)}</span>
            <span class={["small", tone(Format.signed_euros(row.gain, 2))]}>
              {Format.signed_euros(row.gain, 2)}
            </span>
          </span>
        </.link>
      </div>
    </section>
    """
  end

  defp subtitle(security) do
    [security.isin, security.wkn && "WKN #{security.wkn}", security.currency]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp currency(security), do: Format.currency(security.currency)

  defp change_note(price, yesterday, currency) do
    change = price - yesterday

    percent =
      if yesterday > 0,
        do: " (#{change |> Format.percent_of(yesterday) |> Format.signed_percent()})"

    "#{Format.signed_price(change, currency)}#{percent} heute"
  end

  defp period_text(:one_year), do: "des letzten Jahres"
  defp period_text(:five_years), do: "der letzten fünf Jahre"
  defp period_text(:max), do: "seit dem ersten Kurs"

  @impl true
  def mount(%{"id" => id}, _session, socket), do: {:ok, assign(socket, :security_id, id(id))}

  # Ids beyond SQLite's integers would make the query fail.
  defp id(param) do
    case Integer.parse(param) do
      {id, ""} when id in 1..9_223_372_036_854_775_807 -> id
      _invalid -> nil
    end
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, socket |> assign(period: period(params["period"])) |> load()}

  defp period(param), do: Map.get(@period_params, param, :one_year)

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load(socket)}

  # The security again each time, with its latest quote.
  defp load(socket) do
    %{current_scope: scope, security_id: id, period: period} = socket.assigns

    case id && Securities.get_security(scope, id) do
      nil ->
        assign(socket, security: nil, page_title: "Nicht gefunden")

      security ->
        shown = Portfolios.security(scope, security, period, LocalTime.today())

        socket
        |> assign(security: security, page_title: security.name)
        |> assign(shown)
        |> push_chart(shown.chart)
    end
  end

  # The hook draws the chart once connected; prices and shares × 10⁸.
  defp push_chart(socket, chart) do
    if connected?(socket) do
      push_event(socket, "price-chart", %{
        currency: currency(socket.assigns.security),
        dates: Enum.map(chart.prices, & &1.date),
        prices: Enum.map(chart.prices, & &1.price),
        trades: chart.trades
      })
    else
      socket
    end
  end
end
