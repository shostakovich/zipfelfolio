defmodule Zipfelfolio.Taxonomies.Classification do
  @moduledoc "A node of a taxonomy; `weight` is the target share of its parent in 1/100 percent."
  use Zipfelfolio.Schema

  schema "classifications" do
    belongs_to :taxonomy, Zipfelfolio.Taxonomies.Taxonomy
    belongs_to :parent, __MODULE__
    field :name, :string
    field :note, :string
    field :color, :string
    field :weight, :integer
    field :rank, :integer, default: 0
    field :pp_id, :string

    has_many :assignments, Zipfelfolio.Taxonomies.Assignment

    timestamps()
  end
end
