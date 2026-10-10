defmodule Zipfelfolio.Portfolios do
  @moduledoc "Portfolios, accounts, their transactions and savings plans; each belongs to a user."

  import Ecto.Query, warn: false

  alias Zipfelfolio.{ExchangeRates, Performance, Period, Repo, Securities, Valuation}
  alias Zipfelfolio.Portfolios.{Account, Portfolio, SavingsPlan, Transaction}
  alias Zipfelfolio.Users.Scope
  alias Zipfelfolio.Valuation.{Filter, Market, PurchaseValue}

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

    transactions
    |> Valuation.history(accounts, market, dates)
    |> Map.new(&{&1.date, &1.net_worth})
  end

  @doc """
  What the overview shows for `period` up to `today`, from one load of the user's transactions,
  amounts in euro cents:

  - `net_worth` today and `net_worth_yesterday`
  - `chart`: net worth and invested capital on the days of the period a chart shows
  - `ttwror` and `irr` of all portfolios and accounts over the period, see `Performance`
  - `dividends`: this year's up to `today`, before taxes and fees
  - `portfolios`: the portfolios by name, retired ones only while they hold shares, each with
    `account`, its reference account unless an earlier one settles against it too (as in the
    sidebar), its `balance` in euros, the number of `securities` held, the `value` of the
    securities and the account, and the `ttwror` of both since 1 January
  """
  def overview(%Scope{} = scope, period, today) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    first_day = first_transaction_day(transactions)
    interval = Period.interval(period, today, first_day)
    year = Period.interval(:year_to_date, today, first_day)
    market = load_market(transactions, accounts, Enum.min([interval.first, year.first], Date))
    index = Performance.index(transactions, accounts, market, Filter.all(), interval)
    [yesterday, today_point] = Enum.take(index.days, -2)

    %{
      net_worth: today_point.value,
      net_worth_yesterday: yesterday.value,
      chart: chart(index, Period.range(period, today, first_day)),
      ttwror: Performance.ttwror(index),
      irr: Performance.irr(index),
      dividends: Valuation.gross_dividends(transactions, market, year_to_date(today)),
      portfolios: portfolios_overview(scope, transactions, accounts, market, year)
    }
  end

  defp first_transaction_day([first | _]), do: NaiveDateTime.to_date(first.date_time)
  defp first_transaction_day([]), do: nil

  defp chart(%Performance{days: days}, range) do
    chart_days = range |> Period.chart_days() |> MapSet.new()

    for day <- days,
        MapSet.member?(chart_days, day.date),
        do: %{date: day.date, net_worth: day.value, invested_capital: day.invested_capital}
  end

  defp year_to_date(%Date{year: year} = today), do: Date.range(Date.new!(year, 1, 1), today)

  defp portfolios_overview(scope, transactions, accounts, market, %Date.Range{last: today} = year) do
    holdings = Valuation.holdings(transactions, today)
    securities = Enum.frequencies_by(holdings, & &1.portfolio_id)
    portfolios = shown_portfolios(scope, holdings)
    owners = reference_account_owners(portfolios)
    balances = Valuation.balances(transactions, today)

    for portfolio <- portfolios do
      account = Enum.find(accounts, &(owners[&1.id] == portfolio.id))
      filter = Filter.new([portfolio], List.wrap(account && account.id), transactions)
      index = Performance.index(transactions, accounts, market, filter, year)

      %{
        portfolio: portfolio,
        account: account,
        balance: balance(account, balances, market, today),
        securities: Map.get(securities, portfolio.id, 0),
        value: List.last(index.days).value,
        ttwror: Performance.ttwror(index)
      }
    end
  end

  defp balance(nil, _balances, _market, _today), do: nil

  defp balance(account, balances, market, today),
    do: Market.to_euros(market, Map.get(balances, account.id, 0), account.currency, today)

  # Retired portfolios only while they hold shares.
  defp shown_portfolios(scope, holdings) do
    held = MapSet.new(holdings, & &1.portfolio_id)
    Enum.filter(list_portfolios(scope), &(not &1.retired or MapSet.member?(held, &1.id)))
  end

  # An account several portfolios settle against belongs to the first of them.
  defp reference_account_owners(portfolios) do
    for %{reference_account_id: account_id, id: id} <- Enum.reverse(portfolios),
        account_id != nil,
        into: %{},
        do: {account_id, id}
  end

  @doc """
  What the holdings screen shows on `today` for all portfolios, or for the one with
  `portfolio_id`; amounts in euro cents, prices × 10⁸ in the security's currency:

  - `portfolios`: the portfolios to choose from by name, retired ones only while they hold shares
  - `portfolio`: the chosen one of them, nil for all
  - `groups`: each portfolio shown with its `holdings` by value and its reference account in
    `accounts`. For all portfolios, an account several settle against appears under the first
    (as in the overview), and the accounts of no portfolio follow in a group without portfolio.
    Each group has the `value` of its rows and the `purchase_value` and `gain` of its holdings.
  - `total`: `value`, `purchase_value` and `gain` of the groups shown
  - `net_worth`: the value of all holdings and accounts, of which each row shows its share

  A holding has its `security`, `shares`, `price`, `value`, `purchase_value` and `gain`, an
  account its `value`. Retired accounts are left out once they are empty.
  """
  def holdings(%Scope{} = scope, portfolio_id, today) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    market = load_market(transactions, accounts, today)
    holdings = Valuation.holdings(transactions, today)
    portfolios = shown_portfolios(scope, holdings)
    portfolio = Enum.find(portfolios, &(&1.id == portfolio_id))

    rows = %{
      holdings: holding_rows(holdings, transactions, market, today),
      accounts: account_rows(accounts, Valuation.balances(transactions, today), market, today)
    }

    groups = holding_groups(portfolios, portfolio, rows)

    %{
      portfolios: portfolios,
      portfolio: portfolio,
      groups: groups,
      total: totals(groups, groups),
      net_worth: Enum.sum_by(rows.holdings ++ rows.accounts, & &1.value)
    }
  end

  defp holding_rows(holdings, transactions, market, today) do
    purchase_values = PurchaseValue.by_holding(transactions, market, today)

    for holding <- holdings do
      value = Valuation.value(holding, market, today)
      purchase_value = Map.get(purchase_values, {holding.portfolio_id, holding.security_id}, 0)

      %{
        portfolio_id: holding.portfolio_id,
        security: Market.security(market, holding.security_id),
        shares: holding.shares,
        price: Valuation.price(holding, market, today),
        value: value,
        purchase_value: purchase_value,
        gain: value - purchase_value
      }
    end
  end

  defp account_rows(accounts, balances, market, today) do
    for account <- accounts,
        balance = Map.get(balances, account.id, 0),
        not account.retired or balance != 0,
        do: %{account: account, value: Market.to_euros(market, balance, account.currency, today)}
  end

  # One portfolio with its reference account, even if an earlier one settles against it too.
  defp holding_groups(_portfolios, %Portfolio{} = portfolio, rows),
    do: [holding_group(portfolio, rows, &(&1.id == portfolio.reference_account_id))]

  defp holding_groups(portfolios, nil, rows) do
    owners = reference_account_owners(portfolios)

    groups =
      Enum.map(portfolios, fn portfolio ->
        holding_group(portfolio, rows, &(owners[&1.id] == portfolio.id))
      end)

    case Enum.reject(rows.accounts, &Map.has_key?(owners, &1.account.id)) do
      [] -> groups
      accounts -> groups ++ [with_totals(%{portfolio: nil, holdings: [], accounts: accounts})]
    end
  end

  defp holding_group(portfolio, rows, account?) do
    with_totals(%{
      portfolio: portfolio,
      holdings:
        rows.holdings
        |> Enum.filter(&(&1.portfolio_id == portfolio.id))
        |> Enum.sort_by(&{-&1.value, &1.security.name}),
      accounts: Enum.filter(rows.accounts, &account?.(&1.account))
    })
  end

  defp with_totals(%{holdings: holdings, accounts: accounts} = group),
    do: Map.merge(group, totals(holdings ++ accounts, holdings))

  # The value of `rows`, and the purchase value and gain of `holdings`.
  defp totals(rows, holdings) do
    %{
      value: Enum.sum_by(rows, & &1.value),
      purchase_value: Enum.sum_by(holdings, & &1.purchase_value),
      gain: Enum.sum_by(holdings, & &1.gain)
    }
  end

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

  @doc "Whether the user has transactions that did not come from a PP import."
  def own_transactions?(%Scope{} = scope) do
    Repo.exists?(
      from t in Transaction, where: t.user_id == ^scope.user.id and t.source != :pp_import
    )
  end
end
