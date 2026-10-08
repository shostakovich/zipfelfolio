defmodule Zipfelfolio.Repo do
  use Ecto.Repo,
    otp_app: :zipfelfolio,
    adapter: Ecto.Adapters.SQLite3
end
