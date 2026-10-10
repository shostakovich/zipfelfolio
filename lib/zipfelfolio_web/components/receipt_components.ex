defmodule ZipfelfolioWeb.ReceiptComponents do
  @moduledoc """
  How the screens show a receipt of the inbox: its row on „Buchungen“, and in the dialog „Beleg
  prüfen“ its checks and its text with the recognised values marked.
  """
  use Phoenix.Component

  use ZipfelfolioWeb, :verified_routes

  import ZipfelfolioWeb.CoreComponents, only: [icon: 1]

  alias Zipfelfolio.Portfolios.Receipt
  alias Zipfelfolio.Receipts.{Check, Checks, Correction, Fields}
  alias ZipfelfolioWeb.{Format, ReceiptText, TransactionDialog}

  @kinds %{purchase: "Kauf", sale: "Verkauf", dividend: "Dividende"}

  attr :receipts, :list, required: true
  attr :names, :map, required: true, doc: "the names of the known securities by ISIN"
  attr :polled_at, DateTime, default: nil, doc: "when the user's Paperless was polled last"

  @doc "The inbox: a row per receipt with what it needs next."
  def inbox(assigns) do
    ~H"""
    <section id="inbox" class="card mb-4" aria-labelledby="inbox-title">
      <div class="card-header d-flex align-items-center gap-2">
        <.icon name="inbox" />
        <h2 id="inbox-title" class="h6 mb-0 me-auto">Eingang</h2>
        <span class="small text-body-secondary text-end">
          {count(@receipts)}
          <span :if={@polled_at} id="inbox-polled">
            · <span class="d-none d-sm-inline">zuletzt</span> abgefragt {polled(@polled_at)}
          </span>
        </span>
      </div>
      <ul class="list-group list-group-flush">
        <.inbox_row :for={receipt <- @receipts} receipt={receipt} names={@names} />
      </ul>
    </section>
    """
  end

  defp polled(polled_at), do: Format.recent(polled_at)

  defp count([_one]), do: "1 Beleg"
  defp count(receipts), do: "#{length(receipts)} Belege"

  attr :receipt, Receipt, required: true
  attr :names, :map, required: true

  defp inbox_row(assigns) do
    assigns = assign(assigns, state: state(assigns.receipt))

    ~H"""
    <li
      id={"receipt-#{@receipt.id}"}
      class="list-group-item d-flex flex-wrap align-items-center gap-2 gap-sm-3 app-inbox-row"
    >
      <span class={[
        "app-avatar rounded-circle d-flex align-items-center justify-content-center flex-shrink-0",
        avatar_tone(@state)
      ]}>
        <span
          :if={@state == :recognising}
          class="spinner-border spinner-border-sm"
          aria-hidden="true"
        ></span>
        <.icon :if={@state != :recognising} name={state_icon(@state)} />
      </span>
      <span class="me-auto app-inbox-text">
        <span class="d-block fw-semibold text-truncate">{title(@receipt, @names)}</span>
        <span class="small d-block text-body-secondary">{detail(@receipt, @state)}</span>
        <span :if={@state == :warning} class="small d-block text-warning-emphasis">
          {warning(@receipt)}
        </span>
      </span>
      <.inbox_action receipt={@receipt} state={@state} />
    </li>
    """
  end

  attr :receipt, Receipt, required: true
  attr :state, :atom, required: true

  defp inbox_action(%{state: :recognising} = assigns), do: ~H""

  defp inbox_action(%{state: state} = assigns) when state in [:unsupported, :duplicate] do
    ~H"""
    <button
      type="button"
      class="btn btn-sm btn-outline-secondary app-inbox-action"
      phx-click="discard"
      phx-value-id={@receipt.id}
      aria-label={"#{@receipt.filename} verwerfen"}
    >
      Verwerfen
    </button>
    """
  end

  defp inbox_action(assigns) do
    ~H"""
    <button
      type="button"
      class={["btn btn-sm app-inbox-action", action_class(@state)]}
      phx-click={TransactionDialog.open_receipt(@receipt.id)}
    >
      {action_label(@state, @receipt)}
    </button>
    """
  end

  # What a receipt needs next: wait, discard, book as recognised, check a warning, or type it.
  defp state(%Receipt{status: :recognising}), do: :recognising
  defp state(%Receipt{status: :unsupported}), do: :unsupported
  defp state(%Receipt{fields: nil}), do: :unrecognised

  defp state(%Receipt{checks: checks}) do
    cond do
      Checks.duplicate?(checks) -> :duplicate
      problems(checks) != [] -> :warning
      true -> :passed
    end
  end

  # A missing reference is no problem: not every bank prints one.
  defp problems(checks) do
    Enum.reject(
      checks,
      &(&1.result == :passed or (&1.name == :reference and &1.result == :missing))
    )
  end

  defp avatar_tone(:passed), do: "bg-success-subtle text-success-emphasis"
  defp avatar_tone(:warning), do: "bg-warning-subtle text-warning-emphasis"
  defp avatar_tone(_state), do: "bg-secondary-subtle text-secondary-emphasis"

  defp state_icon(:passed), do: "check"
  defp state_icon(:warning), do: "alert"
  defp state_icon(:duplicate), do: "copy"
  defp state_icon(:unsupported), do: "file"
  defp state_icon(:unrecognised), do: "file"

  defp action_class(:passed), do: "btn-success"
  defp action_class(:warning), do: "btn-outline-warning"
  defp action_class(:unrecognised), do: "btn-outline-primary"

  defp action_label(:unrecognised, _receipt), do: "Erfassen"

  defp action_label(:warning, receipt) do
    if Enum.any?(receipt.checks, &(&1.name in [:amount, :found] and &1.result == :failed)),
      do: "Korrigieren",
      else: "Prüfen und buchen"
  end

  defp action_label(_state, _receipt), do: "Prüfen und buchen"

  @doc "Whether the receipt passed every check that matters, so booking it needs no correction."
  def passed?(%Receipt{fields: nil}), do: false
  def passed?(%Receipt{checks: checks}), do: problems(checks) == []

  defp title(%Receipt{fields: %Fields{kind: kind} = fields}, names) when is_map_key(@kinds, kind),
    do: Enum.join([@kinds[kind], names[fields.isin] || fields.security_name], " · ")

  defp title(receipt, _names), do: receipt.filename

  defp detail(receipt, :recognising), do: join([source(receipt), "wird erkannt …"])
  defp detail(receipt, :unsupported), do: join([source(receipt), "nicht unterstützt"])

  defp detail(receipt, :unrecognised),
    do: join([source(receipt), "nicht erkannt, bitte von Hand erfassen"])

  defp detail(receipt, :duplicate) do
    check = Enum.find(receipt.checks, &(&1.name == :reference))

    join([
      date(receipt.fields),
      source(receipt),
      "gleiche Referenznummer wie die Buchung vom #{Format.date(check.booked_on)}"
    ])
  end

  defp detail(receipt, :warning), do: join(figures(receipt.fields) ++ [source(receipt)])

  defp detail(receipt, :passed),
    do: join(figures(receipt.fields) ++ [source(receipt), "alle Prüfungen bestanden"])

  defp source(%Receipt{paperless_id: nil}), do: "Upload"
  defp source(%Receipt{paperless_id: id}), do: "Paperless ##{id}"

  defp figures(fields) do
    [
      date(fields),
      fields.shares && "#{decimal(fields.shares)} Stück",
      fields.amount && "#{Format.decimal(fields.amount, 2)} €"
    ]
  end

  defp warning(receipt), do: receipt.checks |> problems() |> hd() |> check_text(receipt.fields)

  defp date(%Fields{date: date}), do: date && Format.date(date)

  defp join(parts), do: parts |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

  @doc "What the dialog says the receipt is: its Paperless document or file, kind and date."
  def receipt_subtitle(%Receipt{fields: fields} = receipt) do
    kind =
      case fields do
        %Fields{kind: kind, date: %Date{} = date} when is_map_key(@kinds, kind) ->
          "#{@kinds[kind]} vom #{Format.date(date)}"

        _unknown ->
          nil
      end

    join([if(receipt.paperless_id, do: source(receipt), else: receipt.filename), kind])
  end

  attr :receipt, Receipt, required: true

  @doc "The receipt's text as on paper, with the recognised values marked, and its PDF."
  def sheet(assigns) do
    assigns =
      assign(assigns, :pieces, ReceiptText.pieces(assigns.receipt.text, assigns.receipt.fields))

    ~H"""
    <div class="d-flex align-items-center gap-2 mb-2 app-receipt-head">
      <span class="small text-body-secondary me-auto">Text des Belegs</span>
      <a
        id="receipt-pdf"
        href={~p"/receipts/#{@receipt.id}"}
        target="_blank"
        rel="noopener"
        class="btn btn-sm d-inline-flex align-items-center gap-1"
      >
        <.icon name="file" class="app-icon-sm" /> PDF öffnen
      </a>
    </div>
    <div :if={@pieces != []} class="app-receipt-sheet">
      <pre
        id="receipt-text"
        class="app-receipt-lines"
        tabindex="0"
        aria-label="Text des Belegs"
      ><%= for piece <- @pieces do %><.piece piece={piece} /><% end %></pre>
    </div>
    <p :if={@pieces == []} id="receipt-text" class="alert alert-light mb-0">
      Das PDF hat keinen lesbaren Text. Bitte die Werte aus dem PDF übernehmen.
    </p>
    """
  end

  defp piece(%{piece: {:mark, _text}} = assigns), do: ~H"<mark>{elem(@piece, 1)}</mark>"
  defp piece(%{piece: {:text, _text}} = assigns), do: ~H"{elem(@piece, 1)}"

  attr :receipt, Receipt, required: true

  @doc "The receipt's checks, or why there are none."
  def checklist(%{receipt: %Receipt{fields: nil}} = assigns) do
    ~H"""
    <div class="small text-body-secondary mb-2 app-receipt-head d-flex align-items-center">
      Prüfungen
    </div>
    <div id="receipt-checks" class="alert alert-light small d-flex gap-2 mb-3">
      <.icon name="alert" class="app-icon-sm flex-shrink-0 mt-1" />
      <span>Nicht erkannt. Bitte die Werte aus dem Beleg übernehmen.</span>
    </div>
    """
  end

  def checklist(assigns) do
    ~H"""
    <div class="small text-body-secondary mb-2 app-receipt-head d-flex align-items-center">
      Prüfungen
    </div>
    <ul id="receipt-checks" class="list-group mb-3 small" aria-label="Prüfungen">
      <li
        :for={check <- @receipt.checks}
        id={"receipt-check-#{check.name}"}
        class={[
          "list-group-item d-flex gap-2 align-items-start py-2",
          check_problem?(check) && "list-group-item-warning"
        ]}
      >
        <.icon name={check_icon(check)} class={["app-icon-sm flex-shrink-0 mt-1", check_tone(check)]} />
        <span>
          <span class="visually-hidden">{check_result(check)}: </span>{check_text(
            check,
            @receipt.fields
          )}
        </span>
      </li>
    </ul>
    """
  end

  @doc "What the price field says when the receipt's amount does not add up, nil otherwise."
  def price_warning(%Receipt{checks: checks, fields: fields}) do
    if Enum.any?(checks, &match?(%Check{name: :amount, result: :failed}, &1)),
      do: "Summe laut Beleg: #{Format.decimal(fields.amount, 2)}\u00A0€"
  end

  def price_warning(nil), do: nil

  @doc "What the portfolio field says when the receipt's depot number names none, nil otherwise."
  def depot_number_warning(%Receipt{checks: checks, fields: fields}) do
    case Enum.find(checks, &(&1.name == :depot)) do
      %Check{result: :failed} -> "Laut Beleg Depot #{Format.masked(fields.depot_number)}"
      %Check{result: :missing} -> "Der Beleg nennt keine Depotnummer."
      _passed_or_none -> nil
    end
  end

  defp check_problem?(check), do: problems([check]) != []

  defp check_icon(%Check{result: :passed}), do: "check"
  defp check_icon(_check), do: "alert"

  defp check_tone(%Check{result: :passed}), do: "text-success"
  defp check_tone(%Check{name: :reference, result: :missing}), do: "text-body-tertiary"
  defp check_tone(%Check{result: :failed, name: :reference}), do: "text-danger"
  defp check_tone(_check), do: "text-warning"

  defp check_result(%Check{result: :passed}), do: "bestanden"
  defp check_result(%Check{name: :reference, result: :missing}), do: "Hinweis"
  defp check_result(_check), do: "nicht bestanden"

  defp check_text(%Check{name: :amount, result: :passed} = check, fields),
    do: "#{Checks.formula(fields)} = #{Format.decimal(check.computed, 2)} €"

  defp check_text(%Check{name: :amount, result: :failed} = check, fields) do
    text =
      "#{Checks.formula(fields)} ergibt #{Format.decimal(check.computed, 2)} €, " <>
        "der Beleg nennt #{Format.decimal(fields.amount, 2)} €."

    text <> " Bitte Kurs prüfen."
  end

  defp check_text(%Check{name: :amount, result: :missing}, _fields),
    do: "Betrag nicht prüfbar: Stück, Kurs oder Betrag fehlen."

  defp check_text(%Check{name: :found, result: :passed}, _fields),
    do: "Alle Werte im Beleg gefunden"

  defp check_text(%Check{name: :found, result: :failed} = check, fields),
    do: Correction.not_found(check, fields) <> ", bitte prüfen."

  defp check_text(%Check{name: :isin, result: :passed}, _fields),
    do: "ISIN gültig und bekannt"

  defp check_text(%Check{name: :isin, result: :new_security}, fields),
    do: "ISIN #{fields.isin} gültig, Wertpapier noch nicht angelegt"

  defp check_text(%Check{name: :isin, result: :failed}, fields),
    do: "ISIN #{fields.isin} ist ungültig, bitte prüfen."

  defp check_text(%Check{name: :isin, result: :missing}, _fields),
    do: "Keine ISIN erkannt"

  defp check_text(%Check{name: :depot, result: :passed} = check, fields),
    do: "Depot #{Format.masked(fields.depot_number)} gehört zu „#{check.portfolio_name}“"

  defp check_text(%Check{name: :depot, result: :failed}, fields),
    do:
      "Depot #{Format.masked(fields.depot_number)} gehört zu keinem deiner Depots. " <>
        "Bitte Depot wählen."

  defp check_text(%Check{name: :depot, result: :missing}, _fields),
    do: "Keine Depotnummer erkannt. Bitte Depot wählen."

  defp check_text(%Check{name: :reference, result: :passed}, fields),
    do: "Referenz #{fields.bank_reference} noch nicht gebucht"

  defp check_text(%Check{name: :reference, result: :failed} = check, _fields),
    do: "Gleiche Referenznummer wie die Buchung vom #{Format.date(check.booked_on)}"

  defp check_text(%Check{name: :reference, result: :missing}, _fields),
    do: "Keine Referenznummer erkannt"

  defp decimal(decimal) do
    normalized = Decimal.normalize(decimal)
    Format.decimal(normalized, max(-normalized.exp, 0))
  end
end
