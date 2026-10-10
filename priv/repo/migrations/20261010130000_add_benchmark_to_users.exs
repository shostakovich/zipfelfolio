defmodule Zipfelfolio.Repo.Migrations.AddBenchmarkToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :benchmark_id, references(:securities, on_delete: :nilify_all)
    end
  end
end
