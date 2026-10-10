defmodule ZipfelfolioWeb.DividendsLive do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{LocalTime, Portfolios}
  alias ZipfelfolioWeb.Format

  # The first is the default and stays out of the URL.
  @tabs [{"months", :months, "Monate"}, {"received", :received, "Erhalten"}]
  @amounts [{"net", :net, "Netto"}, {"gross", :gross, "Brutto"}]
  @months ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)

  @year_colours ~w(taupe mustard now)
  @recent_years 2

  @impl true
  def render(assigns) do
    assigns = assign(assigns, tabs: @tabs, amounts: @amounts)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:dividends}
    >
      <.header class="flex-wrap">
        Dividenden
        <:subtitle :if={received?(assigns)}>
          Gebucht, zum EZB-Kurs des Zahltags
        </:subtitle>
        <:actions :if={received?(assigns)}>
          <nav id="amount" class="btn-group btn-group-sm align-self-start mt-1" aria-label="Betrag">
            <.link
              :for={{_param, amount, label} <- @amounts}
              patch={dividends_path(@tab, amount)}
              class={["btn btn-outline-secondary", @amount == amount && "active"]}
              aria-current={@amount == amount && "true"}
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

      <.card :if={!@empty and !received?(assigns)}>
        <p class="mb-0">Noch keine Dividenden gebucht.</p>
      </.card>

      <%= if received?(assigns) do %>
        <div class="row g-3 mb-4 app-stats">
          <div class="col-12 col-sm-6 col-lg-3">
            <.stat
              id="this-year"
              label={"#{@today.year} bisher · #{amount_label(@amount)}"}
              value={Format.euros(@dividends.this_year[@amount])}
            >
              <:note class="text-body-secondary">
                {@today.year - 1} gesamt {Format.euros(@dividends.last_year[@amount])}
              </:note>
            </.stat>
          </div>
        </div>

        <nav id="dividend-tabs" aria-label="Ansicht">
          <ul class="nav nav-tabs mb-3">
            <li :for={{_param, tab, label} <- @tabs} class="nav-item">
              <.link
                patch={dividends_path(tab, @amount)}
                class={["nav-link", @tab == tab && "active"]}
                aria-current={@tab == tab && "true"}
              >
                {label}
              </.link>
            </li>
          </ul>
        </nav>

        <.per_month :if={@tab == :months} years={@dividends.years} amount={@amount} today={@today} />
        <.received :if={@tab == :received} received={@dividends.received} />
      <% end %>
    </Layouts.app>
    """
  end

  attr :years, :list, required: true, doc: "see `Dividends.by_year/2`"
  attr :amount, :atom, required: true
  attr :today, Date, required: true

  defp per_month(assigns) do
    colours = assigns.years |> chart_years() |> year_colours()
    assigns = assign(assigns, months: @months, colours: colours, colour: Map.new(colours))

    ~H"""
    <section id="per-month" class="card mb-4" aria-labelledby="per-month-title">
      <div class="card-header d-flex flex-wrap align-items-center justify-content-between gap-2">
        <h2 class="app-card-title mb-0" id="per-month-title">
          Dividenden pro Monat · {amount_label(@amount)}<span class="d-sm-none"> in €</span>
        </h2>
        <span class="small text-body-secondary d-flex gap-3">
          <span :for={{year, colour} <- @colours} class="text-nowrap">
            <span class={"app-swatch app-swatch-#{colour}"}></span> {year}
          </span>
        </span>
      </div>
      <div class="card-body pb-2 pb-sm-3">
        <div role="img" aria-label={"Dividenden pro Monat für #{chart_label(@colours)}"}>
          <div id="dividend-chart" class="app-chart" phx-hook="DividendChart" phx-update="ignore">
            <canvas></canvas>
          </div>
        </div>
      </div>
      <div class="table-responsive border-top">
        <table class="table table-sm align-middle text-nowrap mb-0 app-card-table app-year-table">
          <thead class="small fw-semibold text-body-secondary">
            <tr>
              <th scope="col"><span class="app-swatch invisible"></span> Jahr</th>
              <th :for={month <- @months} scope="col" class="text-end d-none d-md-table-cell">
                {month}
              </th>
              <th scope="col" class="text-end">Gesamt</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={year <- @years} id={"year-#{year.year}"}>
              <% {paid, open} = split_open(year, @amount, @today) %>
              <th scope="row" class="tabular-nums">
                <span class={["app-swatch", swatch(@colour[year.year])]}></span>
                {year.year}
                <span
                  :if={year.year == @today.year}
                  class="small fw-normal text-body-secondary ms-1 d-md-none"
                >
                  {so_far(@today)}
                </span>
              </th>
              <td
                :for={month <- paid}
                class={[
                  "text-end tabular-nums d-none d-md-table-cell",
                  month[@amount] == 0 && "text-body-tertiary"
                ]}
              >
                {month_amount(month[@amount])}
              </td>
              <td
                :if={open > 0}
                colspan={open}
                class="small text-body-tertiary text-center d-none d-md-table-cell"
                aria-label={"#{so_far(@today)}, Rest des Jahres noch offen"}
              >
                {so_far(@today)} · noch offen
              </td>
              <td class="text-end tabular-nums fw-semibold">{Format.euros(year[@amount])}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :received, :list, required: true, doc: "see `Dividends.received/2`"

  defp received(assigns) do
    groups = Enum.chunk_by(assigns.received, & &1.date.year)
    assigns = assign(assigns, groups: Enum.with_index(groups), recent: @recent_years)

    ~H"""
    <section id="received" class="card mb-4" aria-label="Erhaltene Dividenden">
      <div class="table-responsive">
        <table class="table align-middle mb-0 app-card-table app-received">
          <thead class="small fw-semibold text-body-secondary">
            <tr>
              <th scope="col" class="d-none d-sm-table-cell">Zahltag</th>
              <th scope="col">
                <span class="d-flex justify-content-between gap-3">
                  Wertpapier <span class="d-sm-none">Netto</span>
                </span>
              </th>
              <th scope="col" class="text-end d-none d-lg-table-cell">Stück</th>
              <th scope="col" class="text-end d-none d-sm-table-cell">Brutto</th>
              <th scope="col" class="text-end d-none d-md-table-cell">Steuern</th>
              <th scope="col" class="text-end d-none d-md-table-cell">Gebühren</th>
              <th scope="col" class="text-end d-none d-sm-table-cell">Netto</th>
            </tr>
          </thead>
          <tbody
            :for={{[%{date: %{year: year}} | _] = rows, index} <- @groups}
            id={"received-#{year}"}
            class={index >= @recent && "d-none"}
            data-older={index >= @recent}
          >
            <tr class="app-received-year d-sm-none">
              <th scope="rowgroup">
                <span class="d-flex flex-wrap align-items-baseline column-gap-3">
                  <span class="text-nowrap tabular-nums">
                    {year}
                    <span class="small fw-normal text-body-secondary ms-2">
                      brutto {Format.euros(sum(rows, :gross), 2)}
                    </span>
                  </span>
                  <span class="text-nowrap tabular-nums ms-auto">
                    <span class="small fw-normal text-body-secondary">netto</span>
                    {Format.euros(sum(rows, :net), 2)}
                  </span>
                </span>
              </th>
            </tr>
            <tr class="app-received-year d-none d-sm-table-row">
              <th scope="rowgroup">{year}</th>
              <td></td>
              <td class="d-none d-lg-table-cell"></td>
              <td class="text-end text-nowrap tabular-nums">
                {Format.euros(sum(rows, :gross), 2)}
              </td>
              <td class="text-end text-nowrap tabular-nums d-none d-md-table-cell">
                {deduction(sum(rows, :taxes))}
              </td>
              <td class="text-end text-nowrap tabular-nums d-none d-md-table-cell">
                {deduction(sum(rows, :fees))}
              </td>
              <td class="text-end text-nowrap tabular-nums">
                {Format.euros(sum(rows, :net), 2)}
              </td>
            </tr>
            <tr :for={row <- rows} data-date={Date.to_iso8601(row.date)}>
              <td class="text-nowrap tabular-nums d-none d-sm-table-cell">
                <.pay_date date={row.date} />
              </td>
              <td>
                <div class="app-received-phone d-sm-none">
                  <.security_link security={row.security} class="app-received-name" />
                  <span class="text-body-secondary text-nowrap tabular-nums">
                    <.pay_date date={row.date} /> · {shares(row.shares)}
                  </span>
                  <span class="text-end text-nowrap tabular-nums fw-semibold">
                    {Format.euros(row.net, 2)}
                  </span>
                  <div class="small text-body-secondary text-nowrap tabular-nums">
                    <div>Steuern {Format.euros(row.taxes, 2)}</div>
                    <div :if={row.fees != 0}>Gebühren {Format.euros(row.fees, 2)}</div>
                  </div>
                  <span class="small text-body-secondary text-end text-nowrap tabular-nums">
                    brutto {Format.euros(row.gross, 2)}
                  </span>
                </div>
                <div class="d-none d-sm-block">
                  <.security_link security={row.security} />
                  <div class="small text-body-secondary tabular-nums d-lg-none mt-1">
                    <span class="text-nowrap">{shares(row.shares)}</span>
                    <span class="d-md-none">&nbsp;·</span>
                    <span class="text-nowrap d-md-none">Steuern {Format.euros(row.taxes, 2)}</span>
                    <span :if={row.fees != 0} class="d-md-none">&nbsp;·</span>
                    <span :if={row.fees != 0} class="text-nowrap d-md-none">
                      Gebühren {Format.euros(row.fees, 2)}
                    </span>
                  </div>
                </div>
              </td>
              <td class="text-end text-nowrap tabular-nums d-none d-lg-table-cell">
                {share_count(row.shares)}
              </td>
              <td class="text-end text-nowrap tabular-nums d-none d-sm-table-cell">
                {Format.euros(row.gross, 2)}
              </td>
              <td class={[
                "text-end text-nowrap tabular-nums d-none d-md-table-cell",
                muted(row.taxes)
              ]}>
                {deduction(row.taxes)}
              </td>
              <td class={["text-end text-nowrap tabular-nums d-none d-md-table-cell", muted(row.fees)]}>
                {deduction(row.fees)}
              </td>
              <td class="text-end text-nowrap tabular-nums fw-semibold d-none d-sm-table-cell">
                {Format.euros(row.net, 2)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div :if={length(@groups) > @recent} class="card-footer p-0 text-center">
        <button
          id="received-all"
          type="button"
          class="btn btn-link text-decoration-none w-100 app-more"
          phx-click={
            JS.remove_class("d-none", to: "#received tbody[data-older]")
            |> JS.hide(to: "#received .card-footer")
          }
        >
          Ältere Jahre anzeigen ({length(@groups) - @recent})
        </button>
      </div>
    </section>
    """
  end

  defp split_open(%{year: year, months: months}, amount, %Date{year: year} = today) do
    paid = if Enum.at(months, today.month - 1)[amount] > 0, do: today.month, else: today.month - 1
    {Enum.take(months, paid), 12 - paid}
  end

  defp split_open(%{months: months}, _amount, _today), do: {months, 0}

  defp so_far(today), do: "bis #{today.day}. #{Enum.at(@months, today.month - 1)}"

  attr :security, :map, required: true, doc: "nil for a dividend booked without a security"
  attr :class, :string, default: nil

  defp security_link(%{security: nil} = assigns) do
    ~H"""
    <span class={["d-block fw-semibold text-body-secondary", @class]}>Ohne Wertpapier</span>
    """
  end

  defp security_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/securities/#{@security}"}
      class={["d-block fw-semibold text-body text-decoration-none", @class]}
    >
      {security_name(@security)}
    </.link>
    """
  end

  attr :date, Date, required: true

  defp pay_date(assigns) do
    ~H"""
    <time datetime={Date.to_iso8601(@date)}>{Calendar.strftime(@date, "%d.%m.")}</time>
    """
  end

  # Names such as „All-World“ never break at their hyphen.
  defp security_name(security), do: String.replace(security.name, "-", "\u2011")

  defp sum(rows, key), do: Enum.sum_by(rows, &Map.fetch!(&1, key))

  defp swatch(nil), do: "invisible"
  defp swatch(colour), do: "app-swatch-#{colour}"

  defp deduction(0), do: "–"
  defp deduction(cents), do: Format.euros(cents, 2)

  defp muted(0), do: "text-body-tertiary"
  defp muted(_cents), do: nil

  defp received?(%{empty: true}), do: false
  defp received?(%{dividends: dividends}), do: dividends.received != []

  defp amount_label(:net), do: "netto"
  defp amount_label(:gross), do: "brutto"

  defp shares(0), do: "–"
  defp shares(shares), do: "#{Format.shares(shares)}\u00A0Stück"

  defp share_count(0), do: "–"
  defp share_count(shares), do: Format.shares(shares)

  defp month_amount(0), do: "–"
  defp month_amount(cents), do: Format.euros(cents)

  defp chart_years(years), do: years |> Enum.take(length(@year_colours)) |> Enum.reverse()

  defp year_colours(years),
    do: Enum.zip(Enum.map(years, & &1.year), Enum.take(@year_colours, -length(years)))

  defp chart_label(colours), do: Enum.map_join(colours, ", ", &elem(&1, 0))

  defp dividends_path(tab, amount) do
    query =
      Enum.reject(
        [tab: param(@tabs, tab), amount: param(@amounts, amount)],
        fn {_key, value} -> is_nil(value) end
      )

    ~p"/dividends?#{query}"
  end

  defp param([{_param, value, _label} | _rest], value), do: nil

  defp param(choices, value),
    do: Enum.find_value(choices, fn {param, v, _label} -> v == value && param end)

  defp parse(choices, param) do
    [{_param, default, _label} | _rest] = choices
    Enum.find_value(choices, default, fn {p, value, _label} -> p == param && value end)
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    empty = Portfolios.list_portfolios(scope) == [] and Portfolios.list_accounts(scope) == []

    {:ok, assign(socket, page_title: "Dividenden", empty: empty)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(tab: parse(@tabs, params["tab"]), amount: parse(@amounts, params["amount"]))
    |> show_or_load_dividends()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_dividends(socket)}

  defp show_or_load_dividends(%{assigns: %{dividends: _}} = socket), do: push_chart(socket)
  defp show_or_load_dividends(socket), do: load_dividends(socket)

  defp load_dividends(%{assigns: %{empty: true}} = socket), do: socket

  defp load_dividends(socket) do
    today = LocalTime.today()
    dividends = Portfolios.dividends(socket.assigns.current_scope, today)

    socket
    |> assign(today: today, dividends: dividends)
    |> push_chart()
  end

  defp push_chart(%{assigns: %{tab: :months} = assigns} = socket) do
    years = chart_years(assigns.dividends.years)

    if connected?(socket) do
      push_event(socket, "dividend-chart", %{
        years:
          for {year, {_year, colour}} <- Enum.zip(years, year_colours(years)) do
            %{
              year: year.year,
              colour: "--app-year-#{colour}",
              amounts: Enum.map(year.months, & &1[assigns.amount])
            }
          end
      })
    else
      socket
    end
  end

  defp push_chart(socket), do: socket
end
