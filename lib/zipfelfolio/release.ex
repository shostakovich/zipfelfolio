defmodule Zipfelfolio.Release do
  @moduledoc "Tasks run from the release, where Mix is not available."

  @app :zipfelfolio

  # A second connection would race the first to switch an empty file to WAL.
  @repo_opts [pool_size: 1]

  def migrate do
    Application.ensure_loaded(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true), @repo_opts)
    end

    :ok
  end

  @doc "Creates a user who then signs in with a link sent by email."
  def create_user(email) do
    Application.ensure_loaded(@app)

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(
        Zipfelfolio.Repo,
        fn _repo -> Zipfelfolio.Users.create_user(%{email: email}) end,
        @repo_opts
      )

    case result do
      {:ok, user} ->
        IO.puts("Created #{user.email}; the sign-in page sends them a link.")

      {:error, changeset} ->
        IO.puts(:stderr, "Could not create #{email}: #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end
end
