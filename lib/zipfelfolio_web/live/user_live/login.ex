defmodule ZipfelfolioWeb.UserLive.Login do
  use ZipfelfolioWeb, :live_view

  alias Zipfelfolio.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h2 class="mb-4 text-center text-lg font-semibold">Anmelden</h2>
      <p :if={@current_scope} class="mb-4 text-center text-sm text-base-content/70">
        Für Änderungen am Konto meldest du dich bitte noch einmal an.
      </p>

      <.button
        id="passkey-login"
        variant={:primary}
        icon="key-round"
        class="w-full"
        phx-hook="PasskeyLogin"
        data-form="passkey-form"
      >
        Mit Passkey anmelden
      </.button>
      <.form for={%{}} as={:passkey} id="passkey-form" action={~p"/users/log-in"}></.form>

      <div class="divider my-6 text-sm text-base-content/70">oder</div>

      <p class="text-sm text-base-content/70">
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
        <.button type="submit" class="mt-2 w-full" phx-disable-with="Wird gesendet …">
          Anmeldelink senden
        </.button>
      </.form>

      <p :if={local_mail_adapter?()} class="mt-6 text-center text-sm text-base-content/70">
        Entwicklung: Mails landen im <.link href="/dev/mailbox" class="link">Postfach</.link>.
      </p>
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
