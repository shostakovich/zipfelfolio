# The test against the owner's real PP file runs only with PP_FILE=/path/to/file.portfolio.
exclude = if System.get_env("PP_FILE"), do: [], else: [:pp_file]
ExUnit.start(assert_receive_timeout: 1_000, exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Zipfelfolio.Repo, :manual)
