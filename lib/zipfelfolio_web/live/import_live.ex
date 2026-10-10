defmodule ZipfelfolioWeb.ImportLive do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{MarketData, Portfolios, PPImport}

  @labels [
    securities: "Wertpapiere",
    prices: "Kurse",
    attribute_types: "Attribute",
    accounts: "Konten",
    portfolios: "Depots",
    transactions: "Buchungen",
    savings_plans: "Sparpläne",
    taxonomies: "Klassifizierungen",
    classifications: "Kategorien",
    assignments: "Zuordnungen"
  ]

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
        Import aus Portfolio Performance
        <:actions>
          <.link navigate={~p"/users/settings"} class="btn btn-sm btn-outline-secondary">
            Einstellungen
          </.link>
        </:actions>
      </.header>

      <div class="row g-4">
        <div class="col-lg-7">
          <.card title="Datei importieren">
            <p>
              Übernimmt Wertpapiere, Kurse, Depots, Konten, Buchungen, Sparpläne und Klassifizierungen.
              Ein erneuter Import gleicht alles an die Datei an; was du in zipfelfolio eingestellt
              hast, etwa die Kursquelle, bleibt.
            </p>
            <div :if={@own_transactions?} class="alert alert-warning" role="alert">
              Du hast schon Buchungen in zipfelfolio erfasst. Sie bleiben erhalten; stehen sie auch
              in Portfolio Performance, sind sie danach doppelt.
            </div>
            <form id="import-form" phx-submit="import" phx-change="validate">
              <label class="form-label" for={@uploads.pp_file.ref}>
                PP-Datei (.portfolio, Binärformat)
              </label>
              <.live_file_input upload={@uploads.pp_file} class="form-control mb-2" />
              <p
                :for={error <- upload_errors(@uploads.pp_file) ++ entry_errors(@uploads.pp_file)}
                class="text-danger small"
              >
                {upload_error(error)}
              </p>
              <.button
                phx-disable-with="Wird importiert …"
                disabled={@uploads.pp_file.entries == []}
              >
                Importieren
              </.button>
            </form>
          </.card>
        </div>

        <div :if={@summary} class="col-lg-5">
          <.card title="Ergebnis" id="import-summary">
            <table class="table table-sm mb-0">
              <thead>
                <tr>
                  <th scope="col"></th>
                  <th scope="col" class="text-end">neu</th>
                  <th scope="col" class="text-end">geändert</th>
                  <th scope="col" class="text-end">gelöscht</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{kind, label} <- labels()} id={"summary-#{kind}"}>
                  <th scope="row" class="fw-normal">{label}</th>
                  <td class="text-end">{@summary[kind].created}</td>
                  <td class="text-end">{@summary[kind].updated}</td>
                  <td class="text-end">{@summary[kind].deleted}</td>
                </tr>
              </tbody>
            </table>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import")
     |> assign(:summary, nil)
     |> assign(:own_transactions?, Portfolios.own_transactions?(socket.assigns.current_scope))
     # `.portfolio` has no MIME type; the reader checks the contents instead.
     |> allow_upload(:pp_file, accept: :any, max_entries: 1, max_file_size: 100_000_000)}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, socket) do
    case uploaded_entries(socket, :pp_file) do
      {[_entry], []} -> import_file(socket)
      _not_ready -> {:noreply, socket}
    end
  end

  defp import_file(socket) do
    scope = socket.assigns.current_scope

    [result] =
      consume_uploaded_entries(socket, :pp_file, fn %{path: path}, _entry ->
        {:ok, PPImport.run(scope, path)}
      end)

    case result do
      {:ok, summary} ->
        MarketData.broadcast()

        {:noreply,
         socket
         |> assign(:summary, summary)
         |> put_flash(:info, "Import abgeschlossen.")}

      {:error, reason} ->
        {:noreply, socket |> assign(:summary, nil) |> put_flash(:error, error_message(reason))}
    end
  end

  defp labels, do: @labels

  defp entry_errors(upload), do: Enum.flat_map(upload.entries, &upload_errors(upload, &1))

  defp upload_error(:too_large), do: "Die Datei ist zu groß."
  defp upload_error(:too_many_files), do: "Bitte nur eine Datei wählen."
  defp upload_error(_), do: "Die Datei ließ sich nicht hochladen."

  defp error_message(:xml_format),
    do: "Die Datei ist im XML-Format. Speichere sie in Portfolio Performance als Binärdatei."

  defp error_message(:too_large), do: "Die Datei ist entpackt zu groß."

  defp error_message(:malformed), do: "Die Datei ist beschädigt oder hat ein unbekanntes Format."

  defp error_message(_),
    do: "Das ist keine (unverschlüsselte) Datei aus Portfolio Performance."
end
