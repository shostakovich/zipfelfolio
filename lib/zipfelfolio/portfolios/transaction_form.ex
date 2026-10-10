defmodule Zipfelfolio.Portfolios.TransactionForm do
  @moduledoc """
  A purchase, sale, dividend, deposit or removal as the user enters it, in euros: the checks a
  transaction must pass and the transactions it books (ADR 0001).

  The amount follows shares × price (a dividend's gross value) with fees and taxes until the user
  overwrites it (`amount_set`); `expected_amount` then holds what they give when the amount differs
  by more than a four-decimal price explains. A purchase or sale without an account is an inbound
  or outbound delivery. The price is only an input aid and is not stored.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Zipfelfolio.DecimalInput
  alias Zipfelfolio.LocalTime

  @kinds [:purchase, :sale, :dividend, :deposit, :removal]

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum, values: @kinds, default: :purchase
    field :portfolio_id, :integer
    field :date, :date
    field :security_id, :integer
    field :shares, DecimalInput
    field :price, DecimalInput
    field :gross, DecimalInput
    field :fees, DecimalInput, default: Decimal.new(0)
    field :taxes, DecimalInput, default: Decimal.new(0)
    field :amount, DecimalInput
    field :amount_set, :boolean, default: false
    field :account_id, :integer
    field :remove_at_once, :boolean, default: false
    field :expected_amount, :decimal
  end

  @fields [
    :kind,
    :portfolio_id,
    :date,
    :security_id,
    :shares,
    :price,
    :gross,
    :fees,
    :taxes,
    :amount,
    :amount_set,
    :account_id,
    :remove_at_once
  ]

  # A price rounded to four decimal places is off by at most this much per share.
  @price_rounding Decimal.new("0.00005")
  @cent_rounding Decimal.new("0.005")
  @limit 1_000_000_000

  def kinds, do: @kinds

  @doc """
  Casts and checks `attrs`. `choices` holds the `portfolio_ids`, `account_ids` and
  `security_ids` the user may book on, as sets, and `held_shares`, a function of portfolio id,
  security id and date that gives the shares × 10⁸ held at the end of that day.
  """
  def changeset(%__MODULE__{} = form, attrs, choices) do
    form
    |> cast(attrs, @fields)
    |> zero_when_blank([:fees, :taxes])
    |> validate_required([:kind, :date])
    |> validate_kind()
    |> validate_not_in_future()
    |> validate_choice(:portfolio_id, choices.portfolio_ids)
    |> validate_choice(:account_id, choices.account_ids)
    |> validate_choice(:security_id, choices.security_ids)
    |> validate_number(:fees, greater_than_or_equal_to: 0)
    |> validate_number(:taxes, greater_than_or_equal_to: 0)
    |> validate_places([:fees, :taxes, :gross, :amount], 2)
    |> validate_places([:shares], 8)
    |> validate_below_limit([:shares, :price, :gross, :fees, :taxes])
    |> put_amount()
    |> validate_required([:amount])
    |> validate_number(:amount, greater_than: 0)
    |> validate_below_limit([:amount])
    |> put_expected_amount()
    |> validate_holding(choices.held_shares)
  end

  defp zero_when_blank(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if get_field(changeset, field),
        do: changeset,
        else: put_change(changeset, field, Decimal.new(0))
    end)
  end

  defp validate_kind(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:purchase, :sale] ->
        changeset
        |> validate_required([:portfolio_id, :security_id, :shares, :price])
        |> validate_number(:shares, greater_than: 0)
        |> validate_number(:price, greater_than: 0)

      :dividend ->
        changeset
        |> validate_required([:security_id, :gross, :account_id])
        |> validate_number(:shares, greater_than: 0)
        |> validate_number(:gross, greater_than: 0)

      _deposit_or_removal ->
        validate_required(changeset, [:account_id])
    end
  end

  defp validate_not_in_future(changeset) do
    date = get_field(changeset, :date)

    if date && Date.after?(date, LocalTime.today()),
      do: add_error(changeset, :date, "darf nicht in der Zukunft liegen"),
      else: changeset
  end

  defp validate_choice(changeset, field, ids) do
    validate_change(changeset, field, fn ^field, id ->
      if MapSet.member?(ids, id), do: [], else: [{field, "ist ungültig"}]
    end)
  end

  defp validate_below_limit(changeset, fields) do
    Enum.reduce(fields, changeset, &validate_number(&2, &1, less_than: @limit))
  end

  defp validate_places(changeset, fields, places) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      validate_change(changeset, field, &places_error(&1, &2, places))
    end)
  end

  defp places_error(field, value, places) do
    if Decimal.equal?(value, Decimal.round(value, places)),
      do: [],
      else: [{field, "hat höchstens #{places} Nachkommastellen"}]
  end

  # Until the user overwrites it, the amount follows the other fields; a deposit's or removal's is
  # entered.
  defp put_amount(changeset) do
    entered? =
      get_field(changeset, :kind) in [:deposit, :removal] or
        (get_field(changeset, :amount_set) and get_field(changeset, :amount) != nil)

    if entered?,
      do: changeset,
      else: put_change(changeset, :amount, computed_amount(changeset) |> round_cents())
  end

  defp put_expected_amount(changeset) do
    amount = get_field(changeset, :amount)
    computed = computed_amount(changeset)

    if amount && computed &&
         Decimal.gt?(Decimal.abs(Decimal.sub(amount, computed)), tolerance(changeset)),
       do: put_change(changeset, :expected_amount, round_cents(computed)),
       else: put_change(changeset, :expected_amount, nil)
  end

  # The exact amount the other fields give, nil while one of them is missing.
  defp computed_amount(changeset) do
    fees_and_taxes = Decimal.add(get_field(changeset, :fees), get_field(changeset, :taxes))

    case {get_field(changeset, :kind), gross(changeset)} do
      {_kind, nil} -> nil
      {:purchase, gross} -> Decimal.add(gross, fees_and_taxes)
      {_sale_or_dividend, gross} -> Decimal.sub(gross, fees_and_taxes)
    end
  end

  defp gross(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:purchase, :sale] ->
        shares = get_field(changeset, :shares)
        price = get_field(changeset, :price)
        shares && price && Decimal.mult(shares, price)

      :dividend ->
        get_field(changeset, :gross)

      _deposit_or_removal ->
        nil
    end
  end

  defp tolerance(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:purchase, :sale] ->
        Decimal.add(@cent_rounding, Decimal.mult(get_field(changeset, :shares), @price_rounding))

      _dividend ->
        @cent_rounding
    end
  end

  defp round_cents(nil), do: nil
  defp round_cents(decimal), do: Decimal.round(decimal, 2, :half_up)

  # No sale or outbound delivery beyond the shares held on its day.
  defp validate_holding(changeset, held_shares) do
    with :sale <- get_field(changeset, :kind),
         [] <- changeset.errors,
         held =
           held_shares.(
             fetch!(changeset, :portfolio_id),
             fetch!(changeset, :security_id),
             fetch!(changeset, :date)
           ),
         true <- shares(fetch!(changeset, :shares)) > held do
      add_error(changeset, :shares, "übersteigt den Bestand von %{held} Stück",
        held: format_shares(held)
      )
    else
      _fine -> changeset
    end
  end

  defp fetch!(changeset, field), do: fetch_field!(changeset, field)

  defp format_shares(shares) do
    shares
    |> Decimal.div(100_000_000)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end

  @doc """
  The attributes of the transactions a valid form books, without user and receipt: one, or for
  a dividend removed at once a second, independent removal of its amount.
  """
  def to_transactions(%__MODULE__{} = form) do
    transaction = transaction(form)

    if form.kind == :dividend and form.remove_at_once,
      do: [transaction, removal_of(transaction)],
      else: [transaction]
  end

  defp transaction(form) do
    %{
      type: type(form.kind, form.account_id),
      date_time: NaiveDateTime.new!(form.date, ~T[00:00:00]),
      portfolio_id: if(form.kind in [:purchase, :sale], do: form.portfolio_id),
      account_id: form.account_id,
      security_id: if(form.kind in [:purchase, :sale, :dividend], do: form.security_id),
      shares: stored_shares(form),
      amount: cents(form.amount),
      currency: "EUR",
      source: :manual,
      units: units(form)
    }
  end

  defp stored_shares(%__MODULE__{kind: kind, shares: %Decimal{} = shares})
       when kind in [:purchase, :sale, :dividend],
       do: shares(shares)

  defp stored_shares(_form), do: nil

  defp type(:purchase, nil), do: :inbound_delivery
  defp type(:purchase, _account_id), do: :buy
  defp type(:sale, nil), do: :outbound_delivery
  defp type(:sale, _account_id), do: :sell
  defp type(kind, _account_id), do: kind

  defp units(%__MODULE__{kind: kind}) when kind in [:deposit, :removal], do: []

  defp units(form) do
    for {type, value} <- [fee: form.fees, tax: form.taxes], Decimal.positive?(value) do
      %{type: type, amount: cents(value), currency: "EUR"}
    end
  end

  defp removal_of(dividend) do
    %{dividend | type: :removal, security_id: nil, shares: nil, units: []}
  end

  defp shares(decimal), do: decimal |> Decimal.mult(100_000_000) |> Decimal.to_integer()
  defp cents(decimal), do: decimal |> Decimal.mult(100) |> Decimal.to_integer()
end
