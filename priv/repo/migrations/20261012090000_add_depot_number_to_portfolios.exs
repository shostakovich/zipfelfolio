defmodule Zipfelfolio.Repo.Migrations.AddDepotNumberToPortfolios do
  use Ecto.Migration

  def change do
    alter table(:portfolios) do
      add :depot_number, :string
    end
  end
end
