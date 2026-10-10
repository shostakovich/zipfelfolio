defmodule Zipfelfolio.Repo.Migrations.AddPaperless do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :paperless_url, :string
      add :paperless_token, :string
      add :paperless_tag, :string
      add :paperless_polled_at, :utc_datetime_usec
    end

    alter table(:receipts) do
      add :paperless_id, :integer
    end

    create index(:receipts, [:user_id, :paperless_id])
  end
end
