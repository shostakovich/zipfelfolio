defmodule ZipfelfolioWeb.HoldingsLive do
  use ZipfelfolioWeb, :live_view

  import ZipfelfolioWeb.AllocationComponents

  alias Zipfelfolio.{LocalTime, MarketData, Portfolios}
  alias ZipfelfolioWeb.Format

  # Allocation tab, also its URL parameter, and label; the first is the default. A taxonomy's tab
  # is its id.
  @allocation_tabs [regions: "Regionen", sectors: "Sektoren"]
  @allocation_params Map.new(@allocation_tabs, fn {tab, _label} -> {Atom.to_string(tab), tab} end)
  @default_tab @allocation_tabs |> hd() |> elem(0)

  @source "Durchsicht durch die Fonds mit den Länder- und Sektordaten von DivvyDiary"

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
          <.portfolio_switcher holdings={@holdings} allocation_tab={@allocation_tab} />
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
                  <.link
                    navigate={~p"/securities/#{row.security}"}
                    class="fw-semibold text-body text-decoration-none"
                  >
                    {row.security.name}
                  </.link>
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

      <%!-- Side by side from 1400 px, where the costs still fit four columns. --%>
      <div :if={!@empty and @holdings.costs.funds != []} class="row g-4">
        <div class="col-xxl-7">
          <.allocation
            allocation={@holdings.allocation}
            tab={shown_tab(assigns)}
            tabs={allocation_tabs(assigns)}
            available={@compositions_available}
          />
        </div>
        <div class="col-xxl-5">
          <.costs costs={@holdings.costs} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :allocation, :map, required: true
  attr :tab, :any, required: true, doc: "`:regions`, `:sectors` or the id of a taxonomy"
  attr :tabs, :list, required: true, doc: "each with its `label`, `path` and whether `active`"
  attr :available, :boolean, required: true, doc: "whether DivvyDiary has its API key"

  defp allocation(assigns) do
    ~H"""
    <section id="allocation" class="card h-100" aria-label="Aufteilung">
      <div class="card-header">
        <.card_tabs label="Aufteilung nach" tabs={@tabs} />
      </div>
      <.composition :if={is_atom(@tab)} allocation={@allocation} tab={@tab} available={@available} />
      <.classifications
        :if={is_integer(@tab)}
        allocation={taxonomy_allocation(@allocation, @tab)}
      />
    </section>
    """
  end

  attr :allocation, :map, required: true
  attr :tab, :atom, required: true
  attr :available, :boolean, required: true

  # Regions or sectors from the compositions of the funds.
  defp composition(assigns) do
    assigns = assign(assigns, :rows, Map.fetch!(assigns.allocation, assigns.tab))

    ~H"""
    <div class="card-body">
      <.missing_key :if={!@available} />
      <.composition_bars :if={@available} id="allocation-rows" rows={@rows} />
    </div>
    <div :if={@available} class="card-footer small text-body-secondary">
      {source(@allocation.as_of)} Konten zählen nicht mit.
      <span :if={Enum.any?(@rows, &is_nil(&1.key))}>
        „Ohne Angabe“: Wertpapiere ohne Länder- oder Sektordaten von DivvyDiary.
      </span>
    </div>
    """
  end

  attr :allocation, :map, required: true, doc: "into a taxonomy, see `Classifications.of/3`"

  # The top-level classifications of a taxonomy against their targets.
  defp classifications(assigns) do
    rows = assigns.allocation.classifications

    assigns =
      assign(assigns, rows: rows, scale: bar_scale(Enum.flat_map(rows, &[&1.share, &1.target])))

    ~H"""
    <div class="card-body">
      <ul id="allocation-rows" class="list-unstyled d-flex flex-column gap-3 mb-0">
        <li :for={row <- @rows} id={"classification-#{row.classification.id}"}>
          <div class="d-flex justify-content-between gap-3 small mb-1">
            <span class="fw-semibold">{row.classification.name}</span>
            <span class="tabular-nums text-nowrap">
              <span class={deviation_tone(row.deviation)}>{in_percent(row.share)}</span>
              <span class="text-body-secondary">/ Ziel {in_percent(row.target)}</span>
            </span>
          </div>
          <div class="app-allocation-bar bg-body-tertiary rounded-pill" aria-hidden="true">
            <div style={"width: #{bar_position(row.share, @scale)}%"}></div>
            <div
              class="app-allocation-target"
              style={"left: #{bar_position(row.target, @scale)}%"}
            >
            </div>
          </div>
        </li>
      </ul>
      <p :if={@allocation.unassigned} class="small text-body-secondary mt-3 mb-0">
        Ohne Kategorie: {unassigned(@allocation.unassigned)}. Die Anteile beziehen sich wie die
        Ziele auf den zugeordneten Wert.
      </p>
    </div>
    <div class="card-footer small text-body-secondary">
      Balken: Ist · Strich: dein Ziel · Zuordnungen und Ziele aus Portfolio Performance
    </div>
    """
  end

  attr :costs, :map, required: true

  defp costs(assigns) do
    ~H"""
    <%!-- On a phone the fund size goes under the name. --%>
    <section id="costs" class="card h-100" aria-labelledby="costs-title">
      <div class="card-header d-flex flex-wrap align-items-baseline justify-content-between gap-2">
        <h2 class="fs-6 fw-semibold mb-0" id="costs-title">Kosten</h2>
        <span :if={@costs.ter} class="small text-body-secondary">
          gewichtet {Format.ter(@costs.ter)}
        </span>
      </div>
      <div class="table-responsive">
        <table class="table table-sm align-middle mb-0 tabular-nums">
          <thead>
            <tr>
              <th scope="col">Wertpapier</th>
              <th scope="col" class="text-end">TER</th>
              <th scope="col" class="text-end d-none d-sm-table-cell">Größe</th>
              <th scope="col" class="text-end text-nowrap">pro Jahr</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={fund <- @costs.funds} id={"cost-#{fund.security.id}"}>
              <td>
                <.link navigate={~p"/securities/#{fund.security}"} class="text-body">
                  {fund.security.name}
                </.link>
                <div :if={fund.fund_size} class="small text-body-secondary text-nowrap d-sm-none">
                  {fund_size(fund)}
                </div>
              </td>
              <td class="text-end text-nowrap">{Format.ter(fund.ter)}</td>
              <td class="text-end text-nowrap d-none d-sm-table-cell">{fund_size(fund)}</td>
              <td class="text-end text-nowrap">{per_year(fund.per_year)}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr id="costs-total" class="fw-bold">
              <th scope="row">Gesamt</th>
              <td class="text-end text-nowrap">{Format.ter(@costs.ter)}</td>
              <td class="d-none d-sm-table-cell"></td>
              <td class="text-end text-nowrap">{per_year(@costs.per_year)}</td>
            </tr>
          </tfoot>
        </table>
      </div>
      <div class="card-footer small text-body-secondary">
        Laufende Kosten, die im Kurs stecken. Ordergebühren kommen aus den Buchungen.
        <span :if={Enum.any?(@costs.funds, &is_nil(&1.ter))}>
          Wertpapiere ohne TER in Portfolio Performance zählen nicht mit.
        </span>
      </div>
    </section>
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
  attr :allocation_tab, :any, required: true

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
          <.menu_item patch={holdings_path(allocation: @allocation_tab)} active={!@holdings.portfolio}>
            Gesamt
          </.menu_item>
        </li>
        <li :if={@holdings.portfolios != []}><hr class="dropdown-divider" /></li>
        <li :for={portfolio <- @holdings.portfolios}>
          <.menu_item
            patch={holdings_path(portfolio: portfolio.id, allocation: @allocation_tab)}
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

  # The holdings with `params`; nil and the default tab are left out.
  defp holdings_path(params) do
    query =
      params
      |> Keyword.update(:allocation, nil, &allocation_param/1)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    ~p"/holdings?#{query}"
  end

  defp allocation_param(@default_tab), do: nil
  defp allocation_param(tab) when is_atom(tab), do: Atom.to_string(tab)
  defp allocation_param(taxonomy_id), do: Integer.to_string(taxonomy_id)

  # Regions, sectors, then each taxonomy with value shown in it. A tab keeps the portfolio and the
  # account marked.
  defp allocation_tabs(assigns) do
    shown = shown_tab(assigns)

    taxonomies =
      for %{taxonomy: taxonomy} <- assigns.holdings.allocation.taxonomies,
          do: {taxonomy.id, taxonomy.name}

    for {tab, label} <- @allocation_tabs ++ taxonomies do
      path =
        holdings_path(
          portfolio: shown_portfolio_id(assigns),
          account: assigns.account_id,
          allocation: tab
        )

      %{label: label, path: path, active: tab == shown}
    end
  end

  # The tab in the URL; the first for a taxonomy without value shown in it.
  defp shown_tab(%{allocation_tab: id, holdings: holdings}) when is_integer(id) do
    if taxonomy_allocation(holdings.allocation, id), do: id, else: @default_tab
  end

  defp shown_tab(%{allocation_tab: tab}), do: tab

  defp taxonomy_allocation(allocation, id),
    do: Enum.find(allocation.taxonomies, &(&1.taxonomy.id == id))

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

  defp price(%{price: price, security: security}), do: Format.price(price, security.currency)

  defp deviation_tone(:above), do: "text-warning-emphasis"
  defp deviation_tone(:below), do: "text-danger"
  defp deviation_tone(nil), do: "text-success"

  defp unassigned(%{value: value, share: nil}), do: Format.euros(value, 2)

  defp unassigned(%{value: value, share: share}),
    do: "#{Format.euros(value, 2)} (#{in_percent(share)} des Werts)"

  defp source(nil), do: @source <> "."

  defp source(as_of), do: "#{@source}, Stand #{Format.date(as_of)}."

  defp fund_size(fund), do: Format.fund_size(fund.fund_size, fund.security.currency)

  defp per_year(nil), do: "–"
  defp per_year(cents), do: Format.euros(cents)

  defp share(_value, net_worth) when net_worth <= 0, do: nil
  defp share(value, net_worth), do: value |> Format.percent_of(net_worth) |> Format.percent()

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    empty = Portfolios.list_portfolios(scope) == [] and Portfolios.list_accounts(scope) == []

    {:ok,
     assign(socket,
       page_title: "Bestand",
       empty: empty,
       compositions_available: MarketData.compositions_available?()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(
      portfolio_id: parse_id(params["portfolio"]),
      account_id: parse_id(params["account"])
    )
    |> assign(allocation_tab: allocation_tab(params["allocation"]))
    |> load_holdings()
    |> then(&{:noreply, &1})
  end

  # Regions, sectors or the id of a taxonomy.
  defp allocation_tab(param),
    do: Map.get(@allocation_params, param) || parse_id(param) || @default_tab

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_holdings(socket)}

  defp load_holdings(%{assigns: %{empty: true}} = socket), do: socket

  defp load_holdings(socket) do
    %{current_scope: scope, portfolio_id: portfolio_id} = socket.assigns
    assign(socket, holdings: Portfolios.holdings(scope, portfolio_id, LocalTime.today()))
  end
end
