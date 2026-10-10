defmodule ZipfelfolioWeb.TransactionsLive do
  @moduledoc """
  „Buchungen“: every transaction of the user, grouped by month and newest first, filtered by all,
  purchases and sales, earnings or account. A transaction booked in zipfelfolio opens the dialog
  „Buchung bearbeiten“; those from the PP import are read-only. A receipt opens as PDF.
  """
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.Portfolios
  alias Zipfelfolio.Portfolios.Transaction
  alias Zipfelfolio.Valuation
  alias ZipfelfolioWeb.{Format, TransactionDialog}

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

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Buchungen", filters: @filters)}

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      Enum.find_value(@filters, fn {param, filter, _label} ->
        param == params["filter"] && filter
      end)

    {:noreply, socket |> assign(:filter, filter) |> load_transactions()}
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_transactions(socket)}

  defp load_transactions(socket) do
    months = Portfolios.transactions_by_month(socket.assigns.current_scope, socket.assigns.filter)
    assign(socket, :months, months)
  end
end
