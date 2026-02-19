defmodule DeployWeb.AuthPlug do
  @moduledoc """
  Authentication plugs and LiveView hooks for the deploy web interface.
  """

  import Plug.Conn
  import Phoenix.Controller

  use Phoenix.VerifiedRoutes,
    endpoint: DeployWeb.Endpoint,
    router: DeployWeb.Router

  @doc """
  Plug to fetch the current user from the session.
  Assigns `:current_user` to the connection.
  """
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Deploy.Accounts.get_user(user_id)

    # Only assign user if they're still active
    user = if user && user.active, do: user, else: nil

    assign(conn, :current_user, user)
  end

  @doc """
  Plug to require an authenticated user.
  Redirects to login if not authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc """
  LiveView on_mount callback for authentication.

  ## Usage

      live_session :authenticated, on_mount: {DeployWeb.AuthPlug, :ensure_authenticated} do
        live "/", DashboardLive
      end
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_user, fn ->
        user_id = session["user_id"]
        user = user_id && Deploy.Accounts.get_user(user_id)
        if user && user.active, do: user, else: nil
      end)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end

  def on_mount(:fetch_current_user, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_user, fn ->
        user_id = session["user_id"]
        user = user_id && Deploy.Accounts.get_user(user_id)
        if user && user.active, do: user, else: nil
      end)

    {:cont, socket}
  end

  @doc """
  Logs in a user by creating a new session.
  """
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> assign(:current_user, user)
  end

  @doc """
  Logs out a user by clearing the session.
  """
  def log_out_user(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
