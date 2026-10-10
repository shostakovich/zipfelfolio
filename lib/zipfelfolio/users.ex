defmodule Zipfelfolio.Users do
  @moduledoc """
  Users sign in with a passkey or, as a fallback, a magic link by email. There are no passwords
  and no sign-up: users are created by `mix zipfelfolio.create_user` or `Release.create_user/1`.
  """

  import Ecto.Query, warn: false

  alias Zipfelfolio.Repo
  alias Zipfelfolio.Securities.Security
  alias Zipfelfolio.Users.{Passkey, Scope, User, UserNotifier, UserToken}
  alias Zipfelfolio.WebAuthn

  ## Users

  def get_user_by_email(email) when is_binary(email), do: Repo.get_by(User, email: email)

  def get_user!(id), do: Repo.get!(User, id)

  @doc "Picks the security with `security_id` as the user's benchmark, nil for none."
  def update_benchmark(%Scope{user: user}, security_id) do
    # SQLite names no constraint that fails, so the security is looked up beforehand.
    security? = &Repo.exists?(from s in Security, where: s.id == ^&1)

    user
    |> User.benchmark_changeset(%{benchmark_id: security_id}, security?)
    |> Repo.update()
  end

  def create_user(attrs) do
    %User{}
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Whether the user signed in no more than `minutes` ago (20 by default), as required for
  changes to the account.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.add(DateTime.utc_now(), minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  ## Email

  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc "Changes the email to the one the token was sent to, and deletes the token."
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  ## Session

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Returns `{user, token_inserted_at}` for a valid session token, otherwise `nil`."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Magic link

  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Signs the user in with a magic link and expires the link.

  The first link confirms the email; then all of the user's tokens are expired, and returned so
  their sockets can be disconnected.
  """
  def login_user_by_magic_link(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, user_token} <- Repo.one(query) do
      if user.confirmed_at do
        Repo.delete!(user_token)
        {:ok, {user, []}}
      else
        user |> User.confirm_changeset() |> update_user_and_delete_all_tokens()
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  ## Passkeys

  def list_passkeys(%User{} = user) do
    Repo.all(from p in Passkey, where: p.user_id == ^user.id, order_by: [asc: p.id])
  end

  def passkey_registration_options(%User{} = user, rp, challenge) do
    exclude_ids = Enum.map(list_passkeys(user), & &1.credential_id)

    WebAuthn.registration_options(
      rp,
      challenge,
      %{handle: user.passkey_handle, name: user.email},
      exclude_ids
    )
  end

  @doc """
  Verifies a new passkey from the browser and stores it under `name`. The user gets a mail, as
  a passkey outlives the session that added it.
  """
  def register_passkey(%User{} = user, response, challenge, rp, name) do
    with {:ok, credential} <- WebAuthn.verify_registration(response, challenge, rp),
         {:ok, passkey} <-
           %Passkey{user_id: user.id}
           |> Passkey.create_changeset(Map.put(credential, :name, name))
           |> Repo.insert() do
      UserNotifier.deliver_passkey_added(user, passkey)
      {:ok, passkey}
    end
  end

  @doc "Finds the passkey of an assertion and verifies it; returns its user."
  def authenticate_passkey(response, challenge, rp) do
    with {:ok, credential_id} <- WebAuthn.credential_id(response),
         %Passkey{user: user} = passkey <- passkey_with_user(credential_id),
         {:ok, sign_count} <-
           WebAuthn.verify_authentication(response, challenge, rp, passkey, user.passkey_handle) do
      Repo.update!(Passkey.use_changeset(passkey, sign_count))
      {:ok, user}
    else
      nil -> {:error, :unknown_credential}
      {:error, reason} -> {:error, reason}
    end
  end

  defp passkey_with_user(credential_id) do
    Repo.one(from p in Passkey, where: p.credential_id == ^credential_id, preload: :user)
  end

  def delete_passkey(%User{} = user, id) do
    case Repo.get_by(Passkey, id: id, user_id: user.id) do
      nil -> {:error, :not_found}
      passkey -> Repo.delete(passkey)
    end
  end

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
