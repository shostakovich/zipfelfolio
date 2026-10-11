defmodule ZipfelfolioWeb.UserLive.Settings do
  use ZipfelfolioWeb, :live_view

  on_mount {ZipfelfolioWeb.UserAuth, :require_sudo_mode}

  alias Zipfelfolio.{Receipts, Users}
  alias Zipfelfolio.Receipts.PaperlessJob
  alias Zipfelfolio.Users.User
  alias ZipfelfolioWeb.Format

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@sidebar}
      current={:settings}
    >
      <.header>
        Einstellungen
        <:actions>
          <.button href={~p"/users/log-out"} method="delete" icon="log-out">Abmelden</.button>
        </:actions>
      </.header>

      <div class="grid gap-x-12 gap-y-8 lg:grid-cols-2">
        <div class="flex min-w-0 flex-col gap-8">
          <section id="passkeys" aria-labelledby="passkeys-title">
            <.section_heading id="passkeys-title" count={length(@passkeys)}>
              Passkeys
            </.section_heading>
            <p class="mb-3 max-w-prose text-sm text-base-content/70">
              Mit einem Passkey meldest du dich per Face ID, Fingerabdruck oder Geräte-PIN an.
            </p>
            <.empty_state :if={@passkeys == []} icon="key-round">
              Noch kein Passkey hinterlegt.
            </.empty_state>
            <.list :if={@passkeys != []}>
              <.list_row
                :for={passkey <- @passkeys}
                id={"passkey-#{passkey.id}"}
                title={passkey.name}
              >
                <:leading><.icon name="key-round" class="size-5 text-base-content/70" /></:leading>
                <:meta>
                  angelegt {Format.date(passkey.inserted_at)}<span :if={passkey.last_used_at}><.meta_sep />zuletzt genutzt {Format.date(
                    passkey.last_used_at
                  )}</span>
                </:meta>
                <:action
                  id={"passkey-#{passkey.id}-delete"}
                  label="Löschen"
                  icon="trash-2"
                  danger
                  confirm={"Passkey „#{passkey.name}“ löschen?"}
                  on_click={JS.push("delete_passkey", value: %{id: to_string(passkey.id)})}
                />
              </.list_row>
            </.list>
            <form id="passkey-register" class="mt-4" phx-hook="PasskeyRegister">
              <.input
                id="passkey-name"
                name="name"
                label="Name des neuen Passkeys"
                inline
                placeholder="Name, z. B. iPhone"
                maxlength="60"
                required
              >
                <.button type="submit" variant={:primary} icon="plus" class="join-item">
                  Passkey hinzufügen
                </.button>
              </.input>
            </form>
          </section>

          <section id="depots" aria-labelledby="depots-title">
            <.section_heading id="depots-title">Depots</.section_heading>
            <p class="mb-3 max-w-prose text-sm text-base-content/70">
              Die Depotnummern deiner Depots.
            </p>
            <.button navigate={~p"/portfolios"} icon="briefcase">Depotnummern bearbeiten</.button>
          </section>

          <section id="email" aria-labelledby="email-title">
            <.section_heading id="email-title">E-Mail-Adresse</.section_heading>
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
              <.action_bar class="mt-4">
                <.button type="submit" variant={:primary} phx-disable-with="Wird gesendet …">
                  E-Mail ändern
                </.button>
              </.action_bar>
            </.form>
          </section>
        </div>

        <div class="flex min-w-0 flex-col gap-8">
          <section id="securities" aria-labelledby="securities-title">
            <.section_heading id="securities-title">Wertpapiere</.section_heading>
            <p class="mb-3 max-w-prose text-sm text-base-content/70">
              Woher die Kurse kommen, letzte Kurse und Wechselkurse, manuelle Kurse.
            </p>
            <.button navigate={~p"/settings/securities"} icon="trending-up">
              Kursquellen und Kurse
            </.button>
          </section>

          <section id="import" aria-labelledby="import-title">
            <.section_heading id="import-title">Import</.section_heading>
            <p class="mb-3 max-w-prose text-sm text-base-content/70">
              Wertpapiere, Depots, Konten und Buchungen aus Portfolio Performance übernehmen.
            </p>
            <.button navigate={~p"/settings/import"} icon="upload">PP-Datei importieren</.button>
          </section>

          <section id="receipt-intake" aria-labelledby="receipt-intake-title">
            <.section_heading id="receipt-intake-title">Belegeingang</.section_heading>
            <p class="mb-3 max-w-prose text-sm text-base-content/70">
              Holt alle 15 Minuten die Dokumente mit deinem Tag aus Paperless-ngx in den Eingang.
            </p>
            <ul class="mb-4 flex flex-col gap-3">
              <.intake_row
                id="paperless-status"
                title="Paperless-ngx"
                status={if User.paperless?(@paperless), do: "Verbunden", else: "Nicht verbunden"}
                tone={if User.paperless?(@paperless), do: :success, else: :warning}
                detail={paperless_status(@paperless)}
              />
              <.intake_row
                id="recognition-status"
                title="Belegerkennung"
                status={if @model_name, do: "Eingerichtet", else: "Kein Modell"}
                tone={if @model_name, do: :success, else: :neutral}
                detail={recognition_status(@model_name)}
              />
            </ul>
            <.form for={@paperless_form} id="paperless-form" phx-submit="save_paperless">
              <.input
                field={@paperless_form[:paperless_url]}
                type="url"
                label="URL"
                placeholder="https://paperless.example.org"
                autocomplete="off"
                spellcheck="false"
              />
              <.input
                field={@paperless_form[:paperless_token]}
                type="password"
                label="API-Token"
                value=""
                autocomplete="off"
                placeholder={if @paperless.paperless_token, do: "gespeichert"}
                help={
                  if @paperless.paperless_token,
                    do:
                      "Leer lassen, um den gespeicherten Token zu behalten; eine neue URL braucht einen neuen.",
                    else: "In Paperless unter „Mein Profil“."
                }
              />
              <.input
                field={@paperless_form[:paperless_tag]}
                label="Tag"
                placeholder="zipfelfolio"
                autocomplete="off"
                spellcheck="false"
              />
              <.action_bar class="mt-4">
                <:secondary :if={User.paperless?(@paperless)}>
                  <.button
                    id="paperless-disconnect"
                    variant={:danger_outline}
                    confirm="Paperless trennen?"
                    confirm_text="URL, Token und Tag werden gelöscht."
                    confirm_label="Trennen"
                    phx-click="disconnect_paperless"
                  >
                    Trennen
                  </.button>
                </:secondary>
                <.button type="submit" variant={:primary} phx-disable-with="Speichert …">
                  Speichern
                </.button>
              </.action_bar>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :status, :string, required: true
  attr :tone, :atom, required: true
  attr :detail, :list, required: true, doc: "its parts, each with its punctuation; none wraps"

  defp intake_row(assigns) do
    ~H"""
    <li id={@id}>
      <p class="flex flex-wrap items-center gap-x-2 font-medium">
        {@title}<span class="sr-only">:</span>
        <.badge tone={@tone} data-status>{@status}</.badge>
      </p>
      <p :if={@detail != []} class="text-sm text-base-content/70" data-detail>
        <%= for part <- @detail do %>
          <span class="whitespace-nowrap" data-part>{part}</span>
        <% end %>
      </p>
    </li>
    """
  end

  defp paperless_status(user) do
    if User.paperless?(user) do
      tag = user.paperless_tag

      polled =
        if user.paperless_polled_at,
          do: "zuletzt abgefragt #{Format.recent(user.paperless_polled_at)}",
          else: "noch nicht abgefragt"

      ["Tag „#{tag}“,", "danach „#{Receipts.done_tag(tag)}“ ·", polled]
    else
      []
    end
  end

  defp recognition_status(nil), do: ["Belege öffnen", "ein leeres Formular."]

  defp recognition_status(name),
    do: ["#{name} ·", "Text aus Paperless,", "sonst aus dem PDF"]

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
     |> assign(:model_name, Receipts.model_name())
     |> assign_paperless(Users.get_user!(user.id))
     |> assign_passkeys()}
  end

  defp assign_paperless(socket, user) do
    assign(socket, paperless: user, paperless_form: to_form(Users.change_paperless(user)))
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

  def handle_event("save_paperless", %{"user" => params}, socket) do
    true = Users.sudo_mode?(socket.assigns.current_scope.user)

    case Users.update_paperless(socket.assigns.current_scope, params) do
      {:ok, user} ->
        PaperlessJob.poll_soon(user)

        {:noreply,
         socket
         |> put_flash(:info, "Paperless gespeichert; zipfelfolio fragt es gleich ab.")
         |> assign_paperless(user)}

      {:error, changeset} ->
        {:noreply, assign(socket, :paperless_form, to_form(changeset, action: :update))}
    end
  end

  def handle_event("disconnect_paperless", _params, socket) do
    {:ok, user} = Users.disconnect_paperless(socket.assigns.current_scope)
    {:noreply, socket |> put_flash(:info, "Paperless getrennt.") |> assign_paperless(user)}
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
end
