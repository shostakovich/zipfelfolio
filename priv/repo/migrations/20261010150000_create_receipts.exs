defmodule Zipfelfolio.Repo.Migrations.CreateReceipts do
  use Ecto.Migration

  def change do
    create table(:receipts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sha256, :string, null: false
      add :filename, :string, null: false
      add :byte_size, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:receipts, [:user_id, :sha256])

    alter table(:transactions) do
      add :receipt_id, references(:receipts, on_delete: :nilify_all)
    end

    create index(:transactions, [:receipt_id])
  end
end
