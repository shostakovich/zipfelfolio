defmodule Zipfelfolio.Repo.Migrations.CreateMarketData do
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add :latest_at, :utc_datetime_usec
      add :fetched_at, :utc_datetime_usec
      add :checked_at, :utc_datetime_usec
      add :fetch_error, :string
    end

    create table(:exchange_rates) do
      add :currency, :string, null: false
      add :date, :date, null: false
      add :rate, :decimal, null: false
    end

    create unique_index(:exchange_rates, [:currency, :date])

    create table(:job_runs) do
      add :name, :string, null: false
      add :ran_at, :utc_datetime_usec, null: false
      add :error, :string
    end

    create unique_index(:job_runs, [:name])
  end
end
