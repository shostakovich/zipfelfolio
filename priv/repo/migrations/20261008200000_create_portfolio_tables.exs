defmodule Zipfelfolio.Repo.Migrations.CreatePortfolioTables do
  use Ecto.Migration

  def change do
    create table(:attribute_types) do
      add :pp_id, :string, null: false
      add :name, :string, null: false
      add :column_label, :string
      add :target, :string
      add :value_type, :string
      add :converter, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:attribute_types, [:pp_id, :target])

    create table(:securities) do
      add :name, :string, null: false
      add :isin, :string
      add :wkn, :string
      add :currency, :string
      add :note, :text
      add :retired, :boolean, null: false, default: false
      add :attributes, :map, null: false, default: %{}
      add :pp_feed, :string
      add :pp_ticker, :string
      add :quote_feed, :string, null: false, default: "manual"
      add :symbol, :string
      add :quote_feed_set_by_user, :boolean, null: false, default: false
      add :latest_date, :date
      add :latest_close, :integer

      timestamps(type: :utc_datetime_usec)
    end

    # Not unique: a PP file may hold the same ISIN twice (other exchange or currency).
    create index(:securities, [:isin])

    create table(:pp_security_links) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :security_id, references(:securities, on_delete: :delete_all), null: false
      add :pp_uuid, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:pp_security_links, [:user_id, :pp_uuid])
    create index(:pp_security_links, [:security_id])

    create table(:prices) do
      add :security_id, references(:securities, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :close, :integer, null: false
      add :source, :string, null: false
    end

    create unique_index(:prices, [:security_id, :date])

    create table(:accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :currency, :string, null: false
      add :note, :text
      add :retired, :boolean, null: false, default: false
      add :attributes, :map, null: false, default: %{}
      add :pp_uuid, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:user_id, :pp_uuid])

    create table(:portfolios) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :reference_account_id, references(:accounts, on_delete: :nilify_all)
      add :name, :string, null: false
      add :note, :text
      add :retired, :boolean, null: false, default: false
      add :attributes, :map, null: false, default: %{}
      add :pp_uuid, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:portfolios, [:user_id, :pp_uuid])

    create table(:transactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :date_time, :naive_datetime, null: false
      add :portfolio_id, references(:portfolios, on_delete: :delete_all)
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :other_portfolio_id, references(:portfolios, on_delete: :delete_all)
      add :other_account_id, references(:accounts, on_delete: :delete_all)
      add :security_id, references(:securities, on_delete: :restrict)
      add :shares, :integer
      add :amount, :integer, null: false
      add :currency, :string, null: false
      add :ex_date, :naive_datetime
      add :note, :text
      add :source, :string, null: false
      add :pp_uuid, :string
      add :pp_other_uuid, :string
      add :pp_source, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:transactions, [:user_id, :pp_uuid])
    create index(:transactions, [:portfolio_id])
    create index(:transactions, [:account_id])
    create index(:transactions, [:security_id])

    create table(:transaction_units) do
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :amount, :integer, null: false
      add :currency, :string, null: false
      add :fx_amount, :integer
      add :fx_currency, :string
      add :fx_rate, :decimal
    end

    create index(:transaction_units, [:transaction_id])

    create table(:savings_plans) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :note, :text
      add :type, :string, null: false
      add :security_id, references(:securities, on_delete: :restrict)
      add :portfolio_id, references(:portfolios, on_delete: :delete_all)
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :auto_generate, :boolean, null: false, default: false
      add :start, :date, null: false
      add :interval, :integer, null: false
      add :amount, :integer, null: false
      add :fees, :integer, null: false, default: 0
      add :taxes, :integer, null: false, default: 0
      add :attributes, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:savings_plans, [:user_id])

    create table(:savings_plan_transactions, primary_key: false) do
      add :savings_plan_id, references(:savings_plans, on_delete: :delete_all), null: false
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
    end

    create unique_index(:savings_plan_transactions, [:savings_plan_id, :transaction_id])

    create table(:taxonomies) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :source, :string
      add :dimensions, {:array, :string}, null: false, default: []
      add :pp_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:taxonomies, [:user_id, :pp_id])

    create table(:classifications) do
      add :taxonomy_id, references(:taxonomies, on_delete: :delete_all), null: false
      add :parent_id, references(:classifications, on_delete: :delete_all)
      add :name, :string, null: false
      add :note, :text
      add :color, :string
      add :weight, :integer, null: false
      add :rank, :integer, null: false, default: 0
      add :pp_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:classifications, [:taxonomy_id, :pp_id])
    create index(:classifications, [:parent_id])

    create table(:assignments) do
      add :classification_id, references(:classifications, on_delete: :delete_all), null: false
      add :security_id, references(:securities, on_delete: :delete_all)

      add :account_id, references(:accounts, on_delete: :delete_all),
        check: %{
          name: "security_or_account",
          expr: "(security_id IS NULL) <> (account_id IS NULL)"
        }

      add :weight, :integer, null: false
      add :rank, :integer, null: false, default: 0
    end

    create index(:assignments, [:classification_id])
  end
end
