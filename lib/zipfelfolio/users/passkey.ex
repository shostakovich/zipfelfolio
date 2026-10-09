defmodule Zipfelfolio.Users.Passkey do
  @moduledoc "A WebAuthn credential: the public key as SPKI and its COSE algorithm."
  use Zipfelfolio.Schema

  import Ecto.Changeset

  schema "user_passkeys" do
    field :credential_id, :binary
    field :public_key, :binary
    field :algorithm, :integer
    field :sign_count, :integer
    field :name, :string
    field :last_used_at, :utc_datetime_usec

    belongs_to :user, Zipfelfolio.Users.User

    timestamps()
  end

  def create_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:credential_id, :public_key, :algorithm, :sign_count, :name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:credential_id, :public_key, :algorithm, :sign_count, :name])
    |> validate_length(:name, max: 60)
    |> unique_constraint(:credential_id)
  end

  def use_changeset(passkey, sign_count),
    do: change(passkey, sign_count: sign_count, last_used_at: DateTime.utc_now())
end
