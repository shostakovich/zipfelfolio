defmodule Zipfelfolio.Accounts.Scope do
  @moduledoc """
  The caller of a context function: which user is signed in. Portfolios will be scoped by it,
  so a user sees only what they own or what was shared with them.
  """

  alias Zipfelfolio.Accounts.User

  defstruct user: nil

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
