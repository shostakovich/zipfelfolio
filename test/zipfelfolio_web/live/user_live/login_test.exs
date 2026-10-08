defmodule ZipfelfolioWeb.UserLive.LoginTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.AccountsFixtures

  test "offers a passkey and a magic link, no password or sign-up", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/users/log-in")

    assert has_element?(lv, "#passkey-login[phx-hook=PasskeyLogin]")
    assert has_element?(lv, "#passkey-form[action='/users/log-in']")
    assert has_element?(lv, "#login-form input[type=email]")
    refute html =~ "Passwort"
    refute html =~ "Registrieren"
  end

  test "sends a magic link to a known address", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    {:ok, _lv, html} =
      lv
      |> form("#login-form", user: %{email: user.email})
      |> render_submit()
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "Wenn die Adresse bei uns bekannt ist"

    assert Zipfelfolio.Repo.get_by!(Zipfelfolio.Accounts.UserToken, user_id: user.id).context ==
             "login"
  end

  test "answers the same for an unknown address", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    {:ok, _lv, html} =
      lv
      |> form("#login-form", user: %{email: "unknown@example.com"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "Wenn die Adresse bei uns bekannt ist"
  end

  test "shows passkey errors from the hook", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    assert render_hook(lv, "passkey_error", %{"message" => "Kaputt."}) =~ "Kaputt."
  end

  test "asks a signed-in user to sign in again for sudo mode", %{conn: conn} do
    user = user_fixture()
    {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/users/log-in")

    assert html =~ "Für Änderungen am Konto meldest du dich bitte noch einmal an."
  end
end
