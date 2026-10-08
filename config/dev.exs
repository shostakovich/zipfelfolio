import Config

config :zipfelfolio, Zipfelfolio.Repo,
  database: Path.expand("../storage/development.sqlite3", __DIR__),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :zipfelfolio, ZipfelfolioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "LskGY5/9tttiiNgHNnTehHMtdpAwqP7TysuHPsLz5alTW9d1NZgzzS5t2HPoka81",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:zipfelfolio, ~w(--sourcemap=inline --watch)]},
    esbuild_css: {Esbuild, :install_and_run, [:zipfelfolio_css, ~w(--sourcemap=inline --watch)]}
  ]

config :zipfelfolio, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
