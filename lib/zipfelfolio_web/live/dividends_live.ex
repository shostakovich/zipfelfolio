defmodule ZipfelfolioWeb.DividendsLive do
  use ZipfelfolioWeb, :live_view

  import ZipfelfolioWeb.DividendComponents

  alias Zipfelfolio.{LocalTime, Portfolios}
  alias ZipfelfolioWeb.Format

  # The first is the default and stays out of the URL.
  @tabs [
    {"calendar", :calendar, "Kalender"},
    {"months", :months, "Monate"},
    {"received", :received, "Erhalten"}
  ]
  @amounts [{"net", :net, "Netto"}, {"gross", :gross, "Brutto"}]
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
        <:subtitle :if={any?(assigns)}>
          {subtitle(@tab)}
        </:subtitle>
        <:actions :if={any?(assigns)}>
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

      <.card :if={!@empty and !any?(assigns)}>
        <p class="mb-0">Noch keine Dividenden gebucht und keine erwartet.</p>
      </.card>

      <%= if any?(assigns) do %>
        <.key_figures dividends={@dividends} amount={@amount} today={@today} />

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

        <.calendar
          :if={@tab == :calendar}
          upcoming={@dividends.upcoming}
          months={@dividends.months}
          amount={@amount}
        />
        <%= if @tab != :calendar and @dividends.received == [] do %>
          <.card>
            <p class="mb-0">Noch keine Dividenden gebucht.</p>
          </.card>
        <% else %>
          <.per_month
            :if={@tab == :months}
            years={@dividends.years}
            amount={@amount}
            today={@today}
          />
          <.received :if={@tab == :received} received={@dividends.received} />
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  attr :dividends, :map, required: true, doc: "see `Portfolios.dividends/2`"
  attr :amount, :atom, required: true
  attr :today, Date, required: true

  defp key_figures(assigns) do
    assigns =
      assign(assigns,
        next: List.first(assigns.dividends.upcoming),
        partly_gross: partly_gross?(assigns.dividends.upcoming, assigns.amount)
      )

    ~H"""
    <div class="card app-kpis mb-4">
      <.stat
        id="next-12-months"
        class="app-kpi"
        label="Nächste 12 Monate"
        value={Format.euros(@dividends.total[@amount])}
      >
        <:prefix :if={@partly_gross}><.partly_gross /></:prefix>
        <:note class="text-body-secondary text-nowrap">
          Ø {Format.euros(div(@dividends.total[@amount], 12))}<span class="d-none d-sm-inline"> pro Monat</span><span class="d-sm-none">/Monat</span>
        </:note>
      </.stat>
      <.stat
        id="this-year"
        class="app-kpi"
        label={"#{@today.year} bisher"}
        value={Format.euros(@dividends.this_year[@amount])}
      >
        <:note class="text-body-secondary text-nowrap">
          {@today.year - 1} gesamt {Format.euros(@dividends.last_year[@amount])}
        </:note>
      </.stat>
      <.stat
        id="yield"
        class="app-kpi"
        label="Rendite auf Wert"
        value={yield(@dividends.total[@amount], @dividends.value)}
      >
        <:prefix :if={@partly_gross}><.partly_gross /></:prefix>
        <:note class="text-body-secondary text-nowrap">
          auf Einstand {yield(@dividends.total[@amount], @dividends.purchase_value)}
        </:note>
      </.stat>
      <.stat
        id="next-dividend"
        class="app-kpi"
        label="Nächste Dividende"
        value={if @next, do: expected(@next, @amount, 0), else: "–"}
      >
        <:prefix :if={@next && @amount == :net && @next.net_is_gross}>
          <span title="Noch keine Dividende gebucht, aus der sich Steuern schätzen ließen">
            brutto
          </span>
        </:prefix>
        <:note :if={@next} class="text-body-secondary app-kpi-name">
          <.pay_date date={@next.pay_date} /> · {security_name(@next.security)}
        </:note>
        <:note :if={!@next} class="text-body-secondary">keine erwartet</:note>
      </.stat>
    </div>
    """
  end

  attr :upcoming, :list, required: true, doc: "see `Dividends.upcoming/4`"
  attr :months, :list, required: true, doc: "see `Dividends.by_coming_month/2`"
  attr :amount, :atom, required: true

  defp calendar(assigns) do
    groups = Enum.chunk_by(assigns.upcoming, &{&1.pay_date.year, &1.pay_date.month})
    assigns = assign(assigns, groups: groups)

    ~H"""
    <div class="row g-4 mb-4">
      <div class="col-lg-7">
        <section id="calendar" aria-label="Kalender">
          <.card :if={@groups == []}>
            <p class="mb-0">
              In den nächsten 12 Monaten ist keine Dividende angekündigt oder zu erwarten.
            </p>
          </.card>
          <div
            :for={[%{pay_date: first} | _] = dividends <- @groups}
            id={"calendar-#{Calendar.strftime(first, "%Y-%m")}"}
            class="mb-4"
          >
            <h2 class="app-calendar-month">
              <span>{Format.month_name(first)} {first.year}</span>
              <span class="app-calendar-total">
                <.partly_gross :if={partly_gross?(dividends, @amount)} class="fw-normal" />
                <span class="tabular-nums">{expected_total(dividends, @amount, 2)}</span>
              </span>
            </h2>
            <ul class="list-group">
              <li
                :for={dividend <- dividends}
                class="list-group-item app-upcoming"
                data-pay-date={Date.to_iso8601(dividend.pay_date)}
                data-kind={dividend.kind}
              >
                <.security_link security={dividend.security} class="app-upcoming-name" />
                <span class="app-upcoming-amount text-nowrap">
                  <span
                    :if={@amount == :net and dividend.net_is_gross}
                    class="small fw-normal text-body-secondary"
                    title="Noch keine Dividende gebucht, aus der sich Steuern schätzen ließen"
                  >
                    brutto
                  </span>
                  <span class="tabular-nums">{expected(dividend, @amount, 2)}</span>
                </span>
                <span class="app-upcoming-meta small text-body-secondary">
                  <span class="app-upcoming-dates">
                    <span class="text-nowrap">Zahltag <.pay_date date={dividend.pay_date} /></span>
                    <span :if={dividend.ex_date} class="text-nowrap">
                      Ex‑Tag <.pay_date date={dividend.ex_date} />
                    </span>
                  </span>
                  <span class="app-upcoming-shares text-nowrap">
                    {Format.shares(dividend.shares)}&nbsp;Stück × {per_share(dividend)}
                  </span>
                </span>
                <.kind_tag kind={dividend.kind} class="app-upcoming-tag" />
              </li>
            </ul>
          </div>
        </section>
      </div>
      <div class="col-lg-5">
        <section
          id="coming-months"
          class="card app-sticky-lg"
          aria-labelledby="coming-months-title"
        >
          <div class="card-header d-flex flex-wrap align-items-center justify-content-between row-gap-1 column-gap-3">
            <h2 class="app-card-title mb-0" id="coming-months-title">
              Nächste 12 Monate · {amount_label(@amount)}<span class="d-sm-none"> in €</span>
              <.partly_gross
                :if={partly_gross?(@upcoming, @amount)}
                class="small fw-normal text-body-secondary"
              />
            </h2>
            <span class="small text-body-secondary d-flex gap-3">
              <span class="text-nowrap"><span class="app-swatch app-swatch-now"></span> angekündigt</span>
              <span class="text-nowrap"><span class="app-swatch app-swatch-forecast"></span> Prognose</span>
            </span>
          </div>
          <div class="card-body pb-2 pb-sm-3">
            <div role="img" aria-label={coming_months_label(@months, @amount)}>
              <div
                id="coming-months-chart"
                class="app-chart app-chart-sm"
                phx-hook="UpcomingDividendChart"
                phx-update="ignore"
              >
                <canvas></canvas>
              </div>
            </div>
          </div>
          <div class="card-footer small text-body-secondary"><.forecast_note /></div>
        </section>
      </div>
    </div>
    """
  end

  attr :class, :any, default: nil

  defp partly_gross(assigns) do
    ~H"""
    <span
      class={@class}
      title="Enthält Dividenden ohne gebuchte Vorjahresdividende, brutto gezählt"
    >
      teils brutto
    </span>
    """
  end

  defp partly_gross?(upcoming, amount),
    do: amount == :net and Enum.any?(upcoming, & &1.net_is_gross)

  attr :years, :list, required: true, doc: "see `Dividends.by_year/2`"
  attr :amount, :atom, required: true
  attr :today, Date, required: true

  defp per_month(assigns) do
    colours = assigns.years |> chart_years() |> year_colours()
    months = Enum.map(1..12, &Format.month_abbr/1)
    assigns = assign(assigns, months: months, colours: colours, colour: Map.new(colours))

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

  defp so_far(today), do: "bis #{today.day}. #{Format.month_abbr(today)}"

  attr :date, Date, required: true

  defp pay_date(assigns) do
    ~H"""
    <time datetime={Date.to_iso8601(@date)}>{Calendar.strftime(@date, "%d.%m.")}</time>
    """
  end

  defp sum(rows, key), do: Enum.sum_by(rows, &Map.fetch!(&1, key))

  defp swatch(nil), do: "invisible"
  defp swatch(colour), do: "app-swatch-#{colour}"

  defp deduction(0), do: "–"
  defp deduction(cents), do: Format.euros(cents, 2)

  defp any?(%{empty: true}), do: false
  defp any?(%{dividends: dividends}), do: dividends.received != [] or dividends.upcoming != []

  defp subtitle(:calendar), do: "Termine von DivvyDiary, Prognose aus 12\u00A0Monaten"
  defp subtitle(_tab), do: "Gebucht, zum EZB\u2011Kurs des Zahltags"

  defp per_share(dividend),
    do: Format.price(dividend.per_share, dividend.currency)

  defp yield(_cents, 0), do: "–"
  defp yield(cents, whole), do: cents |> Format.percent_of(whole) |> Format.percent()

  defp coming_months_label(months, amount) do
    "Erwartete Dividenden " <>
      Enum.map_join(months, ", ", fn month ->
        cents = month.announced[amount] + month.forecast[amount]
        "#{Format.month_name(month.month)} #{month.month.year} #{Format.euros(cents)}"
      end)
  end

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

  defp push_chart(%{assigns: %{tab: :calendar} = assigns} = socket) do
    if connected?(socket) do
      push_event(socket, "upcoming-dividend-chart", %{
        months:
          for month <- assigns.dividends.months do
            %{
              label: Format.month_abbr(month.month),
              year: if(month.month.month == 1, do: month.month.year),
              title: "#{Format.month_name(month.month)} #{month.month.year}",
              announced: month.announced[assigns.amount],
              forecast: month.forecast[assigns.amount]
            }
          end
      })
    else
      socket
    end
  end

  defp push_chart(socket), do: socket
end
