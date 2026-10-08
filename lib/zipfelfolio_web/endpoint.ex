defmodule ZipfelfolioWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :zipfelfolio

  @session_options [
    store: :cookie,
    key: "_zipfelfolio_key",
    signing_salt: "xa+VTJb9",
    same_site: "Lax"
  ]

  if Application.compile_env(:zipfelfolio, :forwarded_ssl, false) do
    plug ZipfelfolioWeb.ForwardedSSL
  end

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :zipfelfolio,
    gzip: not code_reloading?,
    only: ZipfelfolioWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :zipfelfolio
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ZipfelfolioWeb.Router
end
