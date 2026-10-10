defmodule Zipfelfolio.Repo.Migrations.CreateCompositions do
  use Ecto.Migration

  def change do
    create table(:compositions) do
      add :security_id, references(:securities, on_delete: :delete_all), null: false
      add :countries, :map, null: false
      add :sectors, :map, null: false
      add :fetched_at, :utc_datetime_usec, null: false
    end

    create unique_index(:compositions, [:security_id])
  end
end
