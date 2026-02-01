defmodule Deploy.Reactors.Steps.CreateDeployBranch do
  @moduledoc """
  Creates a new deploy branch from the base branch (staging).

  The branch is named with the deploy date, e.g., "deploy-20260123".

  Compensation: Deletes the local branch (remote deletion is handled
  separately if the branch was pushed).
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    workspace = arguments.workspace
    deploy_date = arguments.deploy_date
    base_branch = arguments.base_branch

    branch_name = "deploy-#{deploy_date}"

    Logger.info("Creating deploy branch: #{branch_name} from #{base_branch}")

    # First, ensure we're on the base branch
    with {_, 0} <- Deploy.Git.cmd(["checkout", base_branch], cd: workspace, stderr_to_stdout: true),
         # Create and checkout the new deploy branch
         {_, 0} <- Deploy.Git.cmd(["checkout", "-b", branch_name], cd: workspace, stderr_to_stdout: true) do
      {:ok, branch_name}
    else
      {output, exit_code} ->
        {:error, "Failed to create deploy branch (exit #{exit_code}): #{output}"}
    end
  end

  @impl true
  def compensate(branch_name, arguments, _context, _options) do
    workspace = arguments.workspace

    # Switch back to staging and delete the deploy branch locally
    Deploy.Git.cmd(["checkout", "staging"], cd: workspace, stderr_to_stdout: true)
    Deploy.Git.cmd(["branch", "-D", branch_name], cd: workspace, stderr_to_stdout: true)

    :ok
  end
end
