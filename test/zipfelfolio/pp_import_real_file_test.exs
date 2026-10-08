defmodule Zipfelfolio.PPImportRealFileTest do
  @moduledoc """
  Imports the owner's real PP file: `PP_FILE=/path/to/file.portfolio mix test --only pp_file`.
  Asserts invariants only, so no real numbers end up in the repository.
  """
  use Zipfelfolio.DataCase

  import Zipfelfolio.UsersFixtures

  alias Zipfelfolio.{Portfolios, PPImport}
  alias Zipfelfolio.PPImport.Reader

  @moduletag :pp_file
  @moduletag timeout: :infinity

  setup do
    path = System.fetch_env!("PP_FILE")
    {:ok, client} = Reader.read(path)
    %{scope: user_scope_fixture(), client: client, path: path}
  end

  test "imports every transaction with complete sides, and a second import changes nothing",
       %{scope: scope, client: client, path: path} do
    assert {:ok, _summary} = PPImport.run(scope, path)

    transactions = Portfolios.list_transactions(scope)
    assert length(transactions) == length(client.transactions)

    assert Enum.sum_by(transactions, &length(&1.units)) ==
             Enum.sum_by(client.transactions, &length(&1.units))

    for t <- transactions do
      case t.type do
        type when type in [:buy, :sell] ->
          assert t.portfolio_id && t.account_id && t.security_id, inspect(t)

        :security_transfer ->
          assert t.portfolio_id && t.other_portfolio_id, inspect(t)

        :cash_transfer ->
          assert t.account_id && t.other_account_id, inspect(t)

        type when type in [:inbound_delivery, :outbound_delivery] ->
          assert t.portfolio_id, inspect(t)

        _ ->
          assert t.account_id, inspect(t)
      end
    end

    assert {:ok, summary} = PPImport.run(scope, path)

    assert Enum.all?(summary, fn {_kind, counts} -> Enum.all?(counts, &(elem(&1, 1) == 0)) end),
           inspect(summary)
  end
end
