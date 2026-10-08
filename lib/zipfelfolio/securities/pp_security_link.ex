defmodule Zipfelfolio.Securities.PPSecurityLink do
  @moduledoc """
  Which security a user's PP file means by a PP UUID. Securities are shared, the UUIDs are per
  file, so a re-import finds its securities through these links.
  """
  use Zipfelfolio.Schema

  schema "pp_security_links" do
    belongs_to :user, Zipfelfolio.Users.User
    belongs_to :security, Zipfelfolio.Securities.Security
    field :pp_uuid, :string

    timestamps()
  end
end
