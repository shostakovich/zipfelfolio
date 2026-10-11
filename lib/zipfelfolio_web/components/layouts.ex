defmodule ZipfelfolioWeb.Layouts do
  @moduledoc false
  use ZipfelfolioWeb, :html

  alias ZipfelfolioWeb.{Format, Sidebar, TransactionDialog}

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  attr :sidebar, :map,
    required: true,
    doc: "the portfolios and accounts and the inbox's count, see `ZipfelfolioWeb.Sidebar`"

  attr :current, :any,
    default: nil,
    doc: """
    what is open: `:overview`, `:dividends`, `:transactions`, `:portfolios`, `:performance`,
    `:settings`, or `{:holdings, portfolio_id, account_id}` with nil for all portfolios or no
    marked account
    """

  slot :inner_block, required: true

  @doc """
  Signed-in pages in setzkasten's sidebar shell: the views, the active portfolios and accounts with
  their values (not in the icon rail), the settings. „+ Buchung“ in the sidebar, in the top bar
  from 768 px and as the phone's floating button opens the dialog „Buchung erfassen“; the
  transactions page shows its own „Buchung erfassen“ from 768 px instead of the top bar's.
  """
  def app(assigns) do
    assigns = assign(assigns, :nav_key, nav_key(assigns.current, assigns.sidebar))

    ~H"""
    <.app_shell layout={:sidebar} width={:wide} current={@nav_key}>
      <:brand><.logo /> zipfelfolio</:brand>
      <:nav key={:overview} label="Übersicht" icon="house" navigate={~p"/"} />
      <:nav key={:holdings} label="Bestand" icon="layers" navigate={~p"/holdings"} />
      <:nav key={:dividends} label="Dividenden" icon="coins" navigate={~p"/dividends"} />
      <:nav
        key={:transactions}
        label="Buchungen"
        icon="list"
        navigate={~p"/transactions"}
        count={if @sidebar.inbox > 0, do: @sidebar.inbox}
        count_label="im Eingang"
      />
      <:nav key={:performance} label="Performance" icon="trending-up" navigate={~p"/performance"} />
      <:nav
        :for={row <- @sidebar.portfolios}
        key={{:portfolio, row.portfolio.id}}
        label={Format.portfolio_name(row.portfolio)}
        icon="briefcase"
        amount={row.value}
        section="Depots"
        rail={false}
        navigate={Sidebar.portfolio_path(row.portfolio)}
      />
      <:nav
        :for={row <- @sidebar.accounts}
        key={{:account, row.account.id}}
        label={row.account.name}
        icon="wallet"
        amount={row.value}
        section="Konten"
        rail={false}
        navigate={Sidebar.account_path(row.portfolio, row.account)}
      />
      <:nav key={:settings} label="Einstellungen" icon="settings" navigate={~p"/users/settings"} />
      <:nav_footer :let={place}>
        <div class="px-5 py-3">
          <.button
            id={if place == :sidebar, do: "side-book", else: "side-book-#{place}"}
            icon="plus"
            class="w-full"
            phx-click={book(place)}
          >
            Buchung
          </.button>
        </div>
      </:nav_footer>
      <:account :let={place}>
        <.button
          :if={place == :bar and @current != :transactions}
          id="bar-book"
          size={:sm}
          icon="plus"
          class="max-md:hidden"
          phx-click={TransactionDialog.open()}
        >
          Buchung
        </.button>
        <.dropdown
          id={"account-#{place}"}
          label="Konto"
          align={if place == :bar, do: :end, else: :start}
          position={if place == :sidebar, do: :top, else: :bottom}
          variant={:ghost}
          chevron={false}
          class={place == :sidebar && "w-full"}
          trigger_class={if place == :sidebar, do: "w-full justify-start", else: "btn-square"}
        >
          <:trigger>
            <.avatar initials={initial(@current_scope.user.email)} size={:sm} shape={:round} />
            <span :if={place == :sidebar} class="truncate">{@current_scope.user.email}</span>
          </:trigger>
          <:header :if={place != :sidebar}>{@current_scope.user.email}</:header>
          <:item navigate={~p"/users/settings" <> "#passkeys"} icon="key-round">Passkeys</:item>
          <:item href={~p"/users/log-out"} method="delete" icon="log-out">Abmelden</:item>
        </.dropdown>
      </:account>
      <:fab><.fab id="fab-book" label="Buchung" phx-click={TransactionDialog.open()} /></:fab>
      {render_slot(@inner_block)}
    </.app_shell>

    <.flash_group flash={@flash} />
    <.confirm_dialog />
    <.live_component
      module={TransactionDialog}
      id={TransactionDialog.id()}
      current_scope={@current_scope}
    />
    """
  end

  # The dialog „Buchung erfassen“ opens only after a round trip to the server, not with the click,
  # so the expanded sidebar closes first instead of staying open under it.
  defp book(:dialog), do: hide_modal("app-shell-sidebar") |> JS.concat(TransactionDialog.open())
  defp book(_place), do: TransactionDialog.open()

  # The sidebar row of what is open; an account or a portfolio the sidebar leaves out, as it is
  # retired, belongs to „Bestand“.
  defp nav_key({:holdings, portfolio_id, account_id}, sidebar) do
    key =
      cond do
        account_id -> {:account, account_id}
        portfolio_id -> {:portfolio, portfolio_id}
        true -> :holdings
      end

    shown =
      Enum.map(sidebar.portfolios, &{:portfolio, &1.portfolio.id}) ++
        Enum.map(sidebar.accounts, &{:account, &1.account.id})

    if key in shown, do: key, else: :holdings
  end

  defp nav_key(:portfolios, _sidebar), do: :settings
  defp nav_key(current, _sidebar), do: current

  attr :portfolios, :list, required: true
  attr :portfolio, :any, required: true, doc: "the one shown, nil for all"
  attr :path, :any, required: true, doc: "the page for a portfolio's id, nil for all"

  @doc "A menu to show all portfolios or one."
  def portfolio_switcher(assigns) do
    ~H"""
    <.dropdown id="portfolio-menu" label="Depot" align={:end} trigger_class="btn-sm">
      <:trigger>
        <.icon name="briefcase" />{if @portfolio,
          do: Format.portfolio_name(@portfolio),
          else: "Gesamt"}
      </:trigger>
      <:item patch={@path.(nil)} active={!@portfolio}>Gesamt</:item>
      <:item
        :for={{portfolio, index} <- Enum.with_index(@portfolios)}
        patch={@path.(portfolio.id)}
        active={@portfolio && @portfolio.id == portfolio.id}
        divider={index == 0}
      >
        {Format.portfolio_name(portfolio)}
      </:item>
    </.dropdown>
    """
  end

  # The bare mark: a rising line with the arrowhead in mustard.
  defp logo(assigns) do
    ~H"""
    <svg
      class="size-6 shrink-0"
      viewBox="10 12 44 44"
      fill="none"
      stroke-width="4.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M14 44l12-12 8 8 16-16" stroke="currentColor" />
      <path d="M40 24h10v10" stroke="#e0a224" />
    </svg>
    """
  end

  defp initial(name), do: String.upcase(String.first(name) || "")

  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc "Sign-in pages: a narrow column without navigation."
  def auth(assigns) do
    ~H"""
    <main id="main" class="mx-auto max-w-md px-4 py-12">
      <h1 class="mb-6 flex items-center justify-center gap-2 text-2xl font-semibold">
        <.logo /> zipfelfolio
      </h1>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end
end
