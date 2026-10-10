defmodule ZipfelfolioWeb.OverviewLive do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{LocalTime, MarketData, Portfolios}
  alias ZipfelfolioWeb.Format

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current={:overview}>
      <.header>Übersicht</.header>

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

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_net_worth(socket)}
end
