defmodule ZipfelfolioWeb.UserSessionController do
  use ZipfelfolioWeb, :controller

  alias Zipfelfolio.Accounts
  alias ZipfelfolioWeb.PasskeyController
  alias ZipfelfolioWeb.UserAuth

  def create(conn, %{"user" => %{"token" => token}}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, "Willkommen!")
        |> UserAuth.log_in_user(user)

      _ ->
        conn
        |> put_flash(:error, "Der Link ist ungültig oder abgelaufen.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def create(conn, %{"passkey" => %{} = response}) when not is_struct(response) do
    {challenge, conn} = PasskeyController.pop_challenge(conn, :login)

    with challenge when is_binary(challenge) <- challenge,
         {:ok, user} <-
           Accounts.authenticate_passkey(response, challenge, PasskeyController.relying_party()) do
      UserAuth.log_in_user(conn, user)
    else
      _ ->
        conn
        |> put_flash(:error, "Die Anmeldung mit Passkey hat nicht geklappt.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Du bist abgemeldet.")
    |> UserAuth.log_out_user()
  end
end
