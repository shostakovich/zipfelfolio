defmodule ZipfelfolioWeb.PasskeyController do
  @moduledoc """
  The server side of the passkey hooks: options for the browser, with the challenge kept in the
  session for one attempt within the ceremony timeout, and the registration of a new passkey. Signing in with a
  passkey posts to `UserSessionController`.
  """
  use ZipfelfolioWeb, :controller

  alias Zipfelfolio.Accounts
  alias Zipfelfolio.WebAuthn

  def relying_party do
    %{
      id: ZipfelfolioWeb.Endpoint.host(),
      origin: ZipfelfolioWeb.Endpoint.url(),
      name: "zipfelfolio"
    }
  end

  @doc """
  Takes the challenge out of the session; `nil` once it is older than the ceremony timeout, so a
  captured request together with its cookie cannot be replayed later.
  """
  def pop_challenge(conn, purpose) do
    key = session_key(purpose)
    {fresh_challenge(get_session(conn, key)), delete_session(conn, key)}
  end

  defp fresh_challenge({challenge, issued_at}) do
    age_ms = System.system_time(:millisecond) - issued_at
    if age_ms in 0..WebAuthn.timeout_ms(), do: challenge
  end

  defp fresh_challenge(_value), do: nil

  defp put_challenge(conn, purpose, challenge),
    do: put_session(conn, session_key(purpose), {challenge, System.system_time(:millisecond)})

  def authentication_options(conn, _params) do
    challenge = WebAuthn.new_challenge()

    conn
    |> put_challenge(:login, challenge)
    |> json(WebAuthn.authentication_options(relying_party(), challenge))
  end

  def registration_options(conn, _params) do
    user = conn.assigns.current_scope.user

    if Accounts.sudo_mode?(user, -10) do
      challenge = WebAuthn.new_challenge()

      conn
      |> put_challenge(:registration, challenge)
      |> json(Accounts.passkey_registration_options(user, relying_party(), challenge))
    else
      conn |> put_status(:forbidden) |> json(%{error: "Bitte melde dich erneut an."})
    end
  end

  def create(conn, %{"passkey" => %{} = response, "name" => name})
      when not is_struct(response) do
    user = conn.assigns.current_scope.user
    {challenge, conn} = pop_challenge(conn, :registration)

    with true <- is_binary(challenge) and Accounts.sudo_mode?(user, -10),
         {:ok, passkey} <-
           Accounts.register_passkey(user, response, challenge, relying_party(), name) do
      json(conn, %{id: passkey.id})
    else
      {:error, %Ecto.Changeset{}} ->
        unprocessable(conn, "Bitte gib dem Passkey einen Namen (höchstens 60 Zeichen).")

      _ ->
        unprocessable(conn, "Der Passkey konnte nicht geprüft werden.")
    end
  end

  def create(conn, _params), do: unprocessable(conn, "Unvollständige Anfrage.")

  defp unprocessable(conn, message),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: message})

  defp session_key(:login), do: :passkey_login_challenge
  defp session_key(:registration), do: :passkey_registration_challenge
end
