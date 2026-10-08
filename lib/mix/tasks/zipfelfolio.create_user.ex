defmodule Mix.Tasks.Zipfelfolio.CreateUser do
  @shortdoc "Creates a user: mix zipfelfolio.create_user EMAIL"
  @moduledoc """
  Creates a user, who then signs in with a link sent by email.

      mix zipfelfolio.create_user robert@example.com

  In the container: `bin/zipfelfolio eval 'Zipfelfolio.Release.create_user("…")'`.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run([email]) do
    case Zipfelfolio.Accounts.create_user(%{email: email}) do
      {:ok, user} -> Mix.shell().info("Created #{user.email}.")
      {:error, changeset} -> Mix.raise("Could not create #{email}: #{inspect(changeset.errors)}")
    end
  end

  def run(_args), do: Mix.raise("usage: mix zipfelfolio.create_user EMAIL")
end
