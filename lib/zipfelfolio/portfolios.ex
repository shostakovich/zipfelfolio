defmodule Zipfelfolio.Portfolios do
  @moduledoc "Portfolios, accounts, their transactions and savings plans; each belongs to a user."

  import Ecto.Query, warn: false

  alias Zipfelfolio.Portfolios.{Account, Portfolio, SavingsPlan, Transaction}
  alias Zipfelfolio.Repo
  alias Zipfelfolio.Users.Scope

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

  @doc "Whether the user has transactions that did not come from a PP import."
  def own_transactions?(%Scope{} = scope) do
    Repo.exists?(
      from t in Transaction, where: t.user_id == ^scope.user.id and t.source != :pp_import
    )
  end
end
