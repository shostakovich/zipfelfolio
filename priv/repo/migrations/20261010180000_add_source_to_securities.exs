defmodule Zipfelfolio.Repo.Migrations.AddSourceToSecurities do
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add :source, :string, null: false, default: "pp_import"
    end
  end
end
