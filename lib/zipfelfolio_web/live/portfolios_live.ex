defmodule ZipfelfolioWeb.PortfoliosLive do
  @moduledoc """
  „Depots“, the phone's tab for the money half of the sidebar: the total, then each portfolio
  with its reference account and the accounts of no portfolio, from `@sidebar`.
  """
  use ZipfelfolioWeb, :live_view

  alias ZipfelfolioWeb.{Format, Sidebar}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:portfolios}
    >
      <.header>Depots</.header>

      <.card :if={@sidebar.portfolios == [] and @sidebar.accounts == []}>
        <p class="mb-0">
          Noch keine Depots. Sie kommen mit dem <.link navigate={~p"/settings/import"}>Import aus Portfolio Performance</.link>.
        </p>
      </.card>

      <div :if={@sidebar.portfolios != [] or @sidebar.accounts != []} class="app-tree">
        <div class="list-group mb-4">
          <.tree_link
            id="tree-total"
            navigate={~p"/holdings"}
            name="Gesamt"
            value={Layouts.total(@sidebar.portfolios) + Layouts.total(@sidebar.accounts)}
          >
            <span class="app-chip app-chip-all" aria-hidden="true"><.icon name="layers" /></span>
          </.tree_link>
        </div>

        <.group :if={@sidebar.portfolios != []} title="Depots" rows={@sidebar.portfolios}>
          <%= for row <- @sidebar.portfolios do %>
            <.tree_link
              id={"tree-portfolio-#{row.portfolio.id}"}
              navigate={Sidebar.portfolio_path(row.portfolio)}
              name={row.portfolio.name}
              value={row.value}
            >
              <Layouts.chip portfolio={row.portfolio} />
            </.tree_link>
            <.tree_link
              :if={row.account}
              id={"tree-account-#{row.account.account.id}"}
              class="app-sub"
              navigate={Sidebar.account_path(row.portfolio, row.account.account)}
              name={row.account.account.name}
              value={row.account.value}
            >
              <.icon name="wallet" />
            </.tree_link>
          <% end %>
        </.group>

        <.group :if={@sidebar.accounts != []} title="Konten" rows={@sidebar.accounts}>
          <.tree_link
            :for={row <- @sidebar.accounts}
            id={"tree-account-#{row.account.id}"}
            navigate={Sidebar.account_path(nil, row.account)}
            name={row.account.name}
            value={row.value}
          >
            <Layouts.wallet_chip />
          </.tree_link>
        </.group>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true
  slot :inner_block, required: true

  defp group(assigns) do
    ~H"""
    <h2 class="app-sheet-h">
      <span>{@title}</span><span>{Format.euros(Layouts.total(@rows), 2)}</span>
    </h2>
    <div class="list-group mb-4">{render_slot(@inner_block)}</div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :name, :string, required: true
  attr :value, :integer, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true, doc: "the chip or icon"

  defp tree_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={["list-group-item list-group-item-action", @class]}
    >
      {render_slot(@inner_block)}
      <span class="me-auto text-truncate">{@name}</span>
      <span class={["tabular-nums text-nowrap", @value == 0 && "text-body-secondary"]}>
        {Format.euros(@value, 2)}
      </span>
      <.icon name="chevron" class="app-chev" />
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Depots")}
end
