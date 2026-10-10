defmodule Zipfelfolio.Valuation do
  @moduledoc """
  Holdings, account balances and net worth on a date, computed from transactions and a `Market`
  on every request (ADR 0002). Pure, without the database, and computed as PP does so that the
  figures match PP's. Amounts in cents, shares and prices × 10⁸.
  """

  alias Zipfelfolio.Portfolios.Transaction
  alias Zipfelfolio.Valuation.{Holding, Market}

  @credits [:deposit, :sell, :dividend, :interest, :tax_refund, :fee_refund]
  @debits [:removal, :buy, :interest_charge, :tax, :fee]
  @purchases [:buy, :inbound_delivery]

  # PP multiplies shares and price to ten significant digits.
  @pp_math %Decimal.Context{precision: 10, rounding: :half_up}

  @doc "The holdings on `date` per portfolio and security; holdings without shares are left out."
  def holdings(transactions, date), do: transactions |> share_movements(date) |> to_holdings()

  # One holding per security over all portfolios, as PP values net worth.
  defp joint_holdings(transactions, date) do
    transactions
    |> share_movements(date)
    |> Enum.map(fn {_portfolio_id, shares, t} -> {nil, shares, t} end)
    |> to_holdings()
  end

  defp to_holdings(movements) do
    movements
    |> Enum.group_by(fn {portfolio_id, _shares, t} -> {portfolio_id, t.security_id} end)
    |> Enum.map(fn {{portfolio_id, security_id}, movements} ->
      %Holding{
        portfolio_id: portfolio_id,
        security_id: security_id,
        shares: Enum.sum_by(movements, &elem(&1, 1)),
        transactions: Enum.map(movements, &elem(&1, 2))
      }
    end)
    |> Enum.reject(&(&1.shares == 0))
  end

  # `{portfolio_id, shares, transaction}` for every change of shares up to `date`.
  defp share_movements(transactions, date) do
    for t <- transactions, on_or_before?(t, date), {portfolio_id, shares} <- shares_moved(t) do
      {portfolio_id, shares, t}
    end
  end

  defp shares_moved(%Transaction{type: type} = t) when type in @purchases,
    do: [{t.portfolio_id, t.shares}]

  defp shares_moved(%Transaction{type: type} = t) when type in [:sell, :outbound_delivery],
    do: [{t.portfolio_id, -t.shares}]

  defp shares_moved(%Transaction{type: :security_transfer} = t),
    do: [{t.portfolio_id, -t.shares}, {t.other_portfolio_id, t.shares}]

  defp shares_moved(_transaction), do: []

  @doc "The balance of each account on `date`, in the account's currency."
  def balances(transactions, date) do
    for t <- transactions,
        on_or_before?(t, date),
        {account_id, amount} <- cash_moved(t),
        reduce: %{} do
      balances -> Map.update(balances, account_id, amount, &(&1 + amount))
    end
  end

  defp cash_moved(%Transaction{account_id: nil}), do: []

  defp cash_moved(%Transaction{type: type} = t) when type in @credits,
    do: [{t.account_id, t.amount}]

  defp cash_moved(%Transaction{type: type} = t) when type in @debits,
    do: [{t.account_id, -t.amount}]

  defp cash_moved(%Transaction{type: :cash_transfer} = t),
    do: [{t.account_id, -t.amount}, {t.other_account_id, t |> received() |> elem(0)}]

  defp cash_moved(_transaction), do: []

  @doc """
  What a cash transfer credits the other account, as `{amount, currency}`: into another currency
  the converted gross value, as PP books it.
  """
  def received(%Transaction{} = t) do
    case gross_value_unit(t) do
      %{fx_amount: amount, fx_currency: currency} when is_integer(amount) -> {amount, currency}
      _same_currency -> {t.amount, t.currency}
    end
  end

  defp on_or_before?(%Transaction{date_time: date_time}, date),
    do: not Date.after?(NaiveDateTime.to_date(date_time), date)

  @doc """
  The value of a holding on `date`, in euro cents. Without any price, PP takes the gross price per
  share of the holding's last transaction.
  """
  def value(%Holding{} = holding, %Market{} = market, date) do
    currency = Market.currency(market, holding.security_id)
    price = Market.price(market, holding.security_id, date) || last_price(holding, currency)

    Market.to_euros(market, amount(holding.shares, price || 0), currency, date)
  end

  # Shares × price in cents of the security's currency, as PP rounds it.
  defp amount(shares, price) do
    shares = Decimal.div(shares, 100_000_000)

    @pp_math
    |> Decimal.Context.with(fn -> Decimal.mult(shares, price) end)
    |> Decimal.div(1_000_000)
    |> Decimal.round(0, :half_up)
    |> Decimal.to_integer()
  end

  defp last_price(%Holding{transactions: []}, _currency), do: nil

  defp last_price(%Holding{transactions: transactions}, currency) do
    %Transaction{shares: shares} = last = Enum.max_by(transactions, & &1.date_time, NaiveDateTime)

    case gross_value(last, currency) do
      gross when is_integer(gross) and shares > 0 ->
        @pp_math
        |> Decimal.Context.with(fn -> Decimal.div(gross * 100_000_000_000_000, shares) end)
        |> Decimal.round(0, :half_even)
        |> Decimal.to_integer()

      _unknown ->
        nil
    end
  end

  # Before fees and taxes, in the security's currency.
  defp gross_value(%Transaction{currency: currency} = t, currency) do
    fees_and_taxes =
      t.units |> Enum.filter(&(&1.type in [:fee, :tax])) |> Enum.sum_by(& &1.amount)

    if t.type in @purchases, do: t.amount - fees_and_taxes, else: t.amount + fees_and_taxes
  end

  defp gross_value(t, currency) do
    case gross_value_unit(t) do
      %{fx_currency: ^currency, fx_amount: fx_amount} -> fx_amount
      _other -> nil
    end
  end

  defp gross_value_unit(t), do: Enum.find(t.units, &(&1.type == :gross_value))

  @doc """
  The value of all holdings plus the account balances on `date`, in euro cents. `accounts` give the
  currency of each balance.
  """
  def net_worth(transactions, accounts, %Market{} = market, date) do
    currencies = Map.new(accounts, &{&1.id, &1.currency})

    balances =
      transactions
      |> balances(date)
      |> Enum.map(fn {id, amount} -> Market.to_euros(market, amount, currencies[id], date) end)

    values = transactions |> joint_holdings(date) |> Enum.map(&value(&1, market, date))

    Enum.sum(balances) + Enum.sum(values)
  end
end
