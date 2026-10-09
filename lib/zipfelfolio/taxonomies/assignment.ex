defmodule Zipfelfolio.Taxonomies.Assignment do
  @moduledoc "Puts a security or an account into a classification with a weight in 1/100 percent."
  use Zipfelfolio.Schema

  schema "assignments" do
    belongs_to :classification, Zipfelfolio.Taxonomies.Classification
    belongs_to :security, Zipfelfolio.Securities.Security
    belongs_to :account, Zipfelfolio.Portfolios.Account
    field :weight, :integer
    field :rank, :integer, default: 0
  end
end
