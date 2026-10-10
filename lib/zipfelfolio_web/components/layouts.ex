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
  Signed-in pages: from 768 px a dark sidebar, open or collapsed to an icon rail (`sidebar.js`),
  below it a header and a tab bar; both open the dialog „Buchung erfassen“.
  """
  def app(assigns) do
    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2" href="#main">Zum Inhalt springen</a>

    <aside
      id="sidebar"
      class="app-side d-none d-md-flex flex-column"
      data-bs-theme="dark"
      aria-label="Hauptnavigation"
      phx-hook="Sidebar"
    >
      <.account_menu user={@current_scope.user} />
      <div class="app-side-scroll">
        <button
          id="side-book"
          type="button"
          class="app-side-book"
          phx-click={TransactionDialog.open()}
        >
          <.icon name="plus" />
          <span class="app-side-text">Buchung</span>
          <span class="app-fly" aria-hidden="true">Buchung erfassen</span>
        </button>
        <nav class="nav flex-column" aria-label="Ansichten">
          <.side_link
            id="side-overview"
            navigate={~p"/"}
            icon="home"
            current={@current}
            open={:overview}
          >
            Übersicht
          </.side_link>
          <.side_link
            id="side-holdings"
            navigate={~p"/holdings"}
            icon="layers"
            current={@current}
            open={{:holdings, nil, nil}}
          >
            Bestand
          </.side_link>
          <.side_link
            id="side-dividends"
            navigate={~p"/dividends"}
            icon="coins"
            current={@current}
            open={:dividends}
          >
            Dividenden
          </.side_link>
          <.side_link
            id="side-transactions"
            navigate={~p"/transactions"}
            icon="list"
            current={@current}
            open={:transactions}
            badge={@sidebar.inbox}
          >
            Buchungen
          </.side_link>
          <.side_link
            id="side-performance"
            navigate={~p"/performance"}
            icon="trend"
            current={@current}
            open={:performance}
          >
            Performance
          </.side_link>
        </nav>
        <.side_money sidebar={@sidebar} current={@current} />
      </div>
      <div class="app-side-foot">
        <.side_link
          id="side-settings"
          navigate={~p"/users/settings"}
          icon="gear"
          current={@current}
          open={:settings}
        >
          Einstellungen
        </.side_link>
        <button
          id="side-toggle"
          type="button"
          class="app-side-toggle"
          aria-controls="sidebar"
          aria-label="Seitenleiste einklappen"
        >
          <.icon name="sidebar" />
          <span class="app-fly" aria-hidden="true">Seitenleiste ausklappen</span>
        </button>
      </div>
    </aside>
    <div id="side-scrim" class="app-side-scrim"></div>

    <header id="phone-header" class="d-flex d-md-none align-items-center gap-2 px-3 pt-3 pb-2">
      <.link
        class="d-flex align-items-center gap-2 fw-bold fs-5 text-decoration-none text-body me-auto"
        navigate={~p"/"}
      >
        <.logo class="app-head-logo" /> zipfelfolio
      </.link>
      <.link
        navigate={~p"/users/settings"}
        class="app-avatar-hit text-decoration-none"
        aria-label={"Einstellungen (#{@current_scope.user.email})"}
      >
        <span
          class="app-avatar rounded-circle text-bg-primary d-flex align-items-center justify-content-center fw-bold"
          aria-hidden="true"
        >
          {initial(@current_scope.user.email)}
        </span>
      </.link>
    </header>

    <main class="app container-xl px-3" id="main">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>

    <div class="app-fab d-md-none">
      <button
        id="fab-book"
        type="button"
        class="btn btn-primary btn-lg rounded-pill shadow-lg"
        phx-click={TransactionDialog.open()}
      >
        <.icon name="plus" /> Buchung
      </button>
    </div>

    <.live_component
      module={TransactionDialog}
      id={TransactionDialog.id()}
      current_scope={@current_scope}
    />

    <nav
      id="tabbar"
      class="navbar fixed-bottom pb-safe d-md-none app-tabbar"
      aria-label="App-Navigation"
    >
      <ul class="nav nav-pills nav-justified w-100">
        <.tab id="tab-overview" navigate={~p"/"} icon="home" active={@current == :overview}>
          Übersicht
        </.tab>
        <.tab
          id="tab-portfolios"
          navigate={~p"/portfolios"}
          icon="layers"
          active={@current == :portfolios or match?({:holdings, _, _}, @current)}
        >
          Depots
        </.tab>
        <.tab
          id="tab-dividends"
          navigate={~p"/dividends"}
          icon="coins"
          active={@current == :dividends}
        >
          Dividenden
        </.tab>
        <.tab
          id="tab-transactions"
          navigate={~p"/transactions"}
          icon="list"
          active={@current == :transactions}
          badge={@sidebar.inbox}
        >
          Buchungen
        </.tab>
        <.tab
          id="tab-performance"
          navigate={~p"/performance"}
          icon="trend"
          active={@current == :performance}
        >
          Performance
        </.tab>
      </ul>
    </nav>
    """
  end

  attr :user, :map, required: true

  # A Bootstrap dropdown without Bootstrap's JS: LiveView's JS commands toggle it.
  defp account_menu(assigns) do
    ~H"""
    <div
      class="app-side-top dropdown"
      phx-click-away={hide_account_menu()}
      phx-window-keydown={hide_account_menu()}
      phx-key="Escape"
    >
      <button
        id="side-me"
        type="button"
        class="app-side-me"
        aria-expanded="false"
        aria-controls="side-menu"
        phx-click={
          JS.toggle_class("show", to: "#side-menu")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
      >
        <.logo />
        <span class="app-side-text"><b>zipfelfolio</b><small>{@user.email}</small></span>
        <.icon name="down" class="app-chev" />
        <span class="app-fly" aria-hidden="true">zipfelfolio · {@user.email}</span>
      </button>
      <ul id="side-menu" class="dropdown-menu" data-bs-popper="static">
        <li>
          <.link class="dropdown-item" navigate={~p"/users/settings" <> "#passkeys"}>
            <.icon name="key" />Passkeys
          </.link>
        </li>
        <li>
          <.link class="dropdown-item" href={~p"/users/log-out"} method="delete">
            <.icon name="logout" />Abmelden
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp hide_account_menu do
    JS.remove_class("show", to: "#side-menu")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#side-me")
  end

  attr :sidebar, :map, required: true
  attr :current, :any, required: true

  # Each portfolio with its reference account indented below, then the accounts of no portfolio;
  # the totals add up to net worth.
  defp side_money(assigns) do
    ~H"""
    <div :if={@sidebar.portfolios != []} id="side-portfolios" class="app-side-h">
      <span>Depots</span><span>{Format.amount(total(@sidebar.portfolios))}</span>
    </div>
    <nav :if={@sidebar.portfolios != []} class="nav flex-column" aria-label="Depots">
      <%= for row <- @sidebar.portfolios do %>
        <.money_link
          id={"side-portfolio-#{row.portfolio.id}"}
          navigate={Sidebar.portfolio_path(row.portfolio)}
          name={row.portfolio.name}
          value={row.value}
          active={@current == {:holdings, row.portfolio.id, nil}}
        >
          <.chip portfolio={row.portfolio} />
        </.money_link>
        <.money_link
          :if={row.account}
          id={"side-account-#{row.account.account.id}"}
          class="app-sub"
          navigate={Sidebar.account_path(row.portfolio, row.account.account)}
          name={row.account.account.name}
          value={row.account.value}
          active={@current == {:holdings, row.portfolio.id, row.account.account.id}}
        >
          <.icon name="wallet" />
        </.money_link>
      <% end %>
    </nav>
    <div :if={@sidebar.accounts != []} id="side-accounts" class="app-side-h">
      <span>Konten</span><span>{Format.amount(total(@sidebar.accounts))}</span>
    </div>
    <nav :if={@sidebar.accounts != []} class="nav flex-column" aria-label="Konten">
      <.money_link
        :for={row <- @sidebar.accounts}
        id={"side-account-#{row.account.id}"}
        navigate={Sidebar.account_path(nil, row.account)}
        name={row.account.name}
        value={row.value}
        active={@current == {:holdings, nil, row.account.id}}
      >
        <.wallet_chip />
      </.money_link>
    </nav>
    """
  end

  @doc "The sum of the `value`s of `rows`, e.g. of a group of portfolios."
  def total(rows), do: Enum.sum_by(rows, & &1.value)

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :current, :any, required: true
  attr :open, :any, required: true, doc: "what the link opens, as `current` names it"
  attr :badge, :integer, default: 0, doc: "the recognised receipts in the inbox, shown unless 0"
  slot :inner_block, required: true

  # In the rail only the icon shows; the name stays for screen readers and shows in a flyout.
  defp side_link(assigns) do
    assigns = assign(assigns, :active, assigns.current == assigns.open)

    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={["nav-link", @active && "active"]}
      aria-current={@active && "page"}
    >
      <.icon name={@icon} />
      <span class="app-side-text">{render_slot(@inner_block)}</span>
      <.inbox_badge count={@badge} />
      <span class="app-fly" aria-hidden="true">
        {render_slot(@inner_block)}<span :if={@badge > 0}>{@badge} im Eingang</span>
      </span>
    </.link>
    """
  end

  attr :count, :integer, required: true

  defp inbox_badge(assigns) do
    ~H"""
    <span :if={@count > 0} class="badge rounded-pill text-bg-warning app-inbox-badge">
      <span class="visually-hidden">im Eingang: </span>{@count}
    </span>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :name, :string, required: true
  attr :value, :integer, required: true
  attr :active, :boolean, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true, doc: "the chip or icon"

  defp money_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={["nav-link app-acc", @class, @active && "active"]}
      aria-current={@active && "page"}
    >
      {render_slot(@inner_block)}
      <span class="app-acc-name">{@name}</span>
      <span class={["app-bal", amount_tone(@value)]}>{Format.amount(@value)}</span>
      <span class="app-fly" aria-hidden="true">
        {@name} <span>{Format.amount(@value)}&nbsp;€</span>
      </span>
    </.link>
    """
  end

  defp amount_tone(value) when value < 0, do: "is-neg"
  defp amount_tone(0), do: "is-zero"
  defp amount_tone(_value), do: nil

  # Felt colours that keep the white initial readable; by id, so that a portfolio keeps its tone.
  @chip_tones ~w(denim moss plum petrol indigo tomato)

  attr :portfolio, :map, required: true

  @doc "A portfolio's chip: a filled square with its initial."
  def chip(assigns) do
    tone = Enum.at(@chip_tones, rem(assigns.portfolio.id - 1, length(@chip_tones)))
    assigns = assign(assigns, :style, "--chip: var(--felt-#{tone})")

    ~H"""
    <span class="app-chip" style={@style} aria-hidden="true">{initial(@portfolio.name)}</span>
    """
  end

  attr :portfolios, :list, required: true
  attr :portfolio, :any, required: true, doc: "the one shown, nil for all"
  attr :path, :any, required: true, doc: "the page for a portfolio's id, nil for all"

  @doc """
  A menu to show all portfolios or one; a Bootstrap dropdown without Bootstrap's JS, which
  LiveView's JS commands toggle.
  """
  def portfolio_switcher(assigns) do
    ~H"""
    <div
      class="dropdown"
      phx-click-away={hide_portfolio_menu()}
      phx-window-keydown={hide_portfolio_menu()}
      phx-key="Escape"
    >
      <button
        id="portfolio-menu-toggle"
        type="button"
        class="btn btn-sm btn-light dropdown-toggle"
        aria-expanded="false"
        aria-controls="portfolio-menu"
        phx-click={
          JS.toggle_class("show", to: "#portfolio-menu")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
      >
        {if @portfolio, do: @portfolio.name, else: "Gesamt"}
      </button>
      <ul id="portfolio-menu" class="dropdown-menu dropdown-menu-end" data-bs-popper="static">
        <li>
          <.portfolio_menu_item patch={@path.(nil)} active={!@portfolio}>
            Gesamt
          </.portfolio_menu_item>
        </li>
        <li :if={@portfolios != []}><hr class="dropdown-divider" /></li>
        <li :for={portfolio <- @portfolios}>
          <.portfolio_menu_item
            patch={@path.(portfolio.id)}
            active={@portfolio && @portfolio.id == portfolio.id}
          >
            <.chip portfolio={portfolio} />{portfolio.name}
          </.portfolio_menu_item>
        </li>
      </ul>
    </div>
    """
  end

  attr :patch, :string, required: true
  attr :active, :boolean, required: true
  slot :inner_block, required: true

  defp portfolio_menu_item(assigns) do
    ~H"""
    <.link
      patch={@patch}
      class={["dropdown-item d-flex align-items-center gap-2", @active && "active"]}
      aria-current={@active && "page"}
      phx-click={hide_portfolio_menu()}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp hide_portfolio_menu do
    JS.remove_class("show", to: "#portfolio-menu")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#portfolio-menu-toggle")
  end

  @doc "The chip of an account of no portfolio: an outlined square with a wallet."
  def wallet_chip(assigns) do
    ~H"""
    <span class="app-chip app-chip-acc" aria-hidden="true"><.icon name="wallet" /></span>
    """
  end

  attr :class, :string, default: nil

  # The bare mark: a rising line with the arrowhead in mustard.
  defp logo(assigns) do
    ~H"""
    <svg class={["app-side-logo", @class]} viewBox="10 12 44 44" aria-hidden="true">
      <path d="M14 44l12-12 8 8 16-16" stroke="currentColor" />
      <path d="M40 24h10v10" stroke="#e0a224" />
    </svg>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, required: true
  attr :badge, :integer, default: 0
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <li class="nav-item">
      <.link
        id={@id}
        navigate={@navigate}
        class={[
          "nav-link d-flex flex-column align-items-center position-relative",
          @active && "active"
        ]}
        aria-current={@active && "page"}
      >
        <.icon name={@icon} />
        <small>{render_slot(@inner_block)}</small>
        <.inbox_badge count={@badge} />
      </.link>
    </li>
    """
  end

  defp initial(name), do: String.upcase(String.first(name) || "")

  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc "Sign-in pages: a narrow column without navigation."
  def auth(assigns) do
    ~H"""
    <main class="container px-3 py-5 app-auth" id="main">
      <h1 class="h3 fw-bold text-center mb-4">zipfelfolio</h1>
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end
end
