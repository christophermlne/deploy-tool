defmodule DeployWeb.Router do
  use DeployWeb, :router

  import DeployWeb.AuthPlug, only: [fetch_current_user: 2, require_authenticated_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DeployWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  # Public routes (no authentication required)
  scope "/", DeployWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # Protected routes (authentication required)
  scope "/", DeployWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: {DeployWeb.AuthPlug, :ensure_authenticated} do
      live "/", DashboardLive, :index
      live "/deployments", DeploymentListLive, :index
      live "/deployments/new", NewDeploymentLive, :new
      live "/deployments/:id", DeploymentShowLive, :show
    end
  end
end
