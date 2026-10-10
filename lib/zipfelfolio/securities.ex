defmodule Zipfelfolio.Securities do
  @moduledoc """
  Securities, their prices, compositions and attribute types. They are shared by all users, so
  every signed-in user may read and change them; the scope only says who is asking.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Zipfelfolio.{Allocation, LocalTime, Repo}
  alias Zipfelfolio.Securities.{AttributeType, Composition, Price, Security}
  alias Zipfelfolio.Users.Scope

  def list_securities(%Scope{}),
    do: Repo.all(from s in Security, order_by: [s.retired, fragment("? COLLATE NOCASE", s.name)])

  @doc "The security with `id`, nil for an unknown one."
  def get_security(%Scope{}, id), do: Repo.get(Security, id)

  def list_prices(%Scope{}, %Security{id: id}),
    do: Repo.all(from p in Price, where: p.security_id == ^id, order_by: p.date)

  @doc "The securities whose prices come from Yahoo, without retired ones."
  def list_yahoo_securities do
    Repo.all(
      from s in Security, where: s.quote_feed == :yahoo and not s.retired, order_by: s.name
    )
  end

  @doc """
  Claims the Yahoo securities not checked since `cutoff` by marking them checked at `now`, in one
  statement, so that pages opened at the same time fetch each quote once.
  """
  def claim_unchecked_yahoo_securities(cutoff, now) do
    {_count, securities} =
      Repo.update_all(
        from(s in Security,
          where: s.quote_feed == :yahoo and not s.retired,
          where: is_nil(s.checked_at) or s.checked_at < ^cutoff,
          select: s
        ),
        set: [checked_at: now]
      )

    securities
  end

  @doc """
  Sets where prices come from; a later PP import keeps this choice. A switch to Yahoo or a new
  Yahoo symbol drops the Yahoo prices and the quote of the old one, a switch to manual keeps them.
  """
  def update_quote_feed(%Scope{}, %Security{} = security, attrs) do
    changeset = Security.quote_feed_changeset(security, attrs)
    new_source? = changed?(changeset, :quote_feed) or changed?(changeset, :symbol)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset) do
        {:ok, maybe_drop_yahoo_prices(updated, new_source?)}
      end
    end)
  end

  defp maybe_drop_yahoo_prices(%Security{quote_feed: :yahoo} = security, true = _new_source) do
    Repo.delete_all(from p in Price, where: p.security_id == ^security.id and p.source == :yahoo)

    security
    |> change(latest_at: nil, latest_date: nil, latest_close: nil)
    |> change(fetched_at: nil, checked_at: nil, fetch_error: nil)
    |> Repo.update!()
  end

  defp maybe_drop_yahoo_prices(security, _new_source), do: security

  @doc """
  Calls `fun` with the current security if it still takes its prices from the Yahoo symbol of
  `security`, so a fetch never stores what an old symbol delivered; returns `:skipped` otherwise.
  """
  def with_same_yahoo_symbol(%Security{id: id, symbol: symbol}, fun) do
    {:ok, result} =
      Repo.transact(fn ->
        case Repo.get(Security, id) do
          %Security{quote_feed: :yahoo, retired: false, symbol: ^symbol} = current ->
            {:ok, fun.(current)}

          _changed ->
            {:ok, :skipped}
        end
      end)

    result
  end

  def list_securities_by_id(ids), do: Repo.all(from s in Security, where: s.id in ^ids)

  @doc """
  The closes of the securities as `{security_id, date, close}` from the last one on or before
  `date` on, so that every day from `date` on finds its price; all of them when none is that old.
  """
  def list_closes_since(security_ids, date) do
    last_on_or_before =
      from q in Price,
        where: q.security_id == parent_as(:security).id and q.date <= ^date,
        select: max(q.date)

    # Per security a range of the index on security and date, instead of a check of every close.
    Repo.all(
      from s in Security,
        as: :security,
        join: p in Price,
        on: p.security_id == s.id,
        where: s.id in ^security_ids,
        where: p.date >= coalesce(subquery(last_on_or_before), ^~D[0001-01-01]),
        select: {p.security_id, p.date, p.close}
    )
  end

  def last_price_date(%Security{id: id}),
    do: Repo.one(from p in Price, where: p.security_id == ^id, select: max(p.date))

  @doc "Stores `{date, close}` from Yahoo; days with a price from PP or a manual one keep it."
  def store_yahoo_prices(%Security{id: id}, closes) do
    # The source check sits in the upsert itself, so a price PP or a person stores meanwhile wins.
    only_over_yahoo =
      from p in Price,
        where: p.source == :yahoo,
        update: [set: [close: fragment("EXCLUDED.close")]]

    closes
    |> Enum.map(fn {date, close} ->
      %{security_id: id, date: date, close: close, source: :yahoo}
    end)
    |> Enum.chunk_every(5000)
    |> Enum.each(
      &Repo.insert_all(Price, &1,
        on_conflict: only_over_yahoo,
        conflict_target: [:security_id, :date]
      )
    )
  end

  @doc "Records a successful fetch with the latest quote."
  def record_quote(%Security{} = security, quote, now) do
    security
    |> change(
      latest_at: quote.at,
      latest_date: quote.date,
      latest_close: quote.close,
      fetched_at: now,
      checked_at: now,
      fetch_error: nil
    )
    |> Repo.update!()
  end

  def record_fetch_error(%Security{} = security, message, now),
    do: security |> change(fetch_error: message, checked_at: now) |> Repo.update!()

  ## Manual prices

  def list_manual_prices(%Scope{}, %Security{id: id}) do
    Repo.all(
      from p in Price,
        where: p.security_id == ^id and p.source == :manual,
        order_by: [desc: p.date]
    )
  end

  @doc "A form for a manual price: a day up to today and a price, in German or English notation."
  def change_manual_price(%Security{} = security, attrs \\ %{}) do
    attrs = Map.update(attrs, "close", nil, &normalize_number/1)

    {%{}, %{date: :date, close: :decimal}}
    |> cast(attrs, [:date, :close])
    |> validate_required([:date, :close])
    |> validate_number(:close, greater_than: 0, less_than: 1_000_000_000)
    |> validate_not_in_future()
    |> validate_no_pp_price(security)
  end

  # "1.234,56" and "1234.56" both mean 1234.56.
  defp normalize_number(nil), do: nil

  defp normalize_number(text) do
    if String.contains?(text, ","),
      do: text |> String.replace(".", "") |> String.replace(",", "."),
      else: text
  end

  defp validate_not_in_future(changeset) do
    date = get_field(changeset, :date)

    if date && Date.after?(date, LocalTime.today()),
      do: add_error(changeset, :date, "darf nicht in der Zukunft liegen"),
      else: changeset
  end

  defp validate_no_pp_price(changeset, security) do
    date = get_field(changeset, :date)

    if date &&
         Repo.exists?(
           from p in Price,
             where: p.security_id == ^security.id and p.date == ^date and p.source == :pp
         ),
       do: add_error(changeset, :date, "hat schon einen Kurs aus Portfolio Performance"),
       else: changeset
  end

  @doc """
  Enters a manual price; it replaces one from Yahoo on that day, not one from PP. A security with
  manual prices shows its newest price as the latest quote.
  """
  def add_manual_price(%Scope{}, %Security{} = security, attrs) do
    not_over_pp =
      from p in Price,
        where: p.source != :pp,
        update: [set: [close: fragment("EXCLUDED.close"), source: fragment("EXCLUDED.source")]]

    with {:ok, %{date: date, close: close}} <-
           security |> change_manual_price(attrs) |> apply_action(:insert),
         {:ok, price} <-
           Repo.insert(
             %Price{
               security_id: security.id,
               date: date,
               close: to_price(close),
               source: :manual
             },
             on_conflict: not_over_pp,
             conflict_target: [:security_id, :date]
           ) do
      update_manual_quote(security)
      {:ok, price}
    end
  end

  defp to_price(decimal),
    do: decimal |> Decimal.mult(100_000_000) |> Decimal.round(0) |> Decimal.to_integer()

  @doc "Deletes a manual price and returns it, so a Yahoo security can fetch that day again."
  def delete_manual_price(%Scope{}, %Security{id: id} = security, price_id) do
    case Repo.get_by(Price, id: price_id, security_id: id, source: :manual) do
      nil ->
        {:error, :not_found}

      price ->
        Repo.delete!(price)
        update_manual_quote(security)
        {:ok, price}
    end
  end

  defp update_manual_quote(%Security{quote_feed: :manual} = security) do
    newest =
      Repo.one(
        from p in Price,
          where: p.security_id == ^security.id,
          order_by: [desc: p.date],
          limit: 1
      )

    security
    |> change(
      latest_at: nil,
      latest_date: newest && newest.date,
      latest_close: newest && newest.close
    )
    |> Repo.update!()
  end

  defp update_manual_quote(security), do: security

  ## Compositions

  @doc "The securities DivvyDiary may know: those with an ISIN, without retired ones."
  def list_securities_with_isin do
    Repo.all(
      from s in Security,
        where: not is_nil(s.isin) and s.isin != "" and not s.retired,
        order_by: s.name
    )
  end

  @doc "Stores the composition of a security, fetched at `now`, in place of the one before."
  def replace_composition(%Security{id: id}, %{countries: countries, sectors: sectors}, now) do
    Repo.insert!(
      %Composition{security_id: id, countries: countries, sectors: sectors, fetched_at: now},
      on_conflict: {:replace, [:countries, :sectors, :fetched_at]},
      conflict_target: :security_id
    )
  end

  @doc "The compositions of the securities with `ids` as `%{security_id => composition}`."
  def list_compositions(ids) do
    from(c in Composition, where: c.security_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.security_id, &1})
  end

  ## Profile

  @attributes_of_securities "name.abuchen.portfolio.model.Security"

  @doc """
  The profile of `security`:

  - `ter` and `fund_size`, see `Security.ter/1` and `Security.fund_size/1`
  - `attributes`: every other attribute set on it with its type, see `Security.attributes/2`
  - `composition`: its regions and sectors, see `Allocation.of_composition/1`; nil without one
  """
  def profile(%Scope{}, %Security{} = security) do
    types =
      Repo.all(
        from t in AttributeType, where: t.target == @attributes_of_securities, order_by: t.id
      )

    composition = Repo.get_by(Composition, security_id: security.id)

    %{
      ter: Security.ter(security),
      fund_size: Security.fund_size(security),
      attributes: Security.attributes(security, types),
      composition: composition && Allocation.of_composition(composition)
    }
  end
end
