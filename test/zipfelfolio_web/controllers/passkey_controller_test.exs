defmodule ZipfelfolioWeb.PasskeyControllerTest do
  use ZipfelfolioWeb.ConnCase

  alias Zipfelfolio.Users
  alias Zipfelfolio.FakeAuthenticator
  alias ZipfelfolioWeb.PasskeyController

  test "the relying party is the endpoint's host and origin" do
    assert PasskeyController.relying_party() == FakeAuthenticator.relying_party()
  end

  test "POST /users/passkeys/options needs no sign-in", %{conn: conn} do
    options = conn |> post(~p"/users/passkeys/options") |> json_response(200)

    assert options["rpId"] == "localhost"
    assert options["allowCredentials"] == []
  end

  describe "registering a passkey" do
    setup :register_and_log_in_user

    test "stores the passkey under its name", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/settings/passkeys/options")
      options = json_response(conn, 200)
      assert options["user"]["id"] == FakeAuthenticator.encode(user.passkey_handle)

      {:ok, challenge} = Base.url_decode64(options["challenge"], padding: false)
      response = FakeAuthenticator.registration(FakeAuthenticator.new(:eddsa), challenge)

      conn =
        conn |> recycle() |> post(~p"/users/settings/passkeys", %{passkey: response, name: "Mac"})

      assert %{"id" => id} = json_response(conn, 200)
      assert [%{id: ^id, name: "Mac", algorithm: -8}] = Users.list_passkeys(user)
    end

    test "fails without a challenge in the session", %{conn: conn, user: user} do
      response = FakeAuthenticator.registration(FakeAuthenticator.new(), "challenge")
      conn = post(conn, ~p"/users/settings/passkeys", %{passkey: response, name: "Mac"})

      assert json_response(conn, 422)["error"] == "Der Passkey konnte nicht geprüft werden."
      assert Users.list_passkeys(user) == []
    end

    test "asks for a name", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/passkeys/options")
      {:ok, challenge} = Base.url_decode64(json_response(conn, 200)["challenge"], padding: false)
      response = FakeAuthenticator.registration(FakeAuthenticator.new(), challenge)

      conn =
        conn |> recycle() |> post(~p"/users/settings/passkeys", %{passkey: response, name: ""})

      assert json_response(conn, 422)["error"] =~ "Namen"
    end

    test "rejects a challenge older than the ceremony timeout", %{conn: conn, user: user} do
      challenge = Zipfelfolio.WebAuthn.new_challenge()
      issued_at = System.system_time(:millisecond) - Zipfelfolio.WebAuthn.timeout_ms() - 1
      response = FakeAuthenticator.registration(FakeAuthenticator.new(), challenge)

      conn =
        conn
        |> init_test_session(%{passkey_registration_challenge: {challenge, issued_at}})
        |> post(~p"/users/settings/passkeys", %{passkey: response, name: "Mac"})

      assert json_response(conn, 422)["error"] == "Der Passkey konnte nicht geprüft werden."
      assert Users.list_passkeys(user) == []
    end

    test "rejects an upload in place of the passkey fields", %{conn: conn} do
      upload = %Plug.Upload{path: __ENV__.file, filename: "passkey.txt"}
      conn = post(conn, ~p"/users/settings/passkeys", %{passkey: upload, name: "Mac"})

      assert json_response(conn, 422)["error"] == "Unvollständige Anfrage."
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(), -11, :minute)
    test "needs a recent sign-in", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/passkeys/options")

      assert json_response(conn, 403)["error"] == "Bitte melde dich erneut an."
    end
  end

  test "registration needs a signed-in user", %{conn: conn} do
    conn = post(conn, ~p"/users/settings/passkeys/options")

    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
