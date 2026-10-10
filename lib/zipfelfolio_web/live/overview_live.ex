defmodule ZipfelfolioWeb.OverviewLive do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{LocalTime, MarketData, Period, Portfolios}
  alias ZipfelfolioWeb.Format

  # URL parameter, period and button label; the first is the default.
  @periods [
    {"6m", :six_months, "6 M"},
    {"ytd", :year_to_date, "YTD"},
    {"1y", :one_year, "1 J"},
    {"max", :max, "Max"}
  ]
  @period_params Map.new(@periods, fn {param, period, _label} -> {param, period} end)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :periods, @periods)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current={:overview}>
      <.header class="flex-wrap">
        Übersicht
        <:actions :if={!@empty}>
          <nav id="period" class="btn-group btn-group-sm" aria-label="Zeitraum">
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

      <div :if={!@empty} class="row row-cols-2 row-cols-lg-4 g-3 mb-4">
        <div class="col">
          <.stat id="net-worth" label="Vermögen" value={Format.euros(@net_worth)}>
            <:note class={tone(@change)}>{change_note(@change, @change_percent)}</:note>
          </.stat>
        </div>
      </div>

      <section :if={!@empty} class="card mb-4" aria-labelledby="history-title">
        <div class="card-header d-flex flex-wrap align-items-center justify-content-between gap-2">
          <h2 class="fs-6 fw-semibold mb-0" id="history-title">Wertentwicklung</h2>
          <span class="small text-body-secondary d-flex gap-3">
            <span class="text-nowrap"><span class="app-swatch app-swatch-primary"></span> Vermögen</span>
            <span class="text-nowrap">
              <span class="app-swatch app-swatch-secondary"></span> Investiert
            </span>
          </span>
        </div>
        <div class="card-body">
          <div role="img" aria-label={"Vermögen und investiertes Kapital #{period_text(@period)}"}>
            <div id="net-worth-chart" class="app-chart" phx-hook="NetWorthChart" phx-update="ignore">
              <canvas></canvas>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  slot :note do
    attr :class, :any
  end

  defp stat(assigns) do
    ~H"""
    <div class="card h-100" id={@id}>
      <div class="card-body">
        <div class="stat">
          <span class="stat-label">{@label}</span>
          <span class="stat-value">{@value}</span>
          <span :for={note <- @note} class={["small", note[:class]]}>{render_slot(note)}</span>
        </div>
      </div>
    </div>
    """
  end

  defp change_note(change, nil), do: "#{Format.signed_euros(change)} heute"

  defp change_note(change, percent),
    do: "#{Format.signed_euros(change)} heute (#{Format.signed_percent(percent)})"

  defp tone(change) when change > 0, do: "text-success"
  defp tone(change) when change < 0, do: "text-danger"
  defp tone(_change), do: "text-body-secondary"

  defp period_text(:six_months), do: "der letzten sechs Monate"
  defp period_text(:year_to_date), do: "seit Jahresbeginn"
  defp period_text(:one_year), do: "des letzten Jahres"
  defp period_text(:max), do: "seit der ersten Buchung"

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      MarketData.subscribe()
      MarketData.refresh_stale_quotes()
    end

    empty = Portfolios.list_portfolios(scope) == [] and Portfolios.list_accounts(scope) == []

    {:ok, socket |> assign(page_title: "Übersicht", empty: empty) |> load_net_worth()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(period: period(params["period"])) |> push_chart()}
  end

  defp period(param), do: Map.get(@period_params, param, :six_months)

  defp load_net_worth(%{assigns: %{empty: true}} = socket), do: socket

  defp load_net_worth(socket) do
    today = LocalTime.today()
    yesterday = Date.add(today, -1)

    %{^today => net_worth, ^yesterday => before} =
      Portfolios.net_worth(socket.assigns.current_scope, [yesterday, today])

    change = net_worth - before
    assign(socket, net_worth: net_worth, change: change, change_percent: percent(change, before))
  end

  # Relative to yesterday's net worth, when there was any.
  defp percent(_change, before) when before <= 0, do: nil
  defp percent(change, before), do: change |> Decimal.mult(100) |> Decimal.div(before)

  # The hook draws the chart once connected.
  defp push_chart(%{assigns: %{empty: true}} = socket), do: socket

  defp push_chart(socket) do
    if connected?(socket),
      do: push_event(socket, "net-worth-chart", chart(socket.assigns)),
      else: socket
  end

  # Amounts in cents, per day of the period that the chart shows.
  defp chart(%{current_scope: scope, period: period}) do
    first_day = Portfolios.first_transaction_date(scope)
    days = period |> Period.range(LocalTime.today(), first_day) |> Period.chart_days()
    history = Portfolios.history(scope, days)

    %{
      dates: Enum.map(history, & &1.date),
      net_worth: Enum.map(history, & &1.net_worth),
      invested_capital: Enum.map(history, & &1.invested_capital)
    }
  end

  @impl true
  def handle_info(:market_data_updated, socket),
    do: {:noreply, socket |> load_net_worth() |> push_chart()}
end
