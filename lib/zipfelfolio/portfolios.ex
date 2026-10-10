defmodule Zipfelfolio.Portfolios do
  @moduledoc """
  Portfolios, accounts, their transactions and savings plans, each of one user, and what the
  screens show of them: net worth, the overview, the holdings, the dividends, the performance, the
  sidebar and the user's holding of a security, computed from the transactions on every request.
  """

  import Ecto.Query, warn: false

  alias Zipfelfolio.{
    Allocation,
    Costs,
    Distributions,
    Dividends,
    ExchangeRates,
    Performance,
    Period,
    PriceChart,
    Repo
  }

  alias Zipfelfolio.Allocation.Classifications
  alias Zipfelfolio.Performance.Breakdown
  alias Zipfelfolio.Portfolios.{Account, Portfolio, SavingsPlan, Transaction}
  alias Zipfelfolio.Securities
  alias Zipfelfolio.Securities.Security
  alias Zipfelfolio.Taxonomies
  alias Zipfelfolio.Users.Scope
  alias Zipfelfolio.Valuation
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
    market = load_market(transactions, accounts, Enum.min(dates, Date), :since_first_transaction)

    transactions
    |> Valuation.history(accounts, market, dates)
    |> Map.new(&{&1.date, &1.net_worth})
  end

  @doc """
  What the overview shows for `period` up to `today`, from one load of the user's transactions,
  amounts in euro cents:

  - `net_worth` today and `net_worth_yesterday`
  - `chart`: net worth, invested capital and the value of the shadow portfolio in the benchmark
    (`benchmark`, nil without one) on the days of the period a chart shows, see
    `Performance.shadow_portfolio/4`
  - `ttwror` and `irr` of all portfolios and accounts over the period, see `Performance`
  - `benchmark`: the user's benchmark as `%{security, ttwror}` over the same interval, see
    `Performance.benchmark_ttwror/3`; nil when they picked none
  - `dividends`: this year's up to `today`, before taxes and fees
  - `portfolios`: the portfolios by name, retired ones only while they hold shares, each with
    `account`, its reference account as in the sidebar (nil when an earlier one settles against
    it too, or once it is retired and empty), its `balance` in euros, the number of `securities`
    held, the `value` of the securities and the account, and the `ttwror` of both since 1 January
  """
  def overview(%Scope{} = scope, period, today) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    first_day = first_transaction_day(transactions)
    interval = Period.interval(period, today, first_day)
    year = Period.interval(:year_to_date, today, first_day)
    first = Enum.min([interval.first, year.first], Date)
    benchmark = get_benchmark(scope)

    market =
      load_market(transactions, accounts, first, :since_first_transaction, benchmark: benchmark)

    index = Performance.index(transactions, accounts, market, Filter.all(), interval)
    [yesterday, today_point] = Enum.take(index.days, -2)
    range = Period.range(period, today, first_day)

    %{
      net_worth: today_point.value,
      net_worth_yesterday: yesterday.value,
      chart: chart(index, range, shadow_portfolio(benchmark, index, market, range.first)),
      ttwror: Performance.ttwror(index),
      irr: Performance.irr(index),
      benchmark: benchmark(benchmark, index, market),
      dividends: Valuation.gross_dividends(transactions, market, year_to_date(today)),
      portfolios: portfolios_overview(scope, transactions, accounts, market, year)
    }
  end

  @doc """
  What the performance screen shows for `period` up to `today`, of all portfolios and accounts or
  of the portfolio with `portfolio_id` and its reference account:

  - `portfolios`: the portfolios to choose from, as the holdings screen lists them
  - `portfolio`: the chosen one of them, nil for all
  - `interval`: the days of the period, the first the reference day, see `Period.interval/3`
  - `ttwror`, `ttwror_per_year`, `irr`, `drawdown` and `volatility`, see `Performance`
  - `benchmark`: as in `overview/3`, over the interval
  - `breakdown`: where the change in value came from, see `Performance.Breakdown`
  - `monthly_returns`: the TTWROR of every month and year since the first transaction, whatever
    the period, see `Performance.monthly_returns/1`
  """
  def performance(%Scope{} = scope, period, portfolio_id, today) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    portfolios = shown_portfolios(scope, Valuation.holdings(transactions, today))
    portfolio = Enum.find(portfolios, &(&1.id == portfolio_id))
    first_day = first_transaction_day(transactions)
    interval = Period.interval(period, today, first_day)
    all_time = Period.interval(:max, today, first_day)
    benchmark = get_benchmark(scope)

    market =
      load_market(transactions, accounts, all_time.first, :since_first_transaction,
        benchmark: benchmark
      )

    filter = performance_filter(portfolio, transactions)
    index = Performance.index(transactions, accounts, market, filter, interval)

    all_time_index =
      if interval == all_time,
        do: index,
        else: Performance.index(transactions, accounts, market, filter, all_time)

    %{
      portfolios: portfolios,
      portfolio: portfolio,
      interval: interval,
      ttwror: Performance.ttwror(index),
      ttwror_per_year: Performance.ttwror_per_year(index),
      benchmark: benchmark(benchmark, index, market),
      irr: Performance.irr(index),
      drawdown: Performance.drawdown(index),
      volatility: Performance.volatility(index),
      breakdown: Breakdown.of(transactions, accounts, market, filter, index),
      monthly_returns: Performance.monthly_returns(all_time_index)
    }
  end

  # The security the user compares with, nil for none.
  defp get_benchmark(%Scope{user: %{benchmark_id: nil}}), do: nil

  defp get_benchmark(%Scope{user: %{benchmark_id: id}} = scope),
    do: Securities.get_security(scope, id)

  defp benchmark(nil, _index, _market), do: nil

  defp benchmark(security, index, market),
    do: %{security: security, ttwror: Performance.benchmark_ttwror(index, market, security.id)}

  defp performance_filter(nil, _transactions), do: Filter.all()

  defp performance_filter(portfolio, transactions),
    do: Filter.new([portfolio], List.wrap(portfolio.reference_account_id), transactions)

  defp first_transaction_day([first | _]), do: NaiveDateTime.to_date(first.date_time)
  defp first_transaction_day([]), do: nil

  defp chart(%Performance{days: days}, range, shadow_portfolio) do
    chart_days = range |> Period.chart_days() |> MapSet.new()

    for day <- days,
        MapSet.member?(chart_days, day.date),
        do: %{
          date: day.date,
          net_worth: day.value,
          invested_capital: day.invested_capital,
          benchmark: shadow_portfolio[day.date]
        }
  end

  defp shadow_portfolio(nil, _index, _market, _first_day), do: %{}

  defp shadow_portfolio(security, index, market, first_day),
    do: Performance.shadow_portfolio(index, market, security.id, first_day)

  defp year_to_date(%Date{year: year} = today), do: Date.range(Date.new!(year, 1, 1), today)

  defp portfolios_overview(scope, transactions, accounts, market, %Date.Range{last: today} = year) do
    holdings = Valuation.holdings(transactions, today)
    portfolios = shown_portfolios(scope, holdings)
    owners = reference_account_owners(portfolios)

    rows = %{
      holdings: value_rows(holdings, market, today),
      accounts: account_rows(accounts, Valuation.balances(transactions, today), market, today)
    }

    for %{portfolio: %Portfolio{} = portfolio} = group <- holding_groups(portfolios, nil, rows) do
      # Its reference account counts towards the returns even once it is retired and empty.
      account_ids = for {account_id, owner_id} <- owners, owner_id == portfolio.id, do: account_id
      filter = Filter.new([portfolio], account_ids, transactions)
      index = Performance.index(transactions, accounts, market, filter, year)
      account_row = List.first(group.accounts)

      %{
        portfolio: portfolio,
        account: account_row && account_row.account,
        balance: account_row && account_row.value,
        securities: length(group.holdings),
        value: List.last(index.days).value,
        ttwror: Performance.ttwror(index)
      }
    end
  end

  # Retired portfolios only while they hold shares.
  defp shown_portfolios(scope, holdings) do
    held = MapSet.new(holdings, & &1.portfolio_id)
    Enum.filter(list_portfolios(scope), &(not &1.retired or MapSet.member?(held, &1.id)))
  end

  # The portfolio each reference account of `portfolios` belongs to, as `%{account_id =>
  # portfolio_id}`: an account several of them settle against belongs to the first. The screens
  # list the portfolios by name, so it is the first by name.
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
  - `total`: `value`, `purchase_value` and `gain` of the groups shown, the `dividends` of their
    holdings and the `securities_value` they make up
  - `net_worth`: the value of all holdings and accounts, of which each row shows its share
  - `costs`: what the securities shown cost a year, see `Costs.of/1`; accounts hold no funds
  - `allocation`: the regions and sectors of the securities shown, see `Allocation.of/2`, and in
    `taxonomies` the allocation of the securities and accounts shown into each of the user's
    taxonomies by name, see `Classifications.of/3`, those without value shown in them left out

  A holding has its `security`, `shares`, `price`, `value`, `purchase_value`, `gain` and the gross
  `dividends` of the next 12 months, its part of those of its security (see `Dividends.upcoming/4`)
  by shares; an account has its `value`. Retired accounts are left out once they are empty.
  """
  def holdings(%Scope{} = scope, portfolio_id, today) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    stored = stored_dividends(transactions)
    # Purchase values convert each purchase at the rate of its day.
    market =
      load_market(transactions, accounts, today, :since_first_transaction, dividends: stored)

    holdings = Valuation.holdings(transactions, today)
    portfolios = shown_portfolios(scope, holdings)
    portfolio = Enum.find(portfolios, &(&1.id == portfolio_id))
    upcoming = Dividends.upcoming(transactions, stored, market, today)

    rows = %{
      holdings: holdings |> holding_rows(transactions, market, today) |> with_dividends(upcoming),
      accounts: account_rows(accounts, Valuation.balances(transactions, today), market, today)
    }

    groups = portfolios |> holding_groups(portfolio, rows) |> Enum.map(&with_gains/1)
    shown = Enum.flat_map(groups, & &1.holdings)
    shown_accounts = Enum.flat_map(groups, & &1.accounts)

    %{
      portfolios: portfolios,
      portfolio: portfolio,
      groups: groups,
      total: groups |> totals() |> Map.merge(dividend_totals(shown)),
      net_worth: Enum.sum_by(rows.holdings ++ rows.accounts, & &1.value),
      costs: Costs.of(shown),
      allocation: allocation(scope, shown, shown_accounts)
    }
  end

  defp with_dividends(rows, upcoming) do
    gross = upcoming |> Enum.group_by(& &1.security.id, & &1.gross) |> Map.new(&sum_values/1)
    shares = rows |> Enum.group_by(& &1.security.id, & &1.shares) |> Map.new(&sum_values/1)

    Enum.map(rows, fn row ->
      id = row.security.id
      Map.put(row, :dividends, rounded_part(Map.get(gross, id, 0), row.shares, shares[id]))
    end)
  end

  defp sum_values({key, values}), do: {key, Enum.sum(values)}

  defp rounded_part(cents, part, whole) when whole > 0,
    do: div(cents * part * 2 + whole, whole * 2)

  defp rounded_part(_cents, _part, _whole), do: 0

  defp dividend_totals(holdings) do
    %{
      dividends: Enum.sum_by(holdings, & &1.dividends),
      securities_value: Enum.sum_by(holdings, & &1.value)
    }
  end

  defp allocation(scope, holdings, accounts) do
    compositions =
      holdings |> Enum.map(& &1.security.id) |> Enum.uniq() |> Securities.list_compositions()

    taxonomies =
      for taxonomy <- Taxonomies.list_taxonomies(scope),
          allocation = Classifications.of(taxonomy, holdings, accounts),
          allocation.classifications != [],
          do: allocation

    holdings |> Allocation.of(compositions) |> Map.put(:taxonomies, taxonomies)
  end

  @doc """
  What the dividend screen shows on `today`, amounts in euro cents:

  - `received`: every dividend booked, newest first, see `Dividends.received/2`
  - `years`: the dividends per month and year since the first, see `Dividends.by_year/2`
  - `this_year` up to `today` and `last_year` in all, each as `gross` and `net`
  - `upcoming`: the dividends announced or forecast for the coming months, see
    `Dividends.upcoming/4`, with their `total` and per month in `months`, see
    `Dividends.by_coming_month/2`
  - `value` and `purchase_value` of all holdings today, for the yields
  """
  def dividends(%Scope{} = scope, %Date{} = today) do
    transactions = list_transactions(scope)
    stored = stored_dividends(transactions)

    market =
      load_market(transactions, list_accounts(scope), today, :since_first_transaction,
        dividends: stored
      )

    received = Dividends.received(transactions, market)
    upcoming = Dividends.upcoming(transactions, stored, market, today, received)

    holdings =
      transactions |> Valuation.holdings(today) |> holding_rows(transactions, market, today)

    last_year = Date.range(Date.new!(today.year - 1, 1, 1), Date.new!(today.year - 1, 12, 31))

    %{
      received: received,
      years: Dividends.by_year(received, today),
      this_year: Dividends.total(received, year_to_date(today)),
      last_year: Dividends.total(received, last_year),
      upcoming: upcoming,
      total: Dividends.total(upcoming),
      months: Dividends.by_coming_month(upcoming, today),
      value: Enum.sum_by(holdings, & &1.value),
      purchase_value: Enum.sum_by(holdings, & &1.purchase_value)
    }
  end

  @doc """
  The dividends the overview expects after `today`, gross, see `Dividends.upcoming/4`:

  - `upcoming`: all of them, by pay date
  - `rest_of_year`: the total of those paid this year
  - `next_three_months`: those of today's month and the next two
  """
  def upcoming_dividends(%Scope{} = scope, %Date{} = today) do
    transactions = list_transactions(scope)
    stored = stored_dividends(transactions)

    market =
      load_market(transactions, list_accounts(scope), today, :since_first_transaction,
        dividends: stored
      )

    upcoming = Dividends.upcoming(transactions, stored, market, today)
    three_months = today |> Date.beginning_of_month() |> Date.shift(month: 3)

    %{
      upcoming: upcoming,
      rest_of_year:
        upcoming |> Enum.filter(&(&1.pay_date.year == today.year)) |> Enum.sum_by(& &1.gross),
      next_three_months: Enum.filter(upcoming, &Date.before?(&1.pay_date, three_months))
    }
  end

  defp stored_dividends(transactions) do
    transactions
    |> Enum.map(& &1.security_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Securities.list_divvy_diary_dividends()
  end

  @doc """
  What the security page shows of `security` on `today`; amounts in euro cents, prices × 10⁸ in
  the security's currency, shares × 10⁸. The security and its prices are shared by all users,
  the holdings and trades are the user's:

  - `price` today and `price_yesterday`, nil without any price
  - `chart`: see `PriceChart.of/4`, over the days of `period` from the first price or trade on
  - `holdings`: the holdings of it by portfolio name, each with its `portfolio`, `shares`,
    `value`, `purchase_value` and `gain`
  - `total`: the `shares`, `value`, `purchase_value` and `gain` of all holdings
  - `costs_per_year` of the holdings, see `Costs.of/1`
  - `distributions`: from the user's dividends, see `Distributions.of/3`
  - `upcoming`: the dividends expected of it, see `Dividends.upcoming/4`
  """
  def security(%Scope{} = scope, %Security{} = security, period, today) do
    transactions = list_transactions_of(scope, security)
    closes = scope |> Securities.list_prices(security) |> Enum.map(&{&1.date, &1.close})
    stored = Securities.list_divvy_diary_dividends([security.id])
    market = security_market(security, closes, transactions, stored, today)
    holdings = security_holdings(scope, transactions, market, today)
    range = Period.range(period, today, first_price_or_trade(security, closes, transactions))

    %{
      price: Market.price(market, security.id, today),
      price_yesterday: Market.price(market, security.id, Date.add(today, -1)),
      chart: PriceChart.of(security, closes, transactions, range),
      holdings: holdings,
      total: holdings |> totals() |> Map.put(:shares, Enum.sum_by(holdings, & &1.shares)),
      costs_per_year: Costs.of(holdings).per_year,
      distributions: Distributions.of(security, transactions, market),
      upcoming: Dividends.upcoming(transactions, stored, market, today)
    }
  end

  defp list_transactions_of(scope, %Security{id: security_id}) do
    Repo.all(
      from t in Transaction,
        where: t.user_id == ^scope.user.id and t.security_id == ^security_id,
        order_by: [t.date_time, t.id],
        preload: :units
    )
  end

  # Purchase values convert each purchase at the rate of its day.
  defp security_market(security, closes, transactions, dividends, today) do
    currencies =
      [security | transactions ++ dividends]
      |> Enum.map(& &1.currency)
      |> Market.rate_currencies()

    Market.new(
      [security],
      Enum.map(closes, fn {date, close} -> {security.id, date, close} end),
      ExchangeRates.list_rates_since(currencies, first_day(transactions, today))
    )
  end

  defp security_holdings(scope, transactions, market, today) do
    portfolios = Map.new(list_portfolios(scope), &{&1.id, &1})

    transactions
    |> Valuation.holdings(today)
    |> holding_rows(transactions, market, today)
    |> Enum.map(&Map.put(&1, :portfolio, portfolios[&1.portfolio_id]))
    |> Enum.sort_by(& &1.portfolio.name)
  end

  # Closes and transactions come in order of date; the latest quote may be all there is.
  defp first_price_or_trade(security, closes, transactions) do
    [
      Enum.map(Enum.take(closes, 1), &elem(&1, 0)),
      List.wrap(security.latest_date),
      Enum.map(Enum.take(transactions, 1), &NaiveDateTime.to_date(&1.date_time))
    ]
    |> Enum.concat()
    |> Enum.min(Date, fn -> nil end)
  end

  @doc """
  What the sidebar shows on `today`, valued as the holdings screen values all portfolios, amounts
  in euro cents:

  - `portfolios`: the portfolios by name, retired ones only while they hold shares, each with its
    `value` (its securities and its reference account) and its reference `account` as
    `%{account: account, value: cents}`, nil when it has none or an earlier one settles against
    it too
  - `accounts`: the accounts of no portfolio as `%{account: account, value: cents}`, retired ones
    only while they hold money
  """
  def sidebar(%Scope{} = scope, today) do
    transactions = list_transactions(scope)
    accounts = list_accounts(scope)
    market = load_market(transactions, accounts, today, :since_date)
    holdings = Valuation.holdings(transactions, today)

    rows = %{
      holdings: value_rows(holdings, market, today),
      accounts: account_rows(accounts, Valuation.balances(transactions, today), market, today)
    }

    {portfolio_groups, account_groups} =
      scope
      |> shown_portfolios(holdings)
      |> holding_groups(nil, rows)
      |> Enum.split_with(& &1.portfolio)

    %{
      portfolios:
        Enum.map(portfolio_groups, fn group ->
          %{portfolio: group.portfolio, value: group.value, account: List.first(group.accounts)}
        end),
      accounts: Enum.flat_map(account_groups, & &1.accounts)
    }
  end

  # The value of each holding, without the price and purchase value the holdings screen shows.
  defp value_rows(holdings, market, today) do
    for holding <- holdings,
        do: %{portfolio_id: holding.portfolio_id, value: Valuation.value(holding, market, today)}
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

  # Each portfolio with its holdings and its reference account, then the accounts of no portfolio
  # in a group without portfolio; or the one `portfolio` with its reference account, even if an
  # earlier one settles against it too. Each group has the `value` of its rows.
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
      accounts -> groups ++ [group(nil, [], accounts)]
    end
  end

  defp holding_group(portfolio, rows, account?) do
    group(
      portfolio,
      Enum.filter(rows.holdings, &(&1.portfolio_id == portfolio.id)),
      Enum.filter(rows.accounts, &account?.(&1.account))
    )
  end

  defp group(portfolio, holdings, accounts) do
    %{
      portfolio: portfolio,
      holdings: holdings,
      accounts: accounts,
      value: Enum.sum_by(holdings ++ accounts, & &1.value)
    }
  end

  # The holdings by value, and the purchase value and gain of the group.
  defp with_gains(%{holdings: holdings} = group) do
    Map.merge(group, %{
      holdings: Enum.sort_by(holdings, &{-&1.value, &1.security.name}),
      purchase_value: Enum.sum_by(holdings, & &1.purchase_value),
      gain: Enum.sum_by(holdings, & &1.gain)
    })
  end

  defp totals(rows) do
    %{
      value: Enum.sum_by(rows, & &1.value),
      purchase_value: Enum.sum_by(rows, & &1.purchase_value),
      gain: Enum.sum_by(rows, & &1.gain)
    }
  end

  # The securities of the transactions, and the `:benchmark` if given, with their closes from
  # `date` on, and the rates of every currency involved, those of the `:dividends` too, from `date`
  # on, or from the first transaction on, at which invested capital and purchase values convert.
  defp load_market(transactions, accounts, date, rates, opts \\ []) do
    benchmark = opts[:benchmark]
    dividends = Keyword.get(opts, :dividends, [])

    security_ids =
      transactions
      |> Enum.map(& &1.security_id)
      |> Enum.concat(List.wrap(benchmark && benchmark.id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    securities = Securities.list_securities_by_id(security_ids)

    currencies =
      (accounts ++ securities ++ transactions ++ dividends)
      |> Enum.map(& &1.currency)
      |> Market.rate_currencies()

    rates_from =
      case rates do
        :since_date -> date
        :since_first_transaction -> first_day(transactions, date)
      end

    Market.new(
      securities,
      Securities.list_closes_since(security_ids, date),
      ExchangeRates.list_rates_since(currencies, rates_from)
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
