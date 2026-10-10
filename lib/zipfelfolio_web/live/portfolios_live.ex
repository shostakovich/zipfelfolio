defmodule ZipfelfolioWeb.PortfoliosLive do
  @moduledoc """
  „Depots“, the phone's tab for the money half of the sidebar: the total, then each portfolio
  with its reference account and the accounts of no portfolio, from `@sidebar`. Below, the
  depot numbers of the active portfolios, which find a receipt's portfolio; each is edited in
  place. On the desktop the settings link here.
  """
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.{Portfolios, Receipts}
  alias ZipfelfolioWeb.{Format, Sidebar}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:portfolios}
    >
      <.header>Depots</.header>

      <.card :if={@sidebar.portfolios == [] and @sidebar.accounts == []}>
        <p class="mb-0">
          Noch keine Depots. Sie kommen mit dem <.link navigate={~p"/settings/import"}>Import aus Portfolio Performance</.link>.
        </p>
      </.card>

      <div :if={@sidebar.portfolios != [] or @sidebar.accounts != []} class="app-tree">
        <div class="list-group mb-4">
          <.tree_link
            id="tree-total"
            navigate={~p"/holdings"}
            name="Gesamt"
            value={Layouts.total(@sidebar.portfolios) + Layouts.total(@sidebar.accounts)}
          >
            <span class="app-chip app-chip-all" aria-hidden="true"><.icon name="layers" /></span>
          </.tree_link>
        </div>

        <.group :if={@sidebar.portfolios != []} title="Depots" rows={@sidebar.portfolios}>
          <%= for row <- @sidebar.portfolios do %>
            <.tree_link
              id={"tree-portfolio-#{row.portfolio.id}"}
              navigate={Sidebar.portfolio_path(row.portfolio)}
              name={row.portfolio.name}
              value={row.value}
            >
              <Layouts.chip portfolio={row.portfolio} />
            </.tree_link>
            <.tree_link
              :if={row.account}
              id={"tree-account-#{row.account.account.id}"}
              class="app-sub"
              navigate={Sidebar.account_path(row.portfolio, row.account.account)}
              name={row.account.account.name}
              value={row.account.value}
            >
              <.icon name="wallet" />
            </.tree_link>
          <% end %>
        </.group>

        <.group :if={@sidebar.accounts != []} title="Konten" rows={@sidebar.accounts}>
          <.tree_link
            :for={row <- @sidebar.accounts}
            id={"tree-account-#{row.account.id}"}
            navigate={Sidebar.account_path(nil, row.account)}
            name={row.account.name}
            value={row.value}
          >
            <Layouts.wallet_chip />
          </.tree_link>
        </.group>
      </div>

      <section :if={@active_portfolios != []} id="depot-numbers" aria-labelledby="depot-numbers-title">
        <h2 id="depot-numbers-title" class="app-sheet-h"><span>Depotnummern</span></h2>
        <ul class="list-group mb-2">
          <.depot_number_row
            :for={portfolio <- @active_portfolios}
            portfolio={portfolio}
            form={@editing == portfolio.id && @depot_number_form}
          />
        </ul>
        <p class="small text-body-secondary mx-1">
          Belege finden ihr Depot über die Depotnummer; nur die Ziffern zählen.
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :portfolio, :map, required: true
  attr :form, :any, required: true, doc: "the depot number's form while it is edited, else false"

  defp depot_number_row(%{form: false} = assigns) do
    ~H"""
    <li id={"depot-number-#{@portfolio.id}"} class="list-group-item d-flex align-items-start">
      <Layouts.chip portfolio={@portfolio} />
      <span class="me-auto app-depot-number-text">
        <span class="d-block text-truncate">{@portfolio.name}</span>
        <span class="d-block small text-body-secondary">
          <%= for {part, index} <- Enum.with_index(depot_number_details(@portfolio)) do %>
            <span :if={index > 0}> · </span><span class="text-nowrap">{part}</span>
          <% end %>
        </span>
      </span>
      <button
        type="button"
        class="btn btn-sm flex-shrink-0 align-self-center"
        phx-click="edit_depot_number"
        phx-value-id={@portfolio.id}
        aria-label={"#{depot_number_action(@portfolio)}: Depotnummer von „#{@portfolio.name}“"}
      >
        {depot_number_action(@portfolio)}
      </button>
    </li>
    """
  end

  defp depot_number_row(assigns) do
    ~H"""
    <li id={"depot-number-#{@portfolio.id}"} class="list-group-item d-flex align-items-start">
      <Layouts.chip portfolio={@portfolio} />
      <.form
        for={@form}
        id="depot-number-form"
        class="flex-grow-1 app-depot-number-text"
        phx-change="validate_depot_number"
        phx-submit="save_depot_number"
        phx-window-keydown="cancel_depot_number"
        phx-key="Escape"
      >
        <label class="form-label fw-normal mb-1" for={@form[:depot_number].id}>
          Depotnummer von „{@portfolio.name}“
        </label>
        <div class="d-flex flex-column flex-sm-row align-items-sm-start gap-2">
          <.input
            field={@form[:depot_number]}
            wrapper_class="flex-grow-1"
            class="tabular-nums"
            inputmode="numeric"
            autocomplete="off"
            spellcheck="false"
            placeholder="z. B. 123 456 7890"
            phx-mounted={JS.focus()}
          />
          <div class="d-flex gap-2">
            <.button phx-disable-with="Speichert …">Speichern</.button>
            <button type="button" class="btn" phx-click="cancel_depot_number">Abbrechen</button>
          </div>
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

  attr :title, :string, required: true
  attr :rows, :list, required: true
  slot :inner_block, required: true

  defp group(assigns) do
    ~H"""
    <h2 class="app-sheet-h">
      <span>{@title}</span><span>{Format.euros(Layouts.total(@rows), 2)}</span>
    </h2>
    <div class="list-group mb-4">{render_slot(@inner_block)}</div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :name, :string, required: true
  attr :value, :integer, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true, doc: "the chip or icon"

  defp tree_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={["list-group-item list-group-item-action", @class]}
    >
      {render_slot(@inner_block)}
      <span class="me-auto text-truncate">{@name}</span>
      <span class={["tabular-nums text-nowrap", @value == 0 && "text-body-secondary"]}>
        {Format.euros(@value, 2)}
      </span>
      <.icon name="chevron" class="app-chev" />
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Depots", editing: nil, depot_number_form: nil)
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
         |> put_flash(:info, "Depotnummer von „#{portfolio.name}“ gespeichert.")
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
