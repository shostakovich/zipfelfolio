defmodule Zipfelfolio.Portfolios.Receipt do
  @moduledoc """
  A bank's PDF for a transaction. The file is stored once, named by its SHA-256, in the receipts
  directory next to the database; a user's transactions with the same file share one record.
  """
  use Zipfelfolio.Schema

  schema "receipts" do
    belongs_to :user, Zipfelfolio.Users.User
    field :sha256, :string
    field :filename, :string
    field :byte_size, :integer

    timestamps()
  end
end
