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
  The user's net worth and invested capital on each of `dates`, in euro cents and in order of
  date, as `%{date: date, net_worth: cents, invested_capital: cents}`.
  """
  def history(%Scope{} = scope, dates) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    market = load_market(transactions, accounts, Enum.min(dates, Date))

    Valuation.history(transactions, accounts, market, dates)
  end

  @doc """
  The user's net worth on each of `dates` as `%{date => cents}`: the value of all holdings plus
  the account balances, in euros.
  """
  def net_worth(%Scope{} = scope, dates),
    do: scope |> history(dates) |> Map.new(&{&1.date, &1.net_worth})

  # The securities of the transactions with their closes from `date` on, and the rates of every
  # currency involved from the first transaction on, at which invested capital converts.
  defp load_market(transactions, accounts, date) do
    security_ids =
      transactions |> Enum.map(& &1.security_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    securities = Securities.list_securities_by_id(security_ids)

    currencies =
      (accounts ++ securities ++ transactions)
      |> Enum.map(& &1.currency)
      |> Market.rate_currencies()

    Market.new(
      securities,
      Securities.list_closes_since(security_ids, date),
      ExchangeRates.list_rates_since(currencies, first_day(transactions, date))
    )
  end

  # The transactions come in order of time.
  defp first_day([first | _], date),
    do: Enum.min([NaiveDateTime.to_date(first.date_time), date], Date)

  defp first_day([], date), do: date

  @doc "The day of the user's first transaction; nil without any."
  def first_transaction_date(%Scope{} = scope) do
    first =
      Repo.one(
        from t in Transaction,
          where: t.user_id == ^scope.user.id,
          order_by: t.date_time,
          limit: 1,
          select: t.date_time
      )

    first && NaiveDateTime.to_date(first)
  end

  @doc "Whether the user has transactions that did not come from a PP import."
  def own_transactions?(%Scope{} = scope) do
    Repo.exists?(
      from t in Transaction, where: t.user_id == ^scope.user.id and t.source != :pp_import
    )
  end
end
