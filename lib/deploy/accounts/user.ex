defmodule Deploy.Accounts.User do
  @moduledoc """
  Schema for user accounts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          username: String.t() | nil,
          password: String.t() | nil,
          password_hash: String.t() | nil,
          display_name: String.t() | nil,
          active: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :display_name, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for updating user attributes (not password).
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name, :active])
    |> validate_required([:username])
    |> validate_length(:username, min: 2, max: 50)
    |> unique_constraint(:username)
  end

  @doc """
  Changeset for creating a new user or changing password.
  Validates and hashes the password.
  """
  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 80, message: "must be between 8 and 80 characters")
    |> hash_password()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
