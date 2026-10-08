defmodule Zipfelfolio.UsersTest do
  use Zipfelfolio.DataCase

  alias Zipfelfolio.Users

  import Zipfelfolio.UsersFixtures
  alias Zipfelfolio.Users.{Passkey, User, UserToken}
  alias Zipfelfolio.{FakeAuthenticator, WebAuthn}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Users.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Users.get_user_by_email(user.email)
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Users.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Users.get_user!(user.id)
    end
  end

  describe "create_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Users.create_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Users.create_user(%{email: "not valid"})

      assert %{email: ["braucht ein @ und keine Leerzeichen"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Users.create_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Users.create_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Users.create_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "creates an unconfirmed user with a random passkey handle" do
      email = unique_user_email()
      {:ok, user} = Users.create_user(valid_user_attributes(email: " #{email} "))
      assert user.email == email
      assert is_nil(user.confirmed_at)
      assert byte_size(user.passkey_handle) == 16
      refute inspect(user) =~ "passkey_handle: <<"
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Users.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Users.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Users.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Users.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Users.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Users.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Users.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Users.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Users.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Users.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Users.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00.000000Z]])

      assert Users.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Users.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(), -3600)}
      token = Users.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Users.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Users.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Users.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~U[2020-01-01 00:00:00.000000Z]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Users.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Users.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Users.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00.000000Z]])
      refute Users.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Users.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Users.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Users.login_user_by_magic_link(encoded_token)
    end
  end

  describe "passkeys" do
    setup do
      %{
        user: user_fixture(),
        authenticator: FakeAuthenticator.new(),
        rp: FakeAuthenticator.relying_party()
      }
    end

    test "register_passkey/5 stores a verified passkey", %{
      user: user,
      authenticator: authenticator,
      rp: rp
    } do
      challenge = WebAuthn.new_challenge()
      response = FakeAuthenticator.registration(authenticator, challenge)

      assert {:ok, passkey} = Users.register_passkey(user, response, challenge, rp, " iPhone ")
      assert passkey.name == "iPhone"
      assert_received {:email, %{subject: "zipfelfolio: neuer Passkey „iPhone“", to: [{_, to}]}}
      assert to == user.email
      assert passkey.credential_id == authenticator.credential_id
      assert passkey.public_key == authenticator.spki
      assert passkey.algorithm == -7
      assert [%Passkey{id: id}] = Users.list_passkeys(user)
      assert id == passkey.id
    end

    test "register_passkey/5 rejects an unverified passkey or a missing name", %{
      user: user,
      authenticator: authenticator,
      rp: rp
    } do
      challenge = WebAuthn.new_challenge()
      response = FakeAuthenticator.registration(authenticator, challenge)

      assert {:error, :challenge} =
               Users.register_passkey(user, response, WebAuthn.new_challenge(), rp, "iPhone")

      assert {:error, %Ecto.Changeset{}} =
               Users.register_passkey(user, response, challenge, rp, " ")

      assert Users.list_passkeys(user) == []
    end

    test "register_passkey/5 rejects a credential that is already registered", %{
      user: user,
      authenticator: authenticator,
      rp: rp
    } do
      passkey_fixture(user_fixture(), authenticator)
      challenge = WebAuthn.new_challenge()
      response = FakeAuthenticator.registration(authenticator, challenge)

      assert {:error, changeset} =
               Users.register_passkey(user, response, challenge, rp, "iPhone")

      assert "has already been taken" in errors_on(changeset).credential_id
    end

    test "passkey_registration_options/3 excludes the user's passkeys", %{
      user: user,
      authenticator: authenticator,
      rp: rp
    } do
      passkey_fixture(user, authenticator)
      options = Users.passkey_registration_options(user, rp, WebAuthn.new_challenge())

      assert options.excludeCredentials == [
               %{type: "public-key", id: FakeAuthenticator.encode(authenticator.credential_id)}
             ]

      assert options.user.id == FakeAuthenticator.encode(user.passkey_handle)
    end

    test "authenticate_passkey/3 returns the user and records the use", %{
      user: user,
      authenticator: authenticator,
      rp: rp
    } do
      passkey = passkey_fixture(user, authenticator)
      challenge = WebAuthn.new_challenge()

      response =
        FakeAuthenticator.assertion(authenticator, challenge, user.passkey_handle, sign_count: 3)

      assert {:ok, %User{id: id}} = Users.authenticate_passkey(response, challenge, rp)
      assert id == user.id

      used = Repo.get!(Passkey, passkey.id)
      assert used.sign_count == 3
      assert used.last_used_at
    end

    test "authenticate_passkey/3 rejects unknown passkeys and another user's handle", %{
      user: user,
      authenticator: authenticator,
      rp: rp
    } do
      challenge = WebAuthn.new_challenge()
      response = FakeAuthenticator.assertion(authenticator, challenge, user.passkey_handle)

      assert Users.authenticate_passkey(response, challenge, rp) ==
               {:error, :unknown_credential}

      passkey_fixture(user_fixture(), authenticator)
      assert Users.authenticate_passkey(response, challenge, rp) == {:error, :user_handle}
    end

    test "delete_passkey/2 deletes only the user's own passkeys", %{
      user: user,
      authenticator: authenticator
    } do
      passkey = passkey_fixture(user, authenticator)

      assert Users.delete_passkey(user_fixture(), passkey.id) == {:error, :not_found}
      assert {:ok, _passkey} = Users.delete_passkey(user, passkey.id)
      assert Users.list_passkeys(user) == []
    end
  end
end
