defmodule Deploy.Reactors.Steps.PushVersionBump do
  @moduledoc """
  Pushes the version bump commit to the remote deploy branch.

  This step assumes the branch already exists on origin (from Phase 1 setup).

  Compensation: Force push to remove the commit using --force-with-lease.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{workspace: workspace, deploy_branch: deploy_branch}, _context, _options) do

    Logger.info("Pushing version bump to #{deploy_branch}")

    with :ok <- Deploy.Git.run!(["push", "origin", deploy_branch], cd: workspace, stderr_to_stdout: true) do
      {:ok, deploy_branch}
    end
  end

  @impl true
  def compensate(_result, arguments, _context, _options) do
    workspace = arguments.workspace
    deploy_branch = arguments.deploy_branch

    Logger.info("Compensating: force pushing to remove version bump commit")

    # Force push with lease to undo the version bump commit on remote
    case Deploy.Git.cmd(
           ["push", "--force-with-lease", "origin", deploy_branch],
           cd: workspace,
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {output, _} ->
        Logger.warning("Failed to force push for compensation: #{output}")
        :ok
    end
  end
end
