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

    # Where the user's receipts come from (ADR 0004): Paperless' URL, API token and tag.
    field :paperless_url, :string
    field :paperless_token, :string, redact: true
    field :paperless_tag, :string
    field :paperless_polled_at, :utc_datetime_usec

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

  @doc """
  A changeset for the user's Paperless: URL, API token and tag, all required; a blank token
  keeps the one stored, unless the URL changes, so a token never goes to another server.
  """
  def paperless_changeset(user, attrs) do
    attrs = keep_blank_token(attrs)

    user
    |> cast(attrs, [:paperless_url, :paperless_token, :paperless_tag])
    |> update_change(:paperless_url, &(&1 |> String.trim() |> String.trim_trailing("/")))
    |> update_change(:paperless_tag, &String.trim/1)
    |> update_change(:paperless_token, &String.trim/1)
    |> validate_required([:paperless_url, :paperless_token, :paperless_tag])
    |> validate_token_for_new_url(
      Enum.any?(attrs, &(to_string(elem(&1, 0)) == "paperless_token"))
    )
    |> validate_length(:paperless_url, max: 200)
    |> validate_length(:paperless_tag, max: 100)
    |> validate_length(:paperless_token, max: 200)
    |> validate_change(:paperless_url, fn :paperless_url, url ->
      case URI.new(url) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _other ->
          [paperless_url: "braucht http:// oder https:// und einen Host"]
      end
    end)
  end

  defp validate_token_for_new_url(changeset, token_given?) do
    if changeset.data.paperless_token && get_change(changeset, :paperless_url) && !token_given?,
      do: add_error(changeset, :paperless_token, "bitte für die neue URL eingeben"),
      else: changeset
  end

  defp keep_blank_token(attrs) do
    Map.reject(attrs, fn {key, value} ->
      to_string(key) == "paperless_token" and String.trim(value || "") == ""
    end)
  end

  @doc "Whether the user has entered a Paperless to poll."
  def paperless?(%__MODULE__{} = user),
    do: user.paperless_url != nil and user.paperless_token != nil and user.paperless_tag != nil

  def confirm_changeset(user), do: change(user, confirmed_at: DateTime.utc_now())
end
