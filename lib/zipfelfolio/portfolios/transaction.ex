defmodule Zipfelfolio.Portfolios.Transaction do
  @moduledoc """
  One business event with a portfolio side, an account side or both (ADR 0001). A buy has a
  portfolio and an account; a security transfer goes from `portfolio` to `other_portfolio`, a cash
  transfer from `account` to `other_account`. Amounts in cents, shares × 10⁸. `source` says where
  it came from: a PP import replaces only its own transactions.
  """
  use Zipfelfolio.Schema

  alias Zipfelfolio.Portfolios.{Account, Portfolio, TransactionUnit}

  @types [
    :buy,
    :sell,
    :inbound_delivery,
    :outbound_delivery,
    :security_transfer,
    :cash_transfer,
    :deposit,
    :removal,
    :dividend,
    :interest,
    :interest_charge,
    :tax,
    :tax_refund,
    :fee,
    :fee_refund
  ]

  schema "transactions" do
    belongs_to :user, Zipfelfolio.Users.User
    field :type, Ecto.Enum, values: @types
    field :date_time, :naive_datetime
    belongs_to :portfolio, Portfolio
    belongs_to :account, Account
    belongs_to :other_portfolio, Portfolio
    belongs_to :other_account, Account
    belongs_to :security, Zipfelfolio.Securities.Security
    field :shares, :integer
    field :amount, :integer
    field :currency, :string
    field :ex_date, :naive_datetime
    field :note, :string
    field :source, Ecto.Enum, values: [:pp_import, :manual, :receipt]
    field :pp_uuid, :string
    field :pp_other_uuid, :string
    field :pp_source, :string
    belongs_to :receipt, Zipfelfolio.Portfolios.Receipt

    has_many :units, TransactionUnit

    timestamps()
  end

  def types, do: @types
end
