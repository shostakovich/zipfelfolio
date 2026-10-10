defmodule ZipfelfolioWeb.Router do
  use ZipfelfolioWeb, :router

  import ZipfelfolioWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ZipfelfolioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # JSON for the passkey hooks; same session and CSRF protection as the pages.
  pipeline :browser_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  scope "/", ZipfelfolioWeb do
    get "/up", HealthController, :show
  end

  scope "/", ZipfelfolioWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {ZipfelfolioWeb.UserAuth, :require_authenticated},
        ZipfelfolioWeb.Sidebar,
        ZipfelfolioWeb.TransactionDialog
      ] do
      live "/", OverviewLive
      live "/holdings", HoldingsLive
      live "/dividends", DividendsLive
      live "/portfolios", PortfoliosLive
      live "/securities/:id", SecurityLive
      live "/settings/import", ImportLive
      live "/settings/securities", SecuritiesLive
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", ZipfelfolioWeb do
    pipe_through [:browser_json, :require_authenticated_user]

    post "/users/settings/passkeys/options", PasskeyController, :registration_options
    post "/users/settings/passkeys", PasskeyController, :create
  end

  scope "/", ZipfelfolioWeb do
    pipe_through :browser_json

    post "/users/passkeys/options", PasskeyController, :authentication_options
  end

  scope "/", ZipfelfolioWeb do
    pipe_through :browser

    live_session :current_user,
      on_mount: [{ZipfelfolioWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:zipfelfolio, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
