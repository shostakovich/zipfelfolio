defmodule Zipfelfolio.Taxonomies.Taxonomy do
  @moduledoc "A user's tree of classifications, such as regions or asset allocation."
  use Zipfelfolio.Schema

  schema "taxonomies" do
    belongs_to :user, Zipfelfolio.Users.User
    field :name, :string
    field :source, :string
    field :dimensions, {:array, :string}, default: []
    field :pp_id, :string

    has_many :classifications, Zipfelfolio.Taxonomies.Classification

    timestamps()
  end
end
