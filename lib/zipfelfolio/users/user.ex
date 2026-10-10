defmodule Zipfelfolio.Users.User do
  @moduledoc false
  use Zipfelfolio.Schema

  import Ecto.Changeset

  alias Zipfelfolio.Securities.Security

  schema "users" do
    field :email, :string
    # The WebAuthn user handle: random, so passkeys reveal nothing about the account.
    field :passkey_handle, :binary, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :authenticated_at, :utc_datetime_usec, virtual: true

    has_many :passkeys, Zipfelfolio.Users.Passkey
    # The security the user compares their portfolios with, nil for none.
    belongs_to :benchmark, Security

    timestamps()
  end

  def create_changeset(user, attrs) do
    user
    |> email_changeset(attrs)
    |> put_change(:passkey_handle, :crypto.strong_rand_bytes(16))
  end

  @doc """
  A changeset for creating a user or changing the email; the email has to change.

  `validate_unique: false` skips the database check, e.g. for live validation.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> update_change(:email, &String.trim/1)
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "braucht ein @ und keine Leerzeichen"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Zipfelfolio.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "ist unverändert")
    else
      changeset
    end
  end

  @doc "A changeset for the benchmark; `security?` says whether a security id exists."
  def benchmark_changeset(user, attrs, security?) do
    user
    |> cast(attrs, [:benchmark_id])
    |> validate_change(:benchmark_id, fn :benchmark_id, id ->
      if security?.(id), do: [], else: [benchmark_id: "ist kein Wertpapier"]
    end)
  end

  def confirm_changeset(user), do: change(user, confirmed_at: DateTime.utc_now())
end
