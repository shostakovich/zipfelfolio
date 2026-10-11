defmodule ZipfelfolioWeb.PortfoliosLive do
  @moduledoc """
  „Depots“: the depot numbers of the active portfolios, which find a receipt's portfolio; each is
  edited in place. The settings link here.
  """
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{Portfolios, Receipts}
  alias ZipfelfolioWeb.Format

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:portfolios}
    >
      <.header back={~p"/users/settings"} back_label="Einstellungen">
        Depotnummern
        <:subtitle>Belege finden ihr Depot über die Depotnummer; nur die Ziffern zählen.</:subtitle>
      </.header>

      <.no_portfolios :if={@active_portfolios == []} />

      <section :if={@active_portfolios != []} id="depot-numbers" aria-label="Depotnummern">
        <.list>
          <.depot_number_row
            :for={portfolio <- @active_portfolios}
            portfolio={portfolio}
            form={@editing == portfolio.id && @depot_number_form}
          />
        </.list>
      </section>
    </Layouts.app>
    """
  end

  attr :portfolio, :map, required: true
  attr :form, :any, required: true, doc: "the depot number's form while it is edited, else false"

  defp depot_number_row(%{form: false} = assigns) do
    ~H"""
    <.list_row id={"depot-number-#{@portfolio.id}"} title={Format.portfolio_name(@portfolio)}>
      <:leading><.icon name="briefcase" class="size-5 text-base-content/70" /></:leading>
      <:meta>
        <span :for={{part, index} <- Enum.with_index(depot_number_details(@portfolio))}><.meta_sep :if={
          index > 0
        } /><span class="whitespace-nowrap">{part}</span></span>
      </:meta>
      <:trailing>
        <.button
          size={:sm}
          phx-click="edit_depot_number"
          phx-value-id={@portfolio.id}
          aria-label={"#{depot_number_action(@portfolio)}: Depotnummer von „#{Format.portfolio_name(@portfolio)}“"}
        >
          {depot_number_action(@portfolio)}
        </.button>
      </:trailing>
    </.list_row>
    """
  end

  defp depot_number_row(assigns) do
    ~H"""
    <li id={"depot-number-#{@portfolio.id}"} class="list-row items-start">
      <.icon name="briefcase" class="mt-0.5 size-5 text-base-content/70" />
      <.form
        for={@form}
        id="depot-number-form"
        class="list-col-grow min-w-0"
        phx-change="validate_depot_number"
        phx-submit="save_depot_number"
        phx-window-keydown="cancel_depot_number"
        phx-key="Escape"
      >
        <p class="font-medium wrap-anywhere">{Format.portfolio_name(@portfolio)}</p>
        <div class="flex flex-col sm:flex-row sm:items-start sm:gap-2">
          <div class="sm:max-w-md sm:flex-1">
            <.input
              field={@form[:depot_number]}
              label={"Depotnummer von „#{Format.portfolio_name(@portfolio)}“"}
              inline
              class="tabular-nums"
              inputmode="numeric"
              autocomplete="off"
              spellcheck="false"
              placeholder="z. B. 123 456 7890"
              phx-mounted={JS.focus()}
            >
              <.button
                type="submit"
                variant={:primary}
                class="join-item"
                phx-disable-with="Speichert …"
              >
                Speichern
              </.button>
            </.input>
          </div>
          <.button variant={:ghost} class="sm:mt-1" phx-click="cancel_depot_number">
            Abbrechen
          </.button>
        </div>
      </.form>
    </li>
    """
  end

  defp depot_number_details(portfolio) do
    Enum.reject(
      [
        if(portfolio.depot_number,
          do: "Depotnummer #{Format.masked(portfolio.depot_number)}",
          else: "Keine Depotnummer"
        ),
        portfolio.reference_account && "Referenzkonto „#{portfolio.reference_account.name}“"
      ],
      &is_nil/1
    )
  end

  defp depot_number_action(%{depot_number: nil}), do: "Eintragen"
  defp depot_number_action(_portfolio), do: "Ändern"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Depotnummern", editing: nil, depot_number_form: nil)
     |> load_active_portfolios()}
  end

  @impl true
  def handle_event("edit_depot_number", %{"id" => id}, socket) do
    case find_portfolio(socket, id) do
      nil -> {:noreply, socket}
      portfolio -> {:noreply, edit(socket, portfolio, %{})}
    end
  end

  def handle_event("validate_depot_number", %{"portfolio" => params}, socket) do
    case find_portfolio(socket, socket.assigns.editing) do
      nil -> {:noreply, socket}
      portfolio -> {:noreply, edit(socket, portfolio, params, :validate)}
    end
  end

  def handle_event("save_depot_number", %{"portfolio" => params}, socket) do
    case find_portfolio(socket, socket.assigns.editing) do
      nil -> {:noreply, socket}
      portfolio -> save(socket, portfolio, params)
    end
  end

  def handle_event("cancel_depot_number", _params, socket),
    do: {:noreply, assign(socket, editing: nil, depot_number_form: nil)}

  defp save(socket, portfolio, params) do
    scope = socket.assigns.current_scope

    case Portfolios.update_depot_number(scope, portfolio, params) do
      {:ok, _portfolio} ->
        Receipts.recheck(scope)

        {:noreply,
         socket
         |> put_flash(:info, "Depotnummer von „#{Format.portfolio_name(portfolio)}“ gespeichert.")
         |> assign(editing: nil, depot_number_form: nil)
         |> load_active_portfolios()}

      {:error, changeset} ->
        {:noreply, assign(socket, :depot_number_form, to_form(changeset, action: :update))}
    end
  end

  defp edit(socket, portfolio, params, action \\ nil) do
    changeset = Portfolios.change_depot_number(socket.assigns.current_scope, portfolio, params)
    assign(socket, editing: portfolio.id, depot_number_form: to_form(changeset, action: action))
  end

  defp find_portfolio(socket, id),
    do: Enum.find(socket.assigns.active_portfolios, &(to_string(&1.id) == to_string(id)))

  defp load_active_portfolios(socket),
    do:
      assign(
        socket,
        :active_portfolios,
        Portfolios.list_active_portfolios(socket.assigns.current_scope)
      )
end
