defmodule ZipfelfolioWeb.OverviewLive do
  use ZipfelfolioWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current={:overview}>
      <.header>Übersicht</.header>
      <.card>
        <p class="mb-0">
          Noch keine Portfolios. Sie kommen mit dem Import aus Portfolio Performance.
        </p>
      </.card>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Übersicht")}
end
