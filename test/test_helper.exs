# Tests against the owner's real PP file run only when the environment gives what they need; their
# moduledocs say how.
exclude =
  [
    pp_file: ~w(PP_FILE),
    pp_net_worth: ~w(PP_FILE PP_NET_WORTH_DATE PP_NET_WORTH),
    pp_dividends: ~w(PP_FILE PP_DIVIDENDS)
  ]
  |> Enum.reject(fn {_tag, variables} -> Enum.all?(variables, &System.get_env/1) end)
  |> Keyword.keys()

ExUnit.start(assert_receive_timeout: 1_000, exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Zipfelfolio.Repo, :manual)
