defmodule ZipfelfolioWeb.UserLive.ConfirmationTest do
  use ZipfelfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zipfelfolio.UsersFixtures

  alias Zipfelfolio.Users

  setup do
    user = unconfirmed_user_fixture()
    token = extract_user_token(&Users.deliver_login_instructions(user, &1))
    %{user: user, token: token}
  end

  test "signs in and confirms the user once", %{conn: conn, user: user, token: token} do
    {:ok, lv, html} = live(conn, ~p"/users/log-in/#{token}")
    assert html =~ user.email

    form = form(lv, "#login-form", %{"user" => %{"token" => token}})
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Willkommen!"
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
    assert Users.get_user!(user.id).confirmed_at

    {:ok, _lv, html} =
      build_conn()
      |> live(~p"/users/log-in/#{token}")
      |> follow_redirect(build_conn(), ~p"/users/log-in")

    assert html =~ "Der Link ist ungültig oder abgelaufen."
  end

  test "rejects an unknown token", %{conn: conn} do
    {:ok, _lv, html} =
      conn |> live(~p"/users/log-in/invalid") |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "Der Link ist ungültig oder abgelaufen."
  end
end
