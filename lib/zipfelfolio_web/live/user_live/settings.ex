defmodule ZipfelfolioWeb.UserLive.Settings do
  use ZipfelfolioWeb, :live_view

  on_mount {ZipfelfolioWeb.UserAuth, :require_sudo_mode}

  alias Zipfelfolio.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current={:settings}>
      <.header>
        Einstellungen
        <:actions>
          <.link href={~p"/users/log-out"} method="delete" class="btn btn-sm btn-outline-secondary">
            Abmelden
          </.link>
        </:actions>
      </.header>

      <div class="row g-4">
        <div class="col-lg-7">
          <.card title="Passkeys" id="passkeys">
            <p class="text-body-secondary">
              Mit einem Passkey meldest du dich per Face ID, Fingerabdruck oder Geräte-PIN an.
            </p>
            <p :if={@passkeys == []} class="fst-italic">Noch kein Passkey hinterlegt.</p>
            <ul :if={@passkeys != []} class="list-group mb-3">
              <li
                :for={passkey <- @passkeys}
                id={"passkey-#{passkey.id}"}
                class="list-group-item d-flex align-items-center gap-2"
              >
                <div class="me-auto">
                  <div class="fw-semibold">{passkey.name}</div>
                  <div class="small text-body-secondary">
                    angelegt {date(passkey.inserted_at)}
                    <span :if={passkey.last_used_at}>
                      · zuletzt genutzt {date(passkey.last_used_at)}
                    </span>
                  </div>
                </div>
                <.button
                  variant="outline-danger"
                  size="sm"
                  phx-click="delete_passkey"
                  phx-value-id={passkey.id}
                  data-confirm={"Passkey „#{passkey.name}“ löschen?"}
                >
                  Löschen
                </.button>
              </li>
            </ul>
            <form id="passkey-register" phx-hook="PasskeyRegister">
              <label class="form-label" for="passkey-name">Name des neuen Passkeys</label>
              <div class="d-flex flex-column flex-sm-row gap-2">
                <input
                  id="passkey-name"
                  name="name"
                  class="form-control"
                  placeholder="z. B. iPhone"
                  maxlength="60"
                  required
                />
                <button class="btn btn-primary text-nowrap" type="submit">
                  Passkey hinzufügen
                </button>
              </div>
            </form>
          </.card>
        </div>

        <div class="col-lg-5">
          <.card title="Wertpapiere" id="securities">
            <p class="text-body-secondary">
              Woher die Kurse kommen, letzte Kurse und Wechselkurse, manuelle Kurse.
            </p>
            <.link navigate={~p"/settings/securities"} class="btn btn-outline-primary">
              Kursquellen und Kurse
            </.link>
          </.card>
          <.card title="Import" id="import">
            <p class="text-body-secondary">
              Wertpapiere, Depots, Konten und Buchungen aus Portfolio Performance übernehmen.
            </p>
            <.link navigate={~p"/settings/import"} class="btn btn-outline-primary">
              PP-Datei importieren
            </.link>
          </.card>
          <.card title="E-Mail-Adresse">
            <.form
              for={@email_form}
              id="email-form"
              phx-submit="update_email"
              phx-change="validate_email"
            >
              <.input
                field={@email_form[:email]}
                type="email"
                label="E-Mail"
                autocomplete="username"
                spellcheck="false"
                required
              />
              <.button phx-disable-with="Wird gesendet …">E-Mail ändern</.button>
            </.form>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Users.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} -> put_flash(socket, :info, "Die E-Mail-Adresse ist geändert.")
        {:error, _} -> put_flash(socket, :error, "Der Link ist ungültig oder abgelaufen.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Einstellungen")
     |> assign(
       :email_form,
       to_form(Users.change_user_email(user, %{}, validate_unique: false))
     )
     |> assign_passkeys()}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Users.change_user_email(user_params, validate_unique: false)
      |> to_form(action: :validate)

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Users.sudo_mode?(user)

    case Users.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Users.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        {:noreply,
         put_flash(
           socket,
           :info,
           "Wir haben einen Bestätigungslink an die neue Adresse geschickt."
         )}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("passkey_registered", _params, socket) do
    {:noreply, socket |> put_flash(:info, "Passkey hinzugefügt.") |> assign_passkeys()}
  end

  def handle_event("passkey_error", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("delete_passkey", %{"id" => id}, socket) do
    case Users.delete_passkey(socket.assigns.current_scope.user, id) do
      {:ok, _passkey} ->
        {:noreply, socket |> put_flash(:info, "Passkey gelöscht.") |> assign_passkeys()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Den Passkey gibt es nicht mehr.")}
    end
  end

  defp assign_passkeys(socket),
    do: assign(socket, :passkeys, Users.list_passkeys(socket.assigns.current_scope.user))

  defp date(datetime), do: Calendar.strftime(datetime, "%d.%m.%Y")
end
