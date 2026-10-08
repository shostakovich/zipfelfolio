defmodule ZipfelfolioWeb.Layouts do
  @moduledoc false
  use ZipfelfolioWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current, :atom, default: nil, doc: "the active navigation item"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2" href="#main">Zum Inhalt springen</a>

    <nav class="navbar navbar-expand-lg sticky-top d-none d-lg-flex mb-4" aria-label="Hauptnavigation">
      <div class="container">
        <.link class="navbar-brand fw-bold" navigate={~p"/"}>zipfelfolio</.link>
        <ul class="navbar-nav me-auto">
          <li class="nav-item">
            <.link
              class={["nav-link", @current == :overview && "active"]}
              aria-current={@current == :overview && "page"}
              navigate={~p"/"}
            >
              Übersicht
            </.link>
          </li>
        </ul>
        <.avatar user={@current_scope.user} active={@current == :settings} />
      </div>
    </nav>

    <header class="d-flex d-lg-none align-items-center gap-2 px-3 pt-3 pb-2">
      <.link class="fw-bold fs-5 text-decoration-none text-body me-auto" navigate={~p"/"}>
        zipfelfolio
      </.link>
      <.avatar user={@current_scope.user} active={@current == :settings} />
    </header>

    <main class="container pb-5" id="main">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  attr :user, :map, required: true
  attr :active, :boolean, default: false

  defp avatar(assigns) do
    ~H"""
    <.link
      navigate={~p"/users/settings"}
      class="app-avatar rounded-circle text-bg-primary d-flex align-items-center justify-content-center fw-bold text-decoration-none"
      aria-label={"Einstellungen (#{@user.email})"}
      aria-current={@active && "page"}
    >
      {@user.email |> String.first() |> String.upcase()}
    </.link>
    """
  end

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
