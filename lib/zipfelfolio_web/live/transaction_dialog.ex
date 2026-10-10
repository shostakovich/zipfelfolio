defmodule ZipfelfolioWeb.TransactionDialog do
  @moduledoc """
  The dialog „Buchung erfassen“ on every signed-in page, opened by `open/0` from the sidebar and
  on the phone: a purchase, sale, dividend, deposit or removal with an optional PDF receipt. The
  amount follows the other fields until the user overwrites it. Once booked, every page loads its
  figures again, and the page shows what was booked: components cannot show a flash themselves,
  so `on_mount/4` lets the page do it.
  """
  use ZipfelfolioWeb, :live_component

  alias Zipfelfolio.{LocalTime, MarketData, Portfolios}
  alias ZipfelfolioWeb.Format

  @id "transaction-dialog"
  @kinds [
    purchase: "Kauf",
    sale: "Verkauf",
    dividend: "Dividende",
    deposit: "Einlage",
    removal: "Entnahme"
  ]

  @doc "The id the layout renders the dialog with."
  def id, do: @id

  @doc "Opens the dialog."
  def open, do: JS.push("open", target: "##{@id}")

  @doc "Shows the dialog's message on the page that renders it."
  def on_mount(:default, _params, _session, socket),
    do: {:cont, Phoenix.LiveView.attach_hook(socket, :transaction_dialog, :handle_info, &flash/2)}

  defp flash({__MODULE__, :booked, message}, socket),
    do: {:halt, put_flash(socket, :info, message)}

  defp flash(_message, socket), do: {:cont, socket}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> allow_upload(:receipt, accept: ~w(.pdf), max_entries: 1, max_file_size: 20_000_000)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div :if={@open}>
        <div
          id="transaction-modal"
          class="modal d-block"
          role="dialog"
          aria-modal="true"
          aria-labelledby="transaction-title"
          phx-window-keydown="close"
          phx-key="Escape"
          phx-target={@myself}
        >
          <div class="modal-dialog modal-lg modal-fullscreen-sm-down modal-dialog-scrollable">
            <.form
              for={@form}
              id="transaction-form"
              class="modal-content"
              phx-change="validate"
              phx-submit="book"
              phx-target={@myself}
              phx-click-away="close"
              phx-mounted={JS.focus_first(to: "#transaction-form .modal-body")}
            >
              <div class="modal-header">
                <h2 class="modal-title h4" id="transaction-title">Buchung erfassen</h2>
                <button
                  type="button"
                  class="btn-close"
                  aria-label="Schließen"
                  phx-click="close"
                  phx-target={@myself}
                ></button>
              </div>
              <div class="modal-body">
                <.kinds field={@form[:kind]} />
                <div class="row g-3">
                  <div :if={@kind != :deposit and @kind != :removal} class="col-sm-6">
                    <.input
                      field={@form[:portfolio_id]}
                      type="select"
                      label="Depot"
                      options={Enum.map(@choices.portfolios, &{&1.name, &1.id})}
                      prompt={if @kind == :dividend, do: "Ohne Depot"}
                      wrapper_class={nil}
                    />
                  </div>
                  <div class="col-sm-6">
                    <.input
                      field={@form[:date]}
                      type="date"
                      label="Datum"
                      max={Date.to_iso8601(@today)}
                      wrapper_class={nil}
                    />
                  </div>
                  <div :if={@kind != :deposit and @kind != :removal} class="col-12">
                    <.input
                      field={@form[:security_id]}
                      type="select"
                      label="Wertpapier"
                      options={Enum.map(@choices.securities, &{security_label(&1), &1.id})}
                      prompt="Wertpapier wählen"
                      wrapper_class={nil}
                    />
                  </div>
                  <div :if={@kind != :deposit and @kind != :removal} class="col-6 col-sm-4">
                    <.number field={@form[:shares]} label="Stück" />
                  </div>
                  <div :if={@kind in [:purchase, :sale]} class="col-6 col-sm-4">
                    <.number field={@form[:price]} label="Kurs" euros />
                  </div>
                  <div :if={@kind == :dividend} class="col-6 col-sm-4">
                    <.number field={@form[:gross]} label="Brutto" euros />
                  </div>
                  <div :if={@kind != :deposit and @kind != :removal} class="col-6 col-sm-4">
                    <.number field={@form[:fees]} label="Gebühren" euros />
                  </div>
                  <div :if={@kind != :deposit and @kind != :removal} class="col-6 col-sm-4">
                    <.number field={@form[:taxes]} label="Steuern" euros />
                  </div>
                  <div class="col-sm-8">
                    <.input
                      field={@form[:account_id]}
                      type="select"
                      label="Konto"
                      options={Enum.map(@choices.accounts, &{&1.name, &1.id})}
                      prompt={account_prompt(@kind)}
                      wrapper_class={nil}
                    />
                  </div>
                  <div class="col-12">
                    <.amount form={@form} kind={@kind} />
                  </div>
                  <div :if={@kind == :dividend} class="col-12">
                    <.input
                      field={@form[:remove_at_once]}
                      type="checkbox"
                      label="Gleich entnehmen"
                      aria-describedby="transaction-remove-hint"
                      wrapper_class="mb-0"
                    />
                    <div id="transaction-remove-hint" class="form-text">
                      Bucht den Nettobetrag am selben Tag vom Konto ab.
                    </div>
                  </div>
                  <div class="col-12">
                    <label class="form-label" for={@uploads.receipt.ref}>
                      Beleg <span class="text-body-secondary">(optional)</span>
                    </label>
                    <.live_file_input
                      upload={@uploads.receipt}
                      class={["form-control", receipt_errors(@uploads, @form) != [] && "is-invalid"]}
                    />
                    <.error :for={message <- receipt_errors(@uploads, @form)}>{message}</.error>
                  </div>
                </div>
              </div>
              <div class="modal-footer">
                <button type="button" class="btn" phx-click="close" phx-target={@myself}>
                  Abbrechen
                </button>
                <.button phx-disable-with="Wird gebucht …">Buchen</.button>
              </div>
            </.form>
          </div>
        </div>
        <div class="modal-backdrop show"></div>
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp kinds(assigns) do
    assigns = assign(assigns, :kinds, @kinds)

    ~H"""
    <div class="btn-group btn-group-sm w-100 mb-3 flex-wrap" role="group" aria-label="Art">
      <%= for {kind, label} <- @kinds do %>
        <input
          type="radio"
          class="btn-check"
          name={@field.name}
          id={"#{@field.id}-#{kind}"}
          value={kind}
          checked={to_string(@field.value) == to_string(kind)}
        />
        <label class="btn btn-outline-secondary flex-fill" for={"#{@field.id}-#{kind}"}>
          {label}
        </label>
      <% end %>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :euros, :boolean, default: false

  # A number as typed, in German notation, with its error once the field was used.
  defp number(assigns) do
    assigns = assign(assigns, :errors, field_errors(assigns.field))

    ~H"""
    <label class="form-label" for={@field.id}>{@label}</label>
    <div class={[@euros && "input-group", @errors != [] && "has-validation"]}>
      <input
        type="text"
        inputmode="decimal"
        autocomplete="off"
        id={@field.id}
        name={@field.name}
        value={typed(@field)}
        class={["form-control tabular-nums", @errors != [] && "is-invalid"]}
      />
      <span :if={@euros} class="input-group-text">€</span>
      <.error :for={message <- @errors}>{message}</.error>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :kind, :atom, required: true

  # The amount computed or overwritten, and a warning when it differs from the other fields.
  defp amount(assigns) do
    form = assigns.form
    field = form[:amount]

    assigns =
      assign(assigns,
        field: field,
        errors: field_errors(field),
        value: amount_value(form),
        expected: form[:expected_amount].value
      )

    ~H"""
    <div class="alert alert-light mb-0">
      <label class="form-label" for={@field.id}>
        Betrag
        <span class="text-body-secondary">({amount_hint(@kind, @form[:account_id].value)})</span>
      </label>
      <input type="hidden" name={@form[:amount_set].name} value={to_string(@form[:amount_set].value)} />
      <div class={["input-group", @errors != [] && "has-validation"]}>
        <input
          type="text"
          inputmode="decimal"
          autocomplete="off"
          id={@field.id}
          name={@field.name}
          value={@value}
          class={["form-control fw-bold tabular-nums", @errors != [] && "is-invalid"]}
          aria-describedby={@expected && "transaction-expected"}
        />
        <span class="input-group-text">€</span>
        <.error :for={message <- @errors}>{message}</.error>
      </div>
      <div :if={@expected} id="transaction-expected" class="form-text text-warning-emphasis">
        {expected_text(@kind, @form)} ergibt {Format.amount(cents(@expected))}&nbsp;€.
      </div>
    </div>
    """
  end

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &translate_error/1),
      else: []
  end

  # What the user typed, not the cast decimal, which would read as thousands in German.
  defp typed(%Phoenix.HTML.FormField{form: form, field: field}),
    do: Map.get(form.params, Atom.to_string(field))

  defp amount_value(form) do
    case {form[:amount_set].value, form[:amount].value} do
      {true, _amount} -> typed(form[:amount])
      {_computed, %Decimal{} = amount} -> Format.amount(cents(amount))
      {_computed, _none} -> nil
    end
  end

  defp cents(decimal), do: decimal |> Decimal.mult(100) |> Decimal.to_integer()

  defp security_label(%{isin: isin} = security) when isin in [nil, ""], do: security.name
  defp security_label(security), do: "#{security.name} (#{security.isin})"

  defp account_prompt(:purchase), do: "Ohne Konto (Einlieferung)"
  defp account_prompt(:sale), do: "Ohne Konto (Auslieferung)"
  defp account_prompt(_kind), do: "Konto wählen"

  defp amount_hint(kind, account_id) when kind in [:purchase, :sale] and account_id in [nil, ""],
    do: "ohne Konto"

  defp amount_hint(kind, _account_id) when kind in [:purchase, :removal],
    do: "wird vom Konto abgebucht"

  defp amount_hint(:dividend, _account_id), do: "netto, wird dem Konto gutgeschrieben"
  defp amount_hint(_kind, _account_id), do: "wird dem Konto gutgeschrieben"

  defp expected_text(:dividend, _form), do: "Brutto abzüglich Gebühren und Steuern"

  defp expected_text(_kind, form) do
    if zero?(form[:fees].value) and zero?(form[:taxes].value),
      do: "Stück × Kurs",
      else: "Stück × Kurs mit Gebühren und Steuern"
  end

  defp zero?(%Decimal{} = value), do: Decimal.eq?(value, 0)
  defp zero?(_blank), do: true

  defp receipt_errors(uploads, form) do
    upload = uploads.receipt
    entry_errors = Enum.flat_map(upload.entries, &upload_errors(upload, &1))

    Enum.map(upload_errors(upload) ++ entry_errors, &upload_error/1) ++
      Enum.map(form[:receipt].errors, &translate_error/1)
  end

  defp upload_error(:too_large), do: "Die Datei ist zu groß."
  defp upload_error(:not_accepted), do: "Bitte eine PDF-Datei wählen."
  defp upload_error(:too_many_files), do: "Bitte nur eine Datei wählen."
  defp upload_error(_error), do: "Die Datei ließ sich nicht hochladen."

  @impl true
  def handle_event("open", _params, socket) do
    scope = socket.assigns.current_scope
    choices = Portfolios.transaction_choices(scope)
    portfolio = List.first(choices.portfolios)

    params = %{
      "kind" => "purchase",
      "date" => Date.to_iso8601(LocalTime.today()),
      "portfolio_id" => portfolio && to_string(portfolio.id),
      "account_id" => reference_account(choices, portfolio && portfolio.id),
      "fees" => "0,00",
      "taxes" => "0,00"
    }

    {:noreply,
     socket
     |> assign(open: true, choices: choices, today: LocalTime.today())
     |> put_form(Portfolios.change_transaction_form(scope, choices, params))}
  end

  def handle_event("close", _params, socket), do: {:noreply, close(socket)}

  def handle_event("validate", %{"transaction" => params} = event, socket) do
    params = follow(params, event["_target"], socket.assigns.choices)
    scope = socket.assigns.current_scope

    changeset =
      scope
      |> Portfolios.change_transaction_form(socket.assigns.choices, params)
      |> Map.put(:action, :validate)

    {:noreply, put_form(socket, changeset)}
  end

  def handle_event("book", %{"transaction" => params}, socket) do
    %{current_scope: scope, choices: choices} = socket.assigns
    changeset = Portfolios.change_transaction_form(scope, choices, params)

    cond do
      not changeset.valid? ->
        {:noreply, put_form(socket, Map.put(changeset, :action, :insert))}

      match?({_done, [_ | _]}, uploaded_entries(socket, :receipt)) ->
        {:noreply, socket}

      true ->
        socket |> book(params) |> booked(socket)
    end
  end

  # The account follows the portfolio; an amount typed in stays until it is emptied.
  defp follow(params, ["transaction", "portfolio_id"], choices),
    do:
      Map.put(params, "account_id", reference_account(choices, parse_id(params["portfolio_id"])))

  defp follow(params, ["transaction", "amount"], _choices),
    do: Map.put(params, "amount_set", to_string(String.trim(params["amount"] || "") != ""))

  defp follow(params, _target, _choices), do: params

  defp reference_account(choices, portfolio_id) do
    with %{reference_account_id: id} when id != nil <-
           Enum.find(choices.portfolios, &(&1.id == portfolio_id)),
         true <- Enum.any?(choices.accounts, &(&1.id == id)) do
      to_string(id)
    else
      _none -> ""
    end
  end

  defp book(socket, params) do
    %{current_scope: scope, choices: choices} = socket.assigns

    case consume_uploaded_entries(socket, :receipt, fn %{path: path}, entry ->
           {:ok, Portfolios.book_transaction(scope, choices, params, {path, entry.client_name})}
         end) do
      [result] -> result
      [] -> Portfolios.book_transaction(scope, choices, params)
    end
  end

  defp booked({:ok, transactions}, socket) do
    MarketData.broadcast()
    send(self(), {__MODULE__, :booked, booked_message(transactions)})
    {:noreply, assign(socket, :open, false)}
  end

  defp booked({:error, changeset}, socket), do: {:noreply, put_form(socket, changeset)}

  defp booked_message([_dividend, _removal]), do: "Dividende und Entnahme gebucht."
  defp booked_message([_transaction]), do: "Buchung gespeichert."

  defp close(socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.receipt.entries, socket, fn entry, socket ->
        cancel_upload(socket, :receipt, entry.ref)
      end)

    assign(socket, :open, false)
  end

  defp put_form(socket, changeset) do
    socket
    |> assign(:kind, Ecto.Changeset.get_field(changeset, :kind))
    |> assign(:form, to_form(changeset, as: :transaction))
  end
end
