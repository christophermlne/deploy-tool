defmodule Deploy.Application do
  @moduledoc """
  Application module for the Deploy tool.

  Starts the supervision tree containing:
  - Ecto Repo (database connection)
  - Phoenix.PubSub (event broadcasting)
  - Deployments.Registry (active deployment tracking)
  - Deployments.Supervisor (DynamicSupervisor for runner processes)

  ## Standalone Mode

  The CLI can still work without starting the full application.
  When `Deploy.Runner.deploy_pr/1` is called without the application running,
  it will work exactly as before - no database, no events, no supervision.

  ## Full Mode

  When the application is started (e.g., via `iex -S mix`),
  the full state management infrastructure is available.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      Deploy.Repo,

      # PubSub for events
      {Phoenix.PubSub, name: Deploy.PubSub},

      # Registry for tracking active deployments
      Deploy.Deployments.Registry,

      # DynamicSupervisor for runner processes
      Deploy.Deployments.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Deploy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
