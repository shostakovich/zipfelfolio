defmodule ZipfelfolioWeb.UserLive.SettingsTest do
  use ZipfelfolioWeb.ConnCase

  alias Zipfelfolio.Users
  import Phoenix.LiveViewTest
  import Zipfelfolio.UsersFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "E-Mail ändern"
      assert html =~ "Passkey hinzufügen"
      refute html =~ "Passwort"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "Bitte melde dich an."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "Bitte melde dich für diese Änderung erneut an."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email-form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "Wir haben einen Bestätigungslink"
      assert Users.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email-form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "E-Mail ändern"
      assert result =~ "braucht ein @ und keine Leerzeichen"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email-form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "E-Mail ändern"
      assert result =~ "ist unverändert"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Users.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Die E-Mail-Adresse ist geändert."
      refute Users.get_user_by_email(user.email)
      assert Users.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Der Link ist ungültig oder abgelaufen."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Der Link ist ungültig oder abgelaufen."
      assert Users.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "Bitte melde dich an."
    end
  end

  describe "passkeys" do
    setup :register_and_log_in_user

    test "lists, refreshes and deletes the user's passkeys", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Noch kein Passkey hinterlegt."
      assert has_element?(lv, "#passkey-register[phx-hook=PasskeyRegister]")

      passkey = passkey_fixture(user)
      html = render_hook(lv, "passkey_registered", %{})
      assert html =~ "Passkey hinzugefügt."
      assert has_element?(lv, "#passkey-#{passkey.id}", "Testgerät")

      lv |> element("#passkey-#{passkey.id} button", "Löschen") |> render_click()
      refute has_element?(lv, "#passkey-#{passkey.id}")
      assert Zipfelfolio.Users.list_passkeys(user) == []
    end

    test "cannot delete another user's passkey", %{conn: conn} do
      passkey = passkey_fixture(user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert render_click(lv, "delete_passkey", %{"id" => passkey.id}) =~
               "Den Passkey gibt es nicht mehr."

      assert Zipfelfolio.Repo.get(Zipfelfolio.Users.Passkey, passkey.id)
    end
  end
end
