defmodule ZipfelfolioWeb.HoldingsLive do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{LocalTime, Portfolios}
  alias ZipfelfolioWeb.Format

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={{:holdings, shown_portfolio_id(assigns), @account_id}}
    >
      <.header class="flex-wrap">
        Bestand
        <:subtitle :if={!@empty}>{subtitle(@holdings)}</:subtitle>
        <:actions :if={!@empty}>
          <.portfolio_switcher holdings={@holdings} />
        </:actions>
      </.header>

      <.card :if={@empty}>
        <p class="mb-0">
          Noch keine Depots. Sie kommen mit dem <.link navigate={~p"/settings/import"}>Import aus Portfolio Performance</.link>.
        </p>
      </.card>

      <%!-- Below 992 px shares and price go under the name, below 768 px purchase value and share
           go, and on a phone the gain goes under the value. --%>
      <section :if={!@empty} id="holdings" class="card mb-4" aria-label="Bestand">
        <div class="table-responsive">
          <table class="table table-hover align-middle mb-0 tabular-nums">
            <thead>
              <tr>
                <th scope="col">Wertpapier</th>
                <th scope="col" class="text-end d-none d-lg-table-cell">Stück</th>
                <th scope="col" class="text-end d-none d-lg-table-cell">Kurs</th>
                <th scope="col" class="text-end">Wert</th>
                <th scope="col" class="text-end d-none d-md-table-cell">Einstand</th>
                <th scope="col" class="text-end d-none d-sm-table-cell">Gewinn</th>
                <th scope="col" class="text-end d-none d-md-table-cell">Anteil</th>
              </tr>
            </thead>
            <tbody :for={group <- @holdings.groups} id={group_id(group)}>
              <tr class="table-group-divider">
                <th
                  scope="colgroup"
                  colspan="7"
                  class="small fw-semibold text-body-secondary bg-body-tertiary"
                >
                  {if group.portfolio, do: group.portfolio.name, else: "Konten"}
                </th>
              </tr>
              <tr
                :for={row <- group.holdings}
                id={"holding-#{group.portfolio.id}-#{row.security.id}"}
              >
                <td>
                  <span class="fw-semibold">{row.security.name}</span>
                  <div :if={row.security.isin} class="small text-body-secondary d-none d-lg-block">
                    {row.security.isin}
                  </div>
                  <div class="small text-body-secondary d-lg-none">
                    <span class="text-nowrap">{Format.shares(row.shares)} Stück</span>
                    · <span class="text-nowrap">{price(row)}</span>
                  </div>
                </td>
                <td class="text-end text-nowrap d-none d-lg-table-cell">
                  {Format.shares(row.shares)}
                </td>
                <td class="text-end text-nowrap d-none d-lg-table-cell">{price(row)}</td>
                <td class="text-end text-nowrap">
                  <span class="fw-semibold">{Format.euros(row.value, 2)}</span>
                  <.gain class="small d-sm-none" gain={row.gain} purchase_value={row.purchase_value} />
                </td>
                <td class="text-end text-nowrap d-none d-md-table-cell">
                  {Format.euros(row.purchase_value, 2)}
                </td>
                <td class="text-end text-nowrap d-none d-sm-table-cell">
                  <.gain gain={row.gain} purchase_value={row.purchase_value} />
                </td>
                <td class="text-end text-nowrap d-none d-md-table-cell">
                  {share(row.value, @holdings.net_worth)}
                </td>
              </tr>
              <tr :if={group.portfolio && group.holdings == []}>
                <td colspan="7" class="small text-body-secondary">Keine Wertpapiere</td>
              </tr>
              <tr
                :for={row <- group.accounts}
                id={"account-#{row.account.id}"}
                class={row.account.id == @account_id && "table-active"}
                aria-current={row.account.id == @account_id && "true"}
              >
                <td>
                  <span class="d-inline-flex align-items-center gap-2 fw-semibold">
                    <.icon name="wallet" class="app-icon-sm text-body-secondary" />
                    {row.account.name}
                  </span>
                  <div class="small text-body-secondary">{account_note(group, row.account)}</div>
                </td>
                <td class="d-none d-lg-table-cell"></td>
                <td class="d-none d-lg-table-cell"></td>
                <td class="text-end text-nowrap fw-semibold">{Format.euros(row.value, 2)}</td>
                <td class="d-none d-md-table-cell"></td>
                <td class="d-none d-sm-table-cell"></td>
                <td class="text-end text-nowrap d-none d-md-table-cell">
                  {share(row.value, @holdings.net_worth)}
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr id="total" class="fw-bold">
                <th scope="row">
                  {if @holdings.portfolio, do: @holdings.portfolio.name, else: "Gesamt"}
                </th>
                <td class="d-none d-lg-table-cell"></td>
                <td class="d-none d-lg-table-cell"></td>
                <td class="text-end text-nowrap">
                  {Format.euros(@holdings.total.value, 2)}
                  <.gain class="small d-sm-none" gain={@holdings.total.gain} />
                </td>
                <td class="text-end text-nowrap d-none d-md-table-cell">
                  {Format.euros(@holdings.total.purchase_value, 2)}
                </td>
                <td class="text-end text-nowrap d-none d-sm-table-cell">
                  <.gain gain={@holdings.total.gain} />
                </td>
                <td class="text-end text-nowrap d-none d-md-table-cell">
                  {@holdings.portfolio && share(@holdings.total.value, @holdings.net_worth)}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :gain, :integer, required: true
  attr :purchase_value, :integer, default: 0, doc: "gives the gain in percent when positive"
  attr :class, :any, default: nil

  defp gain(assigns) do
    assigns = assign(assigns, :shown, Format.signed_euros(assigns.gain, 2))

    ~H"""
    <div class={[tone(@shown), @class]}>
      {@shown}
      <div :if={@purchase_value > 0} class="small">
        {@gain |> Format.percent_of(@purchase_value) |> Format.signed_percent(1)}
      </div>
    </div>
    """
  end

  attr :holdings, :map, required: true

  # A Bootstrap dropdown without Bootstrap's JS: LiveView's JS commands toggle it.
  defp portfolio_switcher(assigns) do
    ~H"""
    <div
      class="dropdown"
      phx-click-away={hide_menu()}
      phx-window-keydown={hide_menu()}
      phx-key="Escape"
    >
      <button
        id="portfolio-menu-toggle"
        type="button"
        class="btn btn-sm btn-light dropdown-toggle"
        aria-expanded="false"
        aria-controls="portfolio-menu"
        phx-click={
          JS.toggle_class("show", to: "#portfolio-menu")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
      >
        {if @holdings.portfolio, do: @holdings.portfolio.name, else: "Gesamt"}
      </button>
      <ul id="portfolio-menu" class="dropdown-menu dropdown-menu-end" data-bs-popper="static">
        <li>
          <.menu_item patch={~p"/holdings"} active={!@holdings.portfolio}>Gesamt</.menu_item>
        </li>
        <li :if={@holdings.portfolios != []}><hr class="dropdown-divider" /></li>
        <li :for={portfolio <- @holdings.portfolios}>
          <.menu_item
            patch={~p"/holdings?#{[portfolio: portfolio.id]}"}
            active={@holdings.portfolio && @holdings.portfolio.id == portfolio.id}
          >
            <Layouts.chip portfolio={portfolio} />{portfolio.name}
          </.menu_item>
        </li>
      </ul>
    </div>
    """
  end

  attr :patch, :string, required: true
  attr :active, :boolean, required: true
  slot :inner_block, required: true

  defp menu_item(assigns) do
    ~H"""
    <.link
      patch={@patch}
      class={["dropdown-item d-flex align-items-center gap-2", @active && "active"]}
      aria-current={@active && "page"}
      phx-click={hide_menu()}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp hide_menu do
    JS.remove_class("show", to: "#portfolio-menu")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#portfolio-menu-toggle")
  end

  # The portfolio shown, nil for all, which the sidebar marks.
  defp shown_portfolio_id(%{holdings: %{portfolio: %{id: id}}}), do: id
  defp shown_portfolio_id(_assigns), do: nil

  defp group_id(%{portfolio: nil}), do: "accounts"
  defp group_id(%{portfolio: portfolio}), do: "portfolio-#{portfolio.id}"

  defp subtitle(%{portfolio: nil, portfolios: portfolios, groups: groups}) do
    securities = groups |> Enum.flat_map(& &1.holdings) |> Enum.uniq_by(& &1.security.id)
    accounts = Enum.flat_map(groups, & &1.accounts)

    Enum.join(
      [
        count(length(portfolios), "Depot", "Depots"),
        count(length(securities), "Wertpapier", "Wertpapiere"),
        count(length(accounts), "Konto", "Konten")
      ],
      " · "
    )
  end

  defp subtitle(%{groups: [group]}) do
    Enum.join(
      [count(length(group.holdings), "Wertpapier", "Wertpapiere")] ++
        Enum.map(group.accounts, & &1.account.name),
      " · "
    )
  end

  defp count(0, _one, many), do: "keine\u00A0#{many}"
  defp count(1, one, _many), do: "1\u00A0#{one}"
  defp count(count, _one, many), do: "#{count}\u00A0#{many}"

  defp account_note(%{portfolio: nil}, account), do: account.currency
  defp account_note(_portfolio_group, account), do: "Referenzkonto · #{account.currency}"

  defp price(%{price: price, security: %{currency: "EUR"}}), do: Format.price(price, "€")
  defp price(%{price: price, security: security}), do: Format.price(price, security.currency)

  defp share(_value, net_worth) when net_worth <= 0, do: nil
  defp share(value, net_worth), do: value |> Format.percent_of(net_worth) |> Format.percent()

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    empty = Portfolios.list_portfolios(scope) == [] and Portfolios.list_accounts(scope) == []

    {:ok, assign(socket, page_title: "Bestand", empty: empty)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(portfolio_id: id(params["portfolio"]), account_id: id(params["account"]))
    |> load_holdings()
    |> then(&{:noreply, &1})
  end

  defp id(param) when is_binary(param) do
    case Integer.parse(param) do
      {id, ""} -> id
      _invalid -> nil
    end
  end

  defp id(_missing), do: nil

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_holdings(socket)}

  defp load_holdings(%{assigns: %{empty: true}} = socket), do: socket

  defp load_holdings(socket) do
    %{current_scope: scope, portfolio_id: portfolio_id} = socket.assigns
    assign(socket, holdings: Portfolios.holdings(scope, portfolio_id, LocalTime.today()))
  end
end
