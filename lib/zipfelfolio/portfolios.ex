defmodule Zipfelfolio.Portfolios do
  @moduledoc "Portfolios, accounts, their transactions and savings plans; each belongs to a user."

  import Ecto.Query, warn: false

  alias Zipfelfolio.{ExchangeRates, Repo, Securities, Valuation}
  alias Zipfelfolio.Portfolios.{Account, Portfolio, SavingsPlan, Transaction}
  alias Zipfelfolio.Users.Scope
  alias Zipfelfolio.Valuation.Market

  def list_portfolios(%Scope{} = scope),
    do: Repo.all(from p in Portfolio, where: p.user_id == ^scope.user.id, order_by: p.name)

  def list_accounts(%Scope{} = scope),
    do: Repo.all(from a in Account, where: a.user_id == ^scope.user.id, order_by: a.name)

  def list_transactions(%Scope{} = scope) do
    Repo.all(
      from t in Transaction,
        where: t.user_id == ^scope.user.id,
        order_by: [t.date_time, t.id],
        preload: :units
    )
  end

  def list_savings_plans(%Scope{} = scope) do
    Repo.all(
      from p in SavingsPlan,
        where: p.user_id == ^scope.user.id,
        order_by: p.name,
        preload: :transactions
    )
  end

  @doc """
  The user's net worth on each of `dates` as `%{date => cents}`: the value of all holdings plus
  the account balances, in euros.
  """
  def net_worth(%Scope{} = scope, dates) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    market = load_market(transactions, accounts, Enum.min(dates, Date))

    Map.new(dates, &{&1, Valuation.net_worth(transactions, accounts, market, &1)})
  end

  # The securities of the transactions with their prices from `date` on, and the rates they need.
  defp load_market(transactions, accounts, date) do
    security_ids =
      transactions |> Enum.map(& &1.security_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    securities = Securities.list_securities_by_id(security_ids)

    currencies =
      Enum.uniq(Enum.map(accounts, & &1.currency) ++ Enum.map(securities, & &1.currency))

    Market.new(
      securities,
      Securities.list_closes_since(security_ids, date),
      ExchangeRates.list_rates_since(currencies, date)
    )
  end

  @doc "Whether the user has transactions that did not come from a PP import."
  def own_transactions?(%Scope{} = scope) do
    Repo.exists?(
      from t in Transaction, where: t.user_id == ^scope.user.id and t.source != :pp_import
    )
  end
end
