defmodule ZipfelfolioWeb.TransactionsLive do
  @moduledoc """
  „Buchungen“: every transaction of the user, grouped by month and newest first, filtered by all,
  purchases and sales, earnings or account. A transaction booked in zipfelfolio opens the dialog
  „Buchung bearbeiten“; those from the PP import are read-only. A receipt opens as PDF.

  Above them the inbox („Eingang“) with the receipts from Paperless and the uploaded ones, see
  `Zipfelfolio.Receipts`; „PDF hochladen“ takes one or several at once.
  """
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{Portfolios, Receipts, Securities, Valuation}
  alias Zipfelfolio.Portfolios.Transaction
  alias ZipfelfolioWeb.{Format, ReceiptComponents, TransactionDialog}

  @filters [
    {nil, nil, "Alle"},
    {"trades", :trades, "Käufe und Verkäufe"},
    {"earnings", :earnings, "Erträge"},
    {"account", :account, "Konto"}
  ]

  @labels %{
    buy: "Kauf",
    sell: "Verkauf",
    inbound_delivery: "Einlieferung",
    outbound_delivery: "Auslieferung",
    security_transfer: "Depotwechsel",
    cash_transfer: "Umbuchung",
    deposit: "Einlage",
    removal: "Entnahme",
    dividend: "Dividende",
    interest: "Zinsen",
    interest_charge: "Zinsbelastung",
    tax: "Steuern",
    tax_refund: "Steuerrückerstattung",
    fee: "Gebühren",
    fee_refund: "Gebührenerstattung"
  }

  @max_uploads 10

  @inflows [:sell, :dividend, :interest, :deposit, :tax_refund, :fee_refund]
  @outflows [:buy, :removal, :interest_charge, :tax, :fee]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:transactions}
    >
      <.header>
        Buchungen
        <:subtitle>Aus Portfolio Performance importierte Buchungen sind nur lesbar.</:subtitle>
        <:actions>
          <form id="receipts-upload" phx-change="upload" phx-submit="upload" class="d-inline">
            <label
              for={@uploads.receipts.ref}
              class="btn btn-sm d-inline-flex align-items-center gap-1"
              role="button"
            >
              <.icon name="upload" class="app-icon-sm" /> PDF hochladen
            </label>
            <.live_file_input upload={@uploads.receipts} class="visually-hidden" />
          </form>
          <button
            id="transactions-book"
            type="button"
            class="btn btn-sm btn-primary d-none d-lg-inline-flex align-items-center gap-1"
            phx-click={TransactionDialog.open()}
          >
            <.icon name="plus" class="app-icon-sm" /> Buchung erfassen
          </button>
        </:actions>
      </.header>

      <div :for={message <- receipt_upload_errors(@uploads)} class="alert alert-danger" role="alert">
        {message}
      </div>

      <ReceiptComponents.inbox
        :if={@inbox != []}
        receipts={@inbox}
        names={@names}
        polled_at={@polled_at}
      />

      <nav id="transaction-filter" aria-label="Filter">
        <ul class="nav nav-underline mb-3 flex-nowrap overflow-x-auto app-filter">
          <li :for={{param, filter, label} <- @filters} class="nav-item">
            <.link
              patch={~p"/transactions?#{filter_query(param)}"}
              class={["nav-link text-nowrap", @filter == filter && "active"]}
              aria-current={@filter == filter && "page"}
            >
              {label}
            </.link>
          </li>
        </ul>
      </nav>

      <.card :if={@months == []}>
        <p id="transactions-empty" class="mb-0">
          {if @filter, do: "Keine Buchungen dieser Art.", else: "Noch keine Buchungen."}
        </p>
      </.card>

      <section
        :for={{month, transactions} <- @months}
        id={"month-#{Date.to_iso8601(month)}"}
        aria-labelledby={"month-#{Date.to_iso8601(month)}-title"}
      >
        <h2
          id={"month-#{Date.to_iso8601(month)}-title"}
          class="small text-uppercase fw-bold text-body-secondary mb-2"
        >
          {month_name(month)}
        </h2>
        <ul class="list-group mb-4">
          <.transaction :for={transaction <- transactions} transaction={transaction} />
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :transaction, Transaction, required: true

  defp transaction(assigns) do
    transaction = assigns.transaction

    assigns =
      assign(assigns,
        title: title(transaction),
        editable: Transaction.editable?(transaction),
        tone: type_tone(transaction.type)
      )

    ~H"""
    <li
      id={"transaction-#{@transaction.id}"}
      class={[
        "list-group-item d-flex align-items-center gap-2 gap-sm-3",
        @editable && "list-group-item-action"
      ]}
    >
      <span class={[
        "app-avatar rounded-circle d-flex align-items-center justify-content-center",
        "bg-#{@tone}-subtle text-#{@tone}-emphasis"
      ]}>
        <.icon name={type_icon(@transaction.type)} />
      </span>
      <span class="me-auto app-tx-text">
        <button
          :if={@editable}
          type="button"
          class="app-tx-edit stretched-link d-block fw-semibold text-start"
          phx-click={TransactionDialog.edit(@transaction.id)}
        >
          {@title}<span class="visually-hidden"> bearbeiten</span>
        </button>
        <span :if={!@editable} class="d-block fw-semibold">{@title}</span>
        <span class="small text-body-secondary">{details(@transaction)}</span>
      </span>
      <span class="d-flex flex-column flex-sm-row align-items-end align-items-sm-center gap-1 gap-sm-3">
        <span class={[
          "fw-bold tabular-nums text-nowrap order-sm-last",
          amount_tone(@transaction.type)
        ]}>
          {signed_amount(@transaction)}
        </span>
        <a
          :if={@transaction.receipt}
          href={~p"/receipts/#{@transaction.receipt_id}"}
          target="_blank"
          rel="noopener"
          class="badge text-bg-light d-inline-flex align-items-center gap-1 text-decoration-none app-tx-receipt"
          aria-label={"Beleg #{@transaction.receipt.filename} öffnen"}
        >
          <.icon name="file" class="app-icon-sm" />PDF
        </a>
      </span>
      <.icon
        :if={@editable}
        name="chevron"
        class="app-icon-sm text-body-tertiary flex-shrink-0 d-none d-sm-block"
      />
    </li>
    """
  end

  defp title(%Transaction{security: %{name: name}} = transaction),
    do: "#{@labels[transaction.type]} · #{name}"

  defp title(transaction), do: @labels[transaction.type]

  defp type_icon(type) when type in [:dividend, :interest], do: "coins"

  defp type_icon(type)
       when type in [:buy, :sell, :inbound_delivery, :outbound_delivery, :security_transfer],
       do: "layers"

  defp type_icon(_type), do: "wallet"

  defp type_tone(type) when type in [:dividend, :interest], do: "success"

  defp type_tone(type)
       when type in [:buy, :sell, :inbound_delivery, :outbound_delivery, :security_transfer],
       do: "primary"

  defp type_tone(_type), do: "secondary"

  defp amount_tone(type) when type in @inflows, do: "text-success"
  defp amount_tone(_type), do: nil

  # From the user's money's view: what comes into an account counts plus, what leaves it minus;
  # deliveries and transfers move what is there already.
  defp signed_amount(%Transaction{type: type, amount: amount, currency: currency}) do
    sign =
      cond do
        type in @inflows -> "+"
        type in @outflows -> "−"
        true -> ""
      end

    sign <> Format.amount(amount) <> "\u00A0" <> Format.currency(currency)
  end

  defp details(transaction) do
    [
      Calendar.strftime(transaction.date_time, "%d.%m.%Y"),
      where(transaction),
      shares(transaction),
      gross(transaction),
      unit(transaction, :fee, "Gebühren"),
      unit(transaction, :tax, "Steuern")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp where(%Transaction{type: :security_transfer} = transaction),
    do: "#{name(transaction.portfolio)} → #{name(transaction.other_portfolio)}"

  defp where(%Transaction{type: :cash_transfer} = transaction),
    do: "#{name(transaction.account)} → #{name(transaction.other_account)}"

  defp where(transaction) do
    case Enum.reject([transaction.portfolio, transaction.account], &is_nil/1) do
      [] -> nil
      sides -> Enum.map_join(sides, " · ", & &1.name)
    end
  end

  defp name(nil), do: "–"
  defp name(record), do: record.name

  defp shares(%Transaction{shares: shares}) when shares in [nil, 0], do: nil

  defp shares(%Transaction{type: type} = transaction) when type in [:buy, :sell] do
    price = Valuation.price_per_share(transaction, transaction.currency)
    "#{Format.shares(transaction.shares)} Stück à #{Format.price(price, transaction.currency)}"
  end

  defp shares(transaction), do: "#{Format.shares(transaction.shares)} Stück"

  defp gross(%Transaction{type: :dividend, amount: amount} = transaction) do
    case Valuation.gross_value(transaction, transaction.currency) do
      ^amount -> nil
      gross -> "brutto #{money(gross, transaction)}"
    end
  end

  defp gross(_transaction), do: nil

  defp unit(transaction, type, label) do
    case unit_cents(transaction, type) do
      0 -> nil
      cents -> "#{label} #{money(cents, transaction)}"
    end
  end

  defp unit_cents(transaction, type),
    do: transaction.units |> Enum.filter(&(&1.type == type)) |> Enum.sum_by(& &1.amount)

  defp money(cents, transaction),
    do: Format.amount(cents) <> "\u00A0" <> Format.currency(transaction.currency)

  defp month_name(month), do: "#{Format.month_name(month)} #{month.year}"

  defp filter_query(nil), do: []
  defp filter_query(param), do: [filter: param]

  defp receipt_upload_errors(uploads) do
    upload = uploads.receipts
    entry_errors = Enum.flat_map(upload.entries, &upload_errors(upload, &1))
    (upload_errors(upload) ++ entry_errors) |> Enum.uniq() |> Enum.map(&upload_error/1)
  end

  defp upload_error(:too_large), do: "Eine Datei ist zu groß, höchstens 20 MB."
  defp upload_error(:not_accepted), do: "Bitte nur PDF-Dateien wählen."
  defp upload_error(:too_many_files), do: "Bitte höchstens #{@max_uploads} Dateien auf einmal."
  defp upload_error(_error), do: "Eine Datei ließ sich nicht hochladen."

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Buchungen", filters: @filters, uploaded: %{})
     |> load_inbox()
     |> allow_upload(:receipts,
       accept: ~w(.pdf),
       max_entries: @max_uploads,
       max_file_size: 20_000_000,
       auto_upload: true,
       progress: &uploaded/3
     )}
  end

  # Each PDF goes into the inbox once it is up; once all of them are, one flash sums them up.
  defp uploaded(:receipts, entry, socket) do
    if entry.done? do
      scope = socket.assigns.current_scope

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Receipts.upload(scope, path, entry.client_name)}
        end)

      socket = update(socket, :uploaded, &Map.put(&1, entry.ref, {result, entry.client_name}))
      {:noreply, socket |> maybe_upload_flash() |> load_inbox()}
    else
      {:noreply, socket}
    end
  end

  # Consumed entries leave the upload only after the callback.
  defp maybe_upload_flash(socket) do
    %{uploaded: uploaded, uploads: %{receipts: upload}} = socket.assigns

    if Enum.all?(upload.entries, &(Map.has_key?(uploaded, &1.ref) or not &1.valid?)) do
      results = Map.values(uploaded)

      kind =
        if Enum.any?(results, &match?({{:error, _reason}, _name}, &1)), do: :error, else: :info

      message =
        results
        |> Enum.group_by(fn {result, _name} -> result end, fn {_result, name} -> name end)
        |> Enum.sort()
        |> Enum.map_join(" ", fn {result, names} -> upload_message(result, names) end)

      socket |> assign(:uploaded, %{}) |> put_flash(kind, message)
    else
      socket
    end
  end

  defp upload_message({:ok, :added}, [name]), do: "#{name} liegt im Eingang."
  defp upload_message({:ok, :added}, names), do: "#{length(names)} Belege liegen im Eingang."
  defp upload_message({:ok, :in_inbox}, [name]), do: "#{name} liegt schon im Eingang."

  defp upload_message({:ok, :in_inbox}, names),
    do: "#{length(names)} Belege liegen schon im Eingang."

  defp upload_message({:ok, :booked}, [name]), do: "#{name} ist schon gebucht."
  defp upload_message({:ok, :booked}, names), do: "#{length(names)} Belege sind schon gebucht."
  defp upload_message({:error, :not_pdf}, [name]), do: "#{name} ist keine PDF-Datei."

  defp upload_message({:error, :not_pdf}, names),
    do: "#{length(names)} Dateien sind keine PDF-Dateien."

  @impl true
  # A rejected file is said once and dropped, so it neither sticks nor counts to the limit.
  def handle_event("upload", _params, socket) do
    upload = socket.assigns.uploads.receipts
    rejected = Enum.reject(upload.entries, & &1.valid?) ++ Enum.drop(upload.entries, @max_uploads)

    case receipt_upload_errors(socket.assigns.uploads) do
      [] ->
        {:noreply, socket}

      errors ->
        {:noreply,
         rejected
         |> Enum.uniq_by(& &1.ref)
         |> Enum.reduce(socket, &cancel_upload(&2, :receipts, &1.ref))
         |> put_flash(:error, Enum.join(errors, " "))}
    end
  end

  def handle_event("discard", %{"id" => id}, socket) do
    message =
      case Receipts.discard(socket.assigns.current_scope, id) do
        :ok -> "Beleg verworfen."
        {:error, :gone} -> "Dieser Beleg liegt nicht mehr im Eingang."
      end

    {:noreply, socket |> put_flash(:info, message) |> load_inbox()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      Enum.find_value(@filters, fn {param, filter, _label} ->
        param == params["filter"] && filter
      end)

    {:noreply, socket |> assign(:filter, filter) |> load_transactions()}
  end

  @impl true
  def handle_info(:market_data_updated, socket),
    do: {:noreply, socket |> load_transactions() |> load_inbox()}

  def handle_info(:receipts_updated, socket), do: {:noreply, load_inbox(socket)}

  defp load_inbox(socket) do
    scope = socket.assigns.current_scope
    names = Map.new(Securities.list_securities(scope), &{&1.isin, &1.name})

    assign(socket,
      inbox: Receipts.list_inbox(scope),
      names: names,
      polled_at: Receipts.paperless_polled_at(scope)
    )
  end

  defp load_transactions(socket) do
    months = Portfolios.transactions_by_month(socket.assigns.current_scope, socket.assigns.filter)
    assign(socket, :months, months)
  end
end
