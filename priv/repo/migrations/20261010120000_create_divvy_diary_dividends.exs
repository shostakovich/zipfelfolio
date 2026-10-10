defmodule Zipfelfolio.Repo.Migrations.CreateDivvyDiaryDividends do
  use Ecto.Migration

  def change do
    create table(:divvy_diary_dividends) do
      add :security_id, references(:securities, on_delete: :delete_all), null: false
      add :ex_date, :date
      add :pay_date, :date, null: false
      add :per_share, :integer, null: false
      add :currency, :string, null: false
      add :fetched_at, :utc_datetime_usec, null: false
    end

    create index(:divvy_diary_dividends, [:security_id, :pay_date])
  end
end
