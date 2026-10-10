defmodule ZipfelfolioWeb.SecurityLive do
  use ZipfelfolioWeb, :live_view

  import ZipfelfolioWeb.AllocationComponents

  alias Zipfelfolio.{ExchangeRates, LocalTime, MarketData, Portfolios, Securities}
  alias ZipfelfolioWeb.{AttributeValue, Format, Sidebar}

  # URL parameter, period and button label; the first is the default.
  @periods [
    {"1y", :one_year, "1 J"},
    {"5y", :five_years, "5 J"},
    {"max", :max, "Max"}
  ]
  @period_params Map.new(@periods, fn {param, period, _label} -> {param, period} end)

  # Composition tab, also its URL parameter, and label; the first is the default.
  @composition_tabs [regions: "Regionen", sectors: "Sektoren"]

  # The distributions shown until all are asked for.
  @recent_distributions 8

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
            <div class="fs-3 fw-bold">{Format.price(@price, @security.currency)}</div>
            <div
              :if={@price_yesterday}
              class={["small", tone(change_note(@price, @price_yesterday, @security.currency))]}
            >
              {change_note(@price, @price_yesterday, @security.currency)}
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
                  :for={{_param, period, label} <- @periods}
                  patch={security_path(@security, period, @composition_tab)}
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

      <div class="row g-4">
        <div class="col-lg-7 d-flex flex-column gap-4">
          <.distributions distributions={@distributions} />
          <.composition
            composition={@profile.composition}
            tab={@composition_tab}
            tabs={composition_tabs(assigns)}
            available={@compositions_available}
            isin={@security.isin}
          />
        </div>
        <div class="col-lg-5 d-flex flex-column gap-4">
          <.profile profile={@profile} security={@security} costs_per_year={@costs_per_year} />
          <.sources
            security={@security}
            exchange_rate={@exchange_rate}
            composition={@profile.composition}
            available={@compositions_available}
          />
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

  attr :distributions, :list, required: true, doc: "see `Distributions.of/3`"

  # The newest first; on a phone without ex-dates and shares.
  defp distributions(assigns) do
    distributions = assigns.distributions

    assigns =
      assign(assigns,
        ex_dates: Enum.any?(distributions, & &1.ex_date),
        total: Enum.sum_by(distributions, & &1.gross),
        recent: @recent_distributions
      )

    ~H"""
    <section id="distributions" class="card" aria-labelledby="distributions-title">
      <div class="card-header d-flex flex-wrap align-items-baseline justify-content-between gap-2">
        <h2 class="fs-6 fw-semibold mb-0" id="distributions-title">Ausschüttungen je Anteil</h2>
        <span :if={@distributions != []} class="small text-body-secondary text-nowrap">
          gesamt {Format.euros(@total, 2)}
        </span>
      </div>
      <p :if={@distributions == []} class="card-body text-body-secondary mb-0">
        Keine Ausschüttungen gebucht.
      </p>
      <div :if={@distributions != []} class="table-responsive">
        <table class="table table-sm align-middle text-nowrap mb-0 tabular-nums">
          <thead>
            <tr>
              <th :if={@ex_dates} scope="col" class="d-none d-sm-table-cell">Ex-Tag</th>
              <th scope="col">Zahltag</th>
              <th scope="col" class="text-end">je Anteil</th>
              <th scope="col" class="text-end d-none d-sm-table-cell">Stück</th>
              <th scope="col" class="text-end">Brutto</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{row, index} <- Enum.with_index(@distributions)}
              class={index >= @recent && "d-none"}
              data-older={index >= @recent}
            >
              <td :if={@ex_dates} class="d-none d-sm-table-cell">{Format.date(row.ex_date)}</td>
              <td>{Format.date(row.date)}</td>
              <td class="text-end">{Format.price(row.per_share, row.currency)}</td>
              <td class="text-end d-none d-sm-table-cell">
                {if row.shares > 0, do: Format.shares(row.shares), else: "–"}
              </td>
              <td class="text-end">{Format.euros(row.gross, 2)}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div
        :if={@distributions != []}
        class="card-footer small text-body-secondary d-flex flex-wrap justify-content-between gap-2"
      >
        <span>Aus deinen gebuchten Dividenden, vor Steuern und Gebühren.</span>
        <button
          :if={length(@distributions) > @recent}
          id="distributions-all"
          type="button"
          class="btn btn-link btn-sm p-0"
          phx-click={JS.remove_class("d-none", to: "#distributions tr[data-older]") |> JS.hide()}
        >
          Alle {length(@distributions)} anzeigen
        </button>
      </div>
    </section>
    """
  end

  attr :composition, :map, required: true, doc: "see `Allocation.of_composition/1`, or nil"
  attr :tab, :atom, required: true
  attr :tabs, :list, required: true
  attr :available, :boolean, required: true, doc: "whether DivvyDiary has its API key"
  attr :isin, :string, required: true

  # Regions and sectors as the holdings show them, if DivvyDiary delivered them.
  defp composition(assigns) do
    assigns = assign(assigns, :shown, assigns.available and assigns.composition != nil)

    ~H"""
    <section id="composition" class="card" aria-label="Zusammensetzung">
      <div class="card-header">
        <.card_tabs :if={@shown} label="Zusammensetzung nach" tabs={@tabs} />
        <h2 :if={!@shown} class="fs-6 fw-semibold mb-0">Zusammensetzung</h2>
      </div>
      <div class="card-body">
        <.missing_key :if={!@available} />
        <p :if={@available and !@composition} class="text-body-secondary mb-0">
          {if @isin in [nil, ""],
            do: "Ohne ISIN fragt zipfelfolio DivvyDiary nicht nach Ländern und Sektoren.",
            else: "Von DivvyDiary liegen für dieses Wertpapier keine Länder und Sektoren vor."}
        </p>
        <.composition_bars :if={@shown} id="composition-rows" rows={Map.fetch!(@composition, @tab)} />
      </div>
      <div :if={@shown} class="card-footer small text-body-secondary">
        Länder und Sektoren von DivvyDiary, Stand {Format.date(@composition.as_of)}.
      </div>
    </section>
    """
  end

  attr :profile, :map, required: true, doc: "see `Securities.profile/2`"
  attr :security, :map, required: true
  attr :costs_per_year, :integer, required: true, doc: "of the user's holdings, nil without"

  # TER and fund size as the costs on the holdings screen show them, then every other attribute
  # under the name of its type.
  defp profile(assigns) do
    assigns = assign(assigns, :rows, profile_rows(assigns))

    ~H"""
    <section id="profile" class="card" aria-labelledby="profile-title">
      <div class="card-header">
        <h2 class="fs-6 fw-semibold mb-0" id="profile-title">Steckbrief</h2>
      </div>
      <p :if={@rows == []} class="card-body text-body-secondary mb-0">
        Keine Angaben aus Portfolio Performance.
      </p>
      <dl :if={@rows != []} class="row mb-0 card-body small">
        <%= for {label, value} <- @rows do %>
          <dt class="col-5 fw-normal text-body-secondary">{label}</dt>
          <dd class="col-7 text-end text-break"><.attribute value={value} /></dd>
        <% end %>
      </dl>
    </section>
    """
  end

  defp profile_rows(%{profile: profile, security: security, costs_per_year: costs_per_year}) do
    ter =
      if profile.ter,
        do: [{"TER", {:text, ter(profile.ter, costs_per_year)}}],
        else: []

    fund_size =
      if profile.fund_size,
        do: [{"Fondsgröße", {:text, Format.fund_size(profile.fund_size, security.currency)}}],
        else: []

    attributes =
      for {type, value} <- profile.attributes,
          shown = AttributeValue.display(type, value, security.currency),
          do: {type.name, shown}

    ter ++ fund_size ++ attributes
  end

  defp ter(ter, nil), do: Format.ter(ter)
  defp ter(ter, per_year), do: "#{Format.ter(ter)} · #{Format.euros(per_year)} im Jahr"

  attr :value, :any, required: true, doc: "see `AttributeValue.display/3`"

  defp attribute(%{value: {:text, text}} = assigns) do
    assigns = assign(assigns, :text, text)
    ~H"{@text}"
  end

  defp attribute(%{value: {:link, label, url}} = assigns) do
    assigns = assign(assigns, label: label, url: url)

    ~H"""
    <a href={@url} target="_blank" rel="noopener noreferrer">{@label}</a>
    """
  end

  defp attribute(%{value: {:image, uri}} = assigns) do
    assigns = assign(assigns, :uri, uri)

    ~H"""
    <img src={@uri} alt="" height="32" />
    """
  end

  attr :security, :map, required: true
  attr :exchange_rate, :map, required: true, doc: "the latest of its currency, nil without"
  attr :composition, :map, required: true
  attr :available, :boolean, required: true

  defp sources(assigns) do
    ~H"""
    <section id="sources" class="card" aria-labelledby="sources-title">
      <div class="card-header">
        <h2 class="fs-6 fw-semibold mb-0" id="sources-title">Datenquellen</h2>
      </div>
      <ul class="list-group list-group-flush small">
        <li class="list-group-item d-flex gap-2">
          <span class="me-auto">Kurse</span>
          <span :if={@security.quote_feed == :yahoo} class="text-end">
            <span class="d-block">Yahoo · <code>{@security.symbol}</code></span>
            <span :if={@security.fetch_error} class="d-block text-danger">
              {@security.fetch_error}
            </span>
            <span :if={!@security.fetch_error} class="d-block text-body-secondary">
              {fetched(@security.fetched_at)}
            </span>
          </span>
          <span :if={@security.quote_feed == :manual} class="text-end">
            <span class="d-block">Manuell</span>
            <span class="d-block text-body-secondary">aus Portfolio Performance oder von Hand</span>
          </span>
        </li>
        <li :if={@security.currency != "EUR"} class="list-group-item d-flex gap-2">
          <span class="me-auto">Wechselkurs {@security.currency}</span>
          <span class="text-end">
            <span class="d-block">EZB{@exchange_rate && " · #{Format.rate(@exchange_rate.rate)}"}</span>
            <span class="d-block text-body-secondary">
              {if @exchange_rate,
                do: "Stand #{Format.date(@exchange_rate.date)}",
                else: "noch kein Kurs"}
            </span>
          </span>
        </li>
        <li class="list-group-item d-flex gap-2">
          <span class="me-auto">Länder und Sektoren</span>
          <span class="text-end">
            <span class="d-block">DivvyDiary</span>
            <span class="d-block text-body-secondary">
              {composition_source(@available, @composition, @security.isin)}
            </span>
          </span>
        </li>
      </ul>
      <div class="card-footer">
        <.link
          navigate={"#{~p"/settings/securities"}#security-#{@security.id}"}
          class="btn btn-sm btn-outline-secondary"
        >
          Kursquelle ändern
        </.link>
      </div>
    </section>
    """
  end

  defp fetched(nil), do: "noch nicht abgerufen"
  defp fetched(at), do: "abgerufen #{Format.datetime(at)}"

  defp composition_source(false = _available, _composition, _isin), do: "ohne API-Key"
  defp composition_source(true, %{as_of: as_of}, _isin), do: "Stand #{Format.date(as_of)}"
  defp composition_source(true, nil, isin) when isin in [nil, ""], do: "ohne ISIN"
  defp composition_source(true, nil, _isin), do: "keine Angaben"

  # Regions and sectors; each keeps the period.
  defp composition_tabs(assigns) do
    for {tab, label} <- @composition_tabs do
      %{
        label: label,
        path: security_path(assigns.security, assigns.period, tab),
        active: tab == assigns.composition_tab
      }
    end
  end

  # The security page with `period` and the composition `tab`, the defaults left out.
  defp security_path(security, period, tab) do
    {param, _period, _label} = List.keyfind(@periods, period, 1)

    query =
      Enum.filter(
        [
          period: period != :one_year && param,
          composition: tab != :regions && Atom.to_string(tab)
        ],
        &elem(&1, 1)
      )

    ~p"/securities/#{security}?#{query}"
  end

  defp subtitle(security) do
    [security.isin, security.wkn && "WKN #{security.wkn}", security.currency]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

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
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     assign(socket,
       security_id: parse_id(id),
       compositions_available: MarketData.compositions_available?()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(period: period(params["period"]))
    |> assign(composition_tab: composition_tab(params["composition"]))
    |> load()
    |> then(&{:noreply, &1})
  end

  defp period(param), do: Map.get(@period_params, param, :one_year)

  defp composition_tab("sectors"), do: :sectors
  defp composition_tab(_default), do: :regions

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
        |> assign(profile: Securities.profile(scope, security))
        |> assign(exchange_rate: exchange_rate(security))
        |> push_chart(shown.chart)
    end
  end

  defp exchange_rate(%{currency: "EUR"}), do: nil
  defp exchange_rate(%{currency: currency}), do: ExchangeRates.latest(currency)

  # The hook draws the chart once connected; prices and shares × 10⁸.
  defp push_chart(socket, chart) do
    if connected?(socket) do
      push_event(socket, "price-chart", %{
        currency: Format.currency(socket.assigns.security.currency),
        dates: Enum.map(chart.prices, & &1.date),
        prices: Enum.map(chart.prices, & &1.price),
        trades: chart.trades
      })
    else
      socket
    end
  end
end
