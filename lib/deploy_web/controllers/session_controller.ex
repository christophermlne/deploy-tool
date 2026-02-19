defmodule DeployWeb.SessionController do
  use DeployWeb, :controller

  alias Deploy.Accounts
  alias DeployWeb.AuthPlug

  def new(conn, _params) do
    # If already logged in, redirect to home
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/")
    else
      render(conn, :new, error: nil)
    end
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        conn
        |> AuthPlug.log_in_user(user)
        |> put_flash(:info, "Welcome back, #{user.display_name || user.username}!")
        |> redirect(to: ~p"/")

      {:error, :account_disabled} ->
        render(conn, :new, error: "This account has been disabled.")

      {:error, :invalid_credentials} ->
        render(conn, :new, error: "Invalid username or password.")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> AuthPlug.log_out_user()
  end
end
