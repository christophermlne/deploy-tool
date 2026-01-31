defmodule Deploy.Reactors.Steps.GitPush do
  @moduledoc """
  Pushes a branch to the remote repository.

  Compensation: Deletes the remote branch. This is important for
  cleanup if later steps fail after the branch has been pushed.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    workspace = arguments.workspace
    branch = arguments.branch

    Logger.info("Pushing branch #{branch} to origin")

    case System.cmd("git", ["push", "-u", "origin", branch], cd: workspace, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, branch}

      {output, exit_code} ->
        {:error, "Git push failed (exit #{exit_code}): #{output}"}
    end
  end

  @impl true
  def compensate(branch, arguments, _context, _options) do
    workspace = arguments.workspace

    Logger.info("Compensating: deleting remote branch #{branch}")

    # Delete the remote branch
    case System.cmd("git", ["push", "origin", "--delete", branch], cd: workspace, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, _exit_code} ->
        # Log but don't fail—might already be deleted
        Logger.warning("Failed to delete remote branch #{branch}: #{output}")
        :ok
    end
  end
end
