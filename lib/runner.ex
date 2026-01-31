defmodule Deploy.Runner do
  @moduledoc """
  High-level interface for running deployment reactors.

  Usage:

      # Run just the setup phase
      Deploy.Runner.setup()

      # Run with custom options
      Deploy.Runner.setup(deploy_date: "20260131")
  """

  require Logger

  alias Deploy.Config
  alias Deploy.Reactors.Setup

  @doc """
  Runs the setup phase of deployment.

  Returns {:ok, result} where result is a map containing:
    - workspace: path to the temporary workspace
    - branch: name of the created deploy branch

  Or {:error, reason} if any step fails (after compensation).
  """
  def setup(opts \\ []) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())

    inputs = %{
      repo_url: Config.repo_url(),
      github_token: Config.github_token(),
      deploy_date: deploy_date
    }

    Logger.info("Starting deployment setup for #{deploy_date}")

    case Reactor.run(Setup, inputs) do
      {:ok, branch_name} ->
        Logger.info("Setup complete. Deploy branch: #{branch_name}")
        {:ok, %{branch: branch_name}}

      {:error, errors} ->
        Logger.error("Setup failed: #{inspect(errors)}")
        {:error, errors}
    end
  end

  @doc """
  Runs the setup phase asynchronously, returning a task.

  Useful for long-running deployments or when you want to
  monitor progress from another process.
  """
  def setup_async(opts \\ []) do
    Task.async(fn -> setup(opts) end)
  end
end
