defmodule ZipfelfolioWeb.ImportLiveTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Zipfelfolio.Portfolios

  setup :register_and_log_in_user

  defp upload(lv, name, content) do
    lv
    |> file_input("#import-form", :pp_file, [%{name: name, content: content}])
    |> render_upload(name)

    lv |> form("#import-form") |> render_submit()
  end

  test "imports an uploaded PP file and shows what changed", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/settings/import")

    html = upload(lv, "sample.portfolio", File.read!("test/fixtures/pp/sample.portfolio"))

    assert html =~ "Import abgeschlossen."
    assert lv |> element("#summary-transactions") |> render() =~ "21"
    assert length(Portfolios.list_portfolios(scope)) == 2
  end

  test "explains why a file cannot be imported", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/import")

    html = upload(lv, "notes.portfolio", "no zip")

    assert html =~ "keine (unverschlüsselte) Datei aus Portfolio Performance"
    refute has_element?(lv, "#import-summary")
  end

  test "ignores a submit without a finished upload", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/import")

    lv |> form("#import-form") |> render_submit()

    refute has_element?(lv, "#import-summary")
  end

  test "is linked from the settings", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert {:ok, _lv, html} =
             lv
             |> element("#import a", "PP-Datei importieren")
             |> render_click()
             |> follow_redirect(conn)

    assert html =~ "Import aus Portfolio Performance"
  end
end
