import Config

config :zipfelfolio, :scopes,
  user: [
    default: true,
    module: Zipfelfolio.Users.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Zipfelfolio.UsersFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :zipfelfolio,
  ecto_repos: [Zipfelfolio.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

config :zipfelfolio, Zipfelfolio.Repo,
  journal_mode: :wal,
  synchronous: :normal,
  foreign_keys: :on,
  busy_timeout: 15_000,
  # A deferred read-then-write fails with SQLITE_BUSY at once; immediate ones wait at BEGIN.
  default_transaction_mode: :immediate,
  pool_size: 5,
  # :serial is AUTOINCREMENT in SQLite, so ids are never reused.
  migration_primary_key: [type: :serial, null: false]

config :zipfelfolio, ZipfelfolioWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ZipfelfolioWeb.ErrorHTML, json: ZipfelfolioWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Zipfelfolio.PubSub,
  live_view: [signing_salt: "nJZKywtH"]

config :phoenix_live_view, root_tag_attribute: "phx-r"

config :zipfelfolio, Zipfelfolio.MarketData,
  price_feed: Zipfelfolio.MarketData.Yahoo,
  rate_source: Zipfelfolio.MarketData.ECB,
  daily_job: true

config :zipfelfolio, Zipfelfolio.Mailer, adapter: Swoosh.Adapters.Local
config :zipfelfolio, :mail_from, {"zipfelfolio", "zipfelfolio@localhost"}
config :swoosh, :api_client, false
config :swoosh, :json_library, JSON

config :esbuild,
  version: "0.25.4",
  zipfelfolio: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  zipfelfolio_css: [
    args: ~w(css/app.css --bundle --outdir=../priv/static/assets/css),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, JSON
config :ecto_sqlite3, json_library: JSON

import_config "#{config_env()}.exs"
