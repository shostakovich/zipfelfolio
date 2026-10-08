defmodule ZipfelfolioWeb.UserAuth do
  @moduledoc """
  Session handling for signed-in users. A sign-in always sets the remember-me cookie, so a
  device stays signed in until the session token expires.
  """
  use ZipfelfolioWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Zipfelfolio.Users
  alias Zipfelfolio.Users.Scope

  # Matches the session validity in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_zipfelfolio_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # An active user gets a fresh session token once the current one is this old.
  @session_reissue_age_in_days 7

  @doc "Signs the user in and redirects to the page they wanted, or to the overview."
  def log_in_user(conn, user) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user)
    |> delete_session(:user_return_to)
    |> redirect(to: user_return_to || ~p"/")
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Users.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      ZipfelfolioWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/users/log-in")
  end

  @doc "Assigns the scope from the session or the remember-me cookie; reissues old tokens."
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Users.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      end
    end
  end

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user)
    else
      conn
    end
  end

  # A new session clears the old one (session fixation); an extended one keeps it.
  defp create_or_extend_session(conn, user) do
    token = Users.generate_user_session_token(user)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  # Keeps open tabs working when the signed-in user signs in again.
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id, do: conn

  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc "Disconnects the sockets of the given (expired) session tokens."
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      ZipfelfolioWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  `on_mount` for LiveViews: `:mount_current_scope` assigns the scope (or `nil`),
  `:require_authenticated` also redirects anonymous visitors to the sign-in page.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Bitte melde dich an.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Users.sudo_mode?(socket.assigns.current_scope.user, -10) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Bitte melde dich für diese Änderung erneut an.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      {user, _} =
        if user_token = session["user_token"] do
          Users.get_user_by_session_token(user_token)
        end || {nil, nil}

      Scope.for_user(user)
    end)
  end

  @doc "Plug for routes that require a signed-in user."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, "Bitte melde dich an.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
