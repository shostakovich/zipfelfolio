import Config

config :zipfelfolio, ZipfelfolioWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :zipfelfolio, forwarded_ssl: true

config :logger, level: :info
