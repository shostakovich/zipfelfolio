defmodule Zipfelfolio.Repo.Migrations.AddRecognitionToReceipts do
  use Ecto.Migration

  def change do
    # Receipts so far were attached to a transaction when it was booked.
    alter table(:receipts) do
      add :status, :string, null: false, default: "booked"
      add :text, :text
      add :fields, :map
      add :checks, :map
      add :bank_reference, :string
    end

    create index(:receipts, [:user_id, :status])
    create index(:receipts, [:user_id, :bank_reference])
  end
end
