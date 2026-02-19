defmodule DeployWeb.PageController do
  use DeployWeb, :controller

  def home(conn, _params) do
    # Temporary home page - will redirect to login or dashboard
    text(conn, "Deploy Tool - Web UI Coming Soon")
  end
end
