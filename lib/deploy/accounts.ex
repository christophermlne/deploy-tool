defmodule Deploy.Accounts do
  @moduledoc """
  The Accounts context for user management and authentication.
  """

  import Ecto.Query
  alias Deploy.Repo
  alias Deploy.Accounts.User

  # --- User CRUD ---

  @doc """
  Creates a new user with a password.

  ## Examples

      iex> create_user(%{username: "admin", password: "secret123", display_name: "Admin"})
      {:ok, %User{}}

      iex> create_user(%{username: "a", password: "short"})
      {:error, %Ecto.Changeset{}}
  """
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user by ID.
  Returns nil if not found.
  """
  def get_user(id) when is_integer(id) do
    Repo.get(User, id)
  end

  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> get_user(int_id)
      _ -> nil
    end
  end

  @doc """
  Gets a user by username.
  Returns nil if not found.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Lists all users, optionally filtered.

  ## Options

    * `:active` - filter by active status (true/false)

  ## Examples

      iex> list_users()
      [%User{}, ...]

      iex> list_users(active: true)
      [%User{active: true}, ...]
  """
  def list_users(opts \\ []) do
    User
    |> maybe_filter_active(opts[:active])
    |> order_by(:username)
    |> Repo.all()
  end

  defp maybe_filter_active(query, nil), do: query
  defp maybe_filter_active(query, active), do: where(query, active: ^active)

  @doc """
  Updates a user (not password).
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deactivates a user account.
  """
  def deactivate_user(%User{} = user) do
    update_user(user, %{active: false})
  end

  @doc """
  Changes a user's password.
  """
  def change_user_password(%User{} = user, attrs) do
    user
    |> User.registration_changeset(attrs)
    |> Repo.update()
  end

  # --- Authentication ---

  @doc """
  Authenticates a user by username and password.

  Returns `{:ok, user}` on success, or `{:error, reason}` on failure.

  ## Error reasons

    * `:invalid_credentials` - username not found or password incorrect
    * `:account_disabled` - user account is inactive

  ## Examples

      iex> authenticate_user("admin", "correct_password")
      {:ok, %User{}}

      iex> authenticate_user("admin", "wrong_password")
      {:error, :invalid_credentials}

      iex> authenticate_user("inactive_user", "password")
      {:error, :account_disabled}
  """
  def authenticate_user(username, password) when is_binary(username) and is_binary(password) do
    user = get_user_by_username(username)

    cond do
      is_nil(user) ->
        # Prevent timing attacks by still running the hash comparison
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      not user.active ->
        {:error, :account_disabled}

      Bcrypt.verify_pass(password, user.password_hash) ->
        {:ok, user}

      true ->
        {:error, :invalid_credentials}
    end
  end
end
