defmodule Zipfelfolio.Accounts.UserNotifier do
  @moduledoc false
  import Swoosh.Email

  alias Zipfelfolio.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:zipfelfolio, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "zipfelfolio: neue E-Mail-Adresse bestätigen", """
    Hallo,

    mit diesem Link bestätigst du deine neue E-Mail-Adresse für zipfelfolio:

    #{url}

    Wenn du das nicht angefordert hast, ignoriere diese Mail.
    """)
  end

  def deliver_passkey_added(user, passkey) do
    deliver(user.email, "zipfelfolio: neuer Passkey „#{passkey.name}“", """
    Hallo,

    für dein Konto bei zipfelfolio wurde der Passkey „#{passkey.name}“ angelegt.

    Warst du das nicht, melde dich mit einem Anmeldelink an und lösche ihn in den Einstellungen.
    """)
  end

  def deliver_login_instructions(user, url) do
    deliver(user.email, "zipfelfolio: Anmeldelink", """
    Hallo,

    mit diesem Link meldest du dich bei zipfelfolio an. Er gilt 15 Minuten und nur einmal:

    #{url}

    Danach kannst du in den Einstellungen einen Passkey anlegen.

    Wenn du das nicht angefordert hast, ignoriere diese Mail.
    """)
  end
end
