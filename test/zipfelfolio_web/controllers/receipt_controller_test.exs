defmodule ZipfelfolioWeb.ReceiptControllerTest do
  use ZipfelfolioWeb.ConnCase

  import Zipfelfolio.{PortfoliosFixtures, UsersFixtures}

  alias Zipfelfolio.Portfolios

  @pdf "%PDF-1.4\nBeleg\n%%EOF\n"

  setup :register_and_log_in_user

  setup %{scope: scope} do
    path = Path.join(System.tmp_dir!(), "receipt-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, @pdf)
    on_exit(fn -> File.rm(path) end)

    account = account_fixture(scope)

    params = %{
      "kind" => "deposit",
      "date" => "2026-10-01",
      "amount" => "1",
      "account_id" => account.id
    }

    {:ok, [deposit]} =
      Portfolios.book_transaction(
        scope,
        Portfolios.transaction_choices(scope),
        params,
        {path, "beleg.pdf"}
      )

    %{receipt_id: deposit.receipt_id}
  end

  test "shows the user's receipt inline", %{conn: conn, receipt_id: id} do
    conn = get(conn, ~p"/receipts/#{id}")

    assert response(conn, 200) == @pdf
    assert response_content_type(conn, :pdf) =~ "application/pdf"
    assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="beleg.pdf")]
  end

  test "not another user's receipt", %{receipt_id: id} do
    conn = build_conn() |> log_in_user(user_fixture())
    assert conn |> get(~p"/receipts/#{id}") |> response(404)
    assert build_conn() |> log_in_user(user_fixture()) |> get(~p"/receipts/x") |> response(404)
  end
end
