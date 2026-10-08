defmodule Zipfelfolio.Portfolios.Portfolio do
  @moduledoc "A securities account; purchases settle against its reference account by default."
  use Zipfelfolio.Schema

  schema "portfolios" do
    belongs_to :user, Zipfelfolio.Users.User
    belongs_to :reference_account, Zipfelfolio.Portfolios.Account
    field :name, :string
    field :note, :string
    field :retired, :boolean, default: false
    field :attributes, :map, default: %{}
    field :pp_uuid, :string

    timestamps()
  end
end
