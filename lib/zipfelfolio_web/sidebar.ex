defmodule ZipfelfolioWeb.Sidebar do
  @moduledoc """
  The portfolios and accounts with their values that the sidebar, and on the phone the „Depots“
  screen, list on every page of a signed-in user. An `on_mount` hook assigns them as `@sidebar`
  and loads them again when new prices arrive.

  The hook subscribes the page to the market data and refreshes stale quotes, so a LiveView that
  shows prices itself only handles `:market_data_updated`, which reaches it after the sidebar.
  It counts the recognised receipts in the inbox for the badge on „Buchungen“, as
  `@sidebar.inbox`; a page that shows the inbox itself, i.e. assigns `:inbox`, also gets
  `:receipts_updated`.
  """
  use ZipfelfolioWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Zipfelfolio.{LocalTime, MarketData, Portfolios, Receipts}

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      MarketData.subscribe()
      Receipts.subscribe(socket.assigns.current_scope)
      MarketData.refresh_stale_quotes()
    end

    {:cont, socket |> load() |> attach_hook(:sidebar, :handle_info, &reload/2)}
  end

  defp reload(:market_data_updated, socket), do: {:cont, load(socket)}

  defp reload(:receipts_updated, socket) do
    socket = assign(socket, :sidebar, %{socket.assigns.sidebar | inbox: inbox_count(socket)})
    if Map.has_key?(socket.assigns, :inbox), do: {:cont, socket}, else: {:halt, socket}
  end

  defp reload(_message, socket), do: {:cont, socket}

  defp load(socket) do
    sidebar = Portfolios.sidebar(socket.assigns.current_scope, LocalTime.today())
    assign(socket, :sidebar, Map.put(sidebar, :inbox, inbox_count(socket)))
  end

  defp inbox_count(socket), do: Receipts.inbox_count(socket.assigns.current_scope)

  @doc "A portfolio opens its holdings."
  def portfolio_path(portfolio), do: ~p"/holdings?#{[portfolio: portfolio.id]}"

  @doc """
  An account opens the holdings of the portfolio it belongs to with its row marked, an account of
  no portfolio all holdings.
  """
  def account_path(nil, account), do: ~p"/holdings?#{[account: account.id]}"

  def account_path(portfolio, account),
    do: ~p"/holdings?#{[portfolio: portfolio.id, account: account.id]}"
end
