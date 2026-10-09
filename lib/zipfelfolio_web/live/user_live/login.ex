defmodule ZipfelfolioWeb.UserLive.Login do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.card title="Anmelden">
        <p :if={@current_scope} class="text-body-secondary">
          Für Änderungen am Konto meldest du dich bitte noch einmal an.
        </p>

        <button
          type="button"
          id="passkey-login"
          class="btn btn-primary w-100"
          phx-hook="PasskeyLogin"
          data-form="passkey-form"
        >
          Mit Passkey anmelden
        </button>
        <.form for={%{}} as={:passkey} id="passkey-form" action={~p"/users/log-in"}></.form>

        <hr class="my-4" />

        <p class="small text-body-secondary">
          Neues Gerät oder kein Passkey zur Hand? Wir schicken dir einen Anmeldelink.
        </p>
        <.form for={@form} id="login-form" phx-submit="send_link">
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="E-Mail"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="outline-primary" class="w-100" phx-disable-with="Wird gesendet …">
            Anmeldelink senden
          </.button>
        </.form>

        <p :if={local_mail_adapter?()} class="small text-body-secondary mt-3 mb-0">
          Entwicklung: Mails landen im <.link href="/dev/mailbox">Postfach</.link>.
        </p>
      </.card>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email = get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    {:ok,
     socket
     |> assign(:page_title, "Anmelden")
     |> assign(:form, to_form(%{"email" => email}, as: "user"))}
  end

  @impl true
  def handle_event("send_link", %{"user" => %{"email" => email}}, socket) do
    if user = Users.get_user_by_email(email) do
      Users.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
    end

    # The same answer either way, so the form tells no one which addresses exist.
    {:noreply,
     socket
     |> put_flash(:info, "Wenn die Adresse bei uns bekannt ist, kommt gleich ein Anmeldelink.")
     |> push_navigate(to: ~p"/users/log-in")}
  end

  def handle_event("passkey_error", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  defp local_mail_adapter? do
    Application.get_env(:zipfelfolio, Zipfelfolio.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
