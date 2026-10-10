defmodule ZipfelfolioWeb.SecuritiesLive do
  use ZipfelfolioWeb, :live_view

  import Ecto.Changeset, only: [change: 1]

  alias Zipfelfolio.{ExchangeRates, MarketData, Securities, Users}
  alias ZipfelfolioWeb.Format

  @feeds [{"Yahoo", "yahoo"}, {"Manuell", "manual"}]

  # What a new security from Yahoo starts with: the MSCI ACWI, in euros on Xetra.
  @symbol "IUSQ.DE"

  @unknown_benchmark "Dieses Wertpapier gibt es nicht mehr, die Benchmark bleibt."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:settings}
    >
      <.header>
        Wertpapiere
        <:actions>
          <.link navigate={~p"/users/settings"} class="btn btn-sm btn-outline-secondary">
            Einstellungen
          </.link>
        </:actions>
      </.header>

      <p class="text-body-secondary">
        Kurse kommen von Yahoo, täglich um 18:00 und beim Öffnen dieser Seite. Am selben Tag gilt ein
        Kurs aus Portfolio Performance vor einem manuellen, ein manueller vor einem von Yahoo.
      </p>

      <.card title="Benchmark" id="benchmark">
        <p>
          Übersicht und Performance vergleichen deine Depots mit diesem Wertpapier, wenn du dort „Benchmark“ einschaltest.
        </p>
        <div class="row g-4">
          <div class="col-lg-6">
            <.form
              for={@benchmark_form}
              id="benchmark-form"
              phx-change="save_benchmark"
              phx-submit="save_benchmark"
            >
              <.input
                field={@benchmark_form[:benchmark_id]}
                type="select"
                label="Wertpapier"
                options={benchmark_options(@active, @benchmark)}
                wrapper_class=""
              />
            </.form>
            <p class="small text-body-secondary mt-2 mb-0">Gilt sofort, ohne Speichern.</p>
          </div>
          <div class="col-lg-6">
            <.form for={@symbol_form} id="yahoo-security" phx-submit="create_security">
              <label class="form-label" for={@symbol_form[:symbol].id}>
                Oder neu per Yahoo-Symbol anlegen
              </label>
              <div class="input-group">
                <input
                  type="text"
                  name={@symbol_form[:symbol].name}
                  id={@symbol_form[:symbol].id}
                  value={@symbol_form[:symbol].value}
                  class={["form-control", symbol_errors(@symbol_form) != [] && "is-invalid"]}
                  spellcheck="false"
                  autocapitalize="characters"
                  aria-describedby="yahoo-security-help"
                />
                <.button variant="outline-primary" phx-disable-with="Wird abgerufen …">
                  Anlegen
                </.button>
              </div>
              <.error :for={message <- symbol_errors(@symbol_form)}>{message}</.error>
            </.form>
            <p id="yahoo-security-help" class="small text-body-secondary mt-2 mb-0">
              Wird deine Benchmark. Name, Währung und Kurse kommen von Yahoo; ein vorhandenes
              Symbol wird übernommen statt doppelt angelegt.
            </p>
          </div>
        </div>
      </.card>

      <.card title="Wechselkurse" id="exchange-rates">
        <p class="mb-0">
          <%= if @rates_until do %>
            EZB-Referenzkurse bis {Format.date(@rates_until)}, täglich um 18:00 aktualisiert.
          <% else %>
            Noch keine Wechselkurse; sie kommen mit dem nächsten Abruf um 18:00.
          <% end %>
        </p>
        <p :if={@last_run && @last_run.error} class="text-danger small mt-2 mb-0">
          {@last_run.error}
        </p>
      </.card>

      <section class="card mb-3" aria-label="Aktive Wertpapiere">
        <p :if={@active == []} class="card-body mb-0">
          Noch keine Wertpapiere. Sie kommen mit dem <.link navigate={~p"/settings/import"}>Import aus Portfolio Performance</.link>.
        </p>
        <ul :if={@active != []} class="list-group list-group-flush">
          <.security
            :for={security <- @active}
            security={security}
            benchmark={@benchmark == security}
            feed_form={@feed_forms[security.id]}
            price_form={@price_forms[security.id]}
            manual_prices={@manual_prices[security.id]}
          />
        </ul>
      </section>

      <details
        :if={@retired != []}
        id="retired"
        class="card mb-3"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <summary class="card-body">Ausgemustert ({length(@retired)})</summary>
        <ul class="list-group list-group-flush">
          <.security
            :for={security <- @retired}
            security={security}
            benchmark={@benchmark == security}
            feed_form={@feed_forms[security.id]}
            price_form={@price_forms[security.id]}
            manual_prices={@manual_prices[security.id]}
          />
        </ul>
      </details>
    </Layouts.app>
    """
  end

  attr :security, :map, required: true
  attr :benchmark, :boolean, default: false
  attr :feed_form, Phoenix.HTML.Form, required: true
  attr :price_form, Phoenix.HTML.Form, required: true
  attr :manual_prices, :list, required: true

  defp security(assigns) do
    ~H"""
    <li class="list-group-item" id={"security-#{@security.id}"}>
      <div class="d-flex gap-3">
        <div class="me-auto">
          <span class="d-block fw-semibold">
            {@security.name}
            <span :if={@benchmark} class="badge ms-1 app-benchmark-badge">
              <span class="app-benchmark-key" aria-hidden="true"></span>Benchmark
            </span>
          </span>
          <span class="small text-body-secondary">
            {[@security.isin, @security.currency] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")}
          </span>
        </div>
        <div class="text-end text-nowrap">
          <span class="d-block">{Format.price(@security.latest_close, @security.currency)}</span>
          <span class="small text-body-secondary">{quote_time(@security)}</span>
        </div>
      </div>

      <p :if={@security.fetch_error} class="text-danger small my-2">{@security.fetch_error}</p>
      <p :if={!@security.fetch_error && @security.fetched_at} class="text-body-secondary small my-2">
        Zuletzt abgerufen {Format.datetime(@security.fetched_at)}
      </p>

      <.form for={@feed_form} id={"feed-#{@security.id}"} phx-submit="save_feed" class="row g-2 mt-1">
        <input type="hidden" name="security_id" value={@security.id} />
        <div class="col-sm-4">
          <.input
            field={@feed_form[:quote_feed]}
            type="select"
            label="Kursquelle"
            options={feeds()}
            wrapper_class=""
          />
        </div>
        <div class="col-sm-5">
          <.input
            field={@feed_form[:symbol]}
            label="Yahoo-Symbol"
            placeholder="z. B. VGWL.DE"
            spellcheck="false"
            wrapper_class=""
          />
        </div>
        <div class="col-sm-3 d-flex align-items-end">
          <.button variant="outline-primary" class="w-100">Speichern</.button>
        </div>
      </.form>

      <details
        id={"manual-prices-#{@security.id}"}
        class="mt-3"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <summary class="small">Manuelle Kurse ({length(@manual_prices)})</summary>
        <.form
          for={@price_form}
          id={"manual-price-#{@security.id}"}
          phx-submit="add_price"
          class="row g-2 mt-1"
        >
          <input type="hidden" name="security_id" value={@security.id} />
          <div class="col-sm-4">
            <.input field={@price_form[:date]} type="date" label="Tag" required wrapper_class="" />
          </div>
          <div class="col-sm-5">
            <.input
              field={@price_form[:close]}
              label="Kurs"
              inputmode="decimal"
              required
              wrapper_class=""
            />
          </div>
          <div class="col-sm-3 d-flex align-items-end">
            <.button variant="outline-primary" class="w-100">Eintragen</.button>
          </div>
        </.form>
        <ul :if={@manual_prices != []} class="list-unstyled mt-2 mb-0">
          <li :for={price <- @manual_prices} class="d-flex align-items-center gap-2 py-1">
            <span class="me-auto">{Format.date(price.date)}</span>
            <span>{Format.price(price.close, @security.currency)}</span>
            <.button
              type="button"
              variant="link"
              size="sm"
              phx-click="delete_price"
              phx-value-security_id={@security.id}
              phx-value-price-id={price.id}
            >
              Löschen
            </.button>
          </li>
        </ul>
      </details>
    </li>
    """
  end

  defp feeds, do: @feeds

  # The active securities, and the benchmark even once it is retired.
  defp benchmark_options(active, benchmark) do
    securities = if benchmark in [nil | active], do: active, else: active ++ [benchmark]
    [{"Keine Benchmark", ""} | Enum.map(securities, &{&1.name, &1.id})]
  end

  defp quote_time(%{latest_at: %DateTime{} = at}), do: "Stand " <> Format.datetime(at)
  defp quote_time(%{latest_date: %Date{} = date}), do: "Stand " <> Format.date(date)
  defp quote_time(_security), do: "noch kein Kurs"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Wertpapiere")
     |> assign(:symbol_form, symbol_form())
     |> load()}
  end

  defp symbol_errors(form), do: Enum.map(form[:symbol].errors, &translate_error/1)

  defp symbol_form(changeset \\ Securities.change_yahoo_symbol(%{"symbol" => @symbol})),
    do: to_form(changeset, as: :yahoo)

  # Loads the data and resets every form.
  defp load(socket) do
    socket
    |> assign(feed_forms: %{}, price_forms: %{})
    |> reload()
  end

  # Loads the data and keeps the forms, so an update in the background spares what is typed.
  defp reload(socket) do
    scope = socket.assigns.current_scope
    {retired, active} = scope |> Securities.list_securities() |> Enum.split_with(& &1.retired)
    securities = active ++ retired

    benchmark = Enum.find(securities, &(&1.id == scope.user.benchmark_id))

    socket
    |> assign(active: active, retired: retired, securities: Map.new(securities, &{&1.id, &1}))
    |> assign(
      benchmark: benchmark,
      benchmark_form: to_form(%{"benchmark_id" => benchmark && benchmark.id}, as: :benchmark)
    )
    |> update(:feed_forms, &add_missing(&1, securities, fn s -> feed_form(s, change(s)) end))
    |> update(
      :price_forms,
      &add_missing(&1, securities, fn s -> price_form(s, Securities.change_manual_price(s)) end)
    )
    |> assign(
      :manual_prices,
      Map.new(securities, &{&1.id, Securities.list_manual_prices(scope, &1)})
    )
    |> assign(rates_until: ExchangeRates.last_date(), last_run: MarketData.last_run())
  end

  defp add_missing(forms, securities, new_form),
    do: Map.new(securities, &{&1.id, Map.get_lazy(forms, &1.id, fn -> new_form.(&1) end)})

  # Field ids carry the security, as every security has its own forms.
  defp feed_form(security, changeset),
    do: to_form(changeset, as: :feed, id: "feed-#{security.id}")

  defp price_form(security, changeset),
    do: to_form(changeset, as: :price, id: "price-#{security.id}")

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, reload(socket)}

  @impl true
  def handle_event("save_feed", %{"security_id" => id, "feed" => params}, socket) do
    security = security!(socket, id)

    case Securities.update_quote_feed(socket.assigns.current_scope, security, params) do
      {:ok, updated} ->
        if new_yahoo_source?(security, updated),
          do: MarketData.fetch_in_background(updated)

        {:noreply, socket |> load() |> put_flash(:info, "Kursquelle gespeichert.")}

      {:error, changeset} ->
        {:noreply, put_form(socket, :feed_forms, security, feed_form(security, changeset))}
    end
  end

  def handle_event("save_benchmark", %{"benchmark" => %{"benchmark_id" => id}}, socket) do
    with {:ok, security_id} <- benchmark_id(id),
         {:ok, socket} <- pick_benchmark(socket, security_id) do
      message = if security_id, do: "Benchmark gespeichert.", else: "Keine Benchmark mehr."
      {:noreply, socket |> reload() |> put_flash(:info, message)}
    else
      :error -> {:noreply, socket |> reload() |> put_flash(:error, @unknown_benchmark)}
    end
  end

  def handle_event("create_security", %{"yahoo" => params}, socket) do
    with {:ok, security} <- MarketData.create_yahoo_security(socket.assigns.current_scope, params),
         {:ok, socket} <- pick_benchmark(socket, security.id) do
      socket
      |> assign(:symbol_form, symbol_form())
      |> load()
      |> put_flash(:info, "#{security.name} ist deine Benchmark.")
      |> then(&{:noreply, &1})
    else
      {:error, changeset} ->
        {:noreply, assign(socket, :symbol_form, symbol_form(changeset))}

      :error ->
        {:noreply, socket |> load() |> put_flash(:error, @unknown_benchmark)}
    end
  end

  def handle_event("add_price", %{"security_id" => id, "price" => params}, socket) do
    security = security!(socket, id)

    case Securities.add_manual_price(socket.assigns.current_scope, security, params) do
      {:ok, _price} ->
        MarketData.broadcast()
        {:noreply, socket |> load() |> put_flash(:info, "Kurs eingetragen.")}

      {:error, changeset} ->
        {:noreply, put_form(socket, :price_forms, security, price_form(security, changeset))}
    end
  end

  def handle_event("delete_price", %{"security_id" => id, "price-id" => price_id}, socket) do
    security = security!(socket, id)

    with {:ok, price} <-
           Securities.delete_manual_price(socket.assigns.current_scope, security, price_id) do
      MarketData.broadcast()

      # Yahoo fills the day again; the daily run only fetches from the last stored day on.
      if security.quote_feed == :yahoo, do: MarketData.fetch_in_background(security, price.date)
    end

    {:noreply, socket |> load() |> put_flash(:info, "Kurs gelöscht.")}
  end

  defp benchmark_id(""), do: {:ok, nil}

  defp benchmark_id(id) do
    case parse_id(id) do
      nil -> :error
      security_id -> {:ok, security_id}
    end
  end

  defp pick_benchmark(socket, security_id) do
    case Users.update_benchmark(socket.assigns.current_scope, security_id) do
      {:ok, user} ->
        {:ok, assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})}

      {:error, _changeset} ->
        :error
    end
  end

  defp security!(socket, id), do: Map.fetch!(socket.assigns.securities, String.to_integer(id))

  defp new_yahoo_source?(before, updated),
    do:
      updated.quote_feed == :yahoo and
        {before.quote_feed, before.symbol} != {:yahoo, updated.symbol}

  defp put_form(socket, key, security, form),
    do: update(socket, key, &Map.put(&1, security.id, form))
end
