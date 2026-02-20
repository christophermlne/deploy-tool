defmodule Deploy.Reactors.Steps.CommitVersionBump do
  @moduledoc """
  Commits the version bump changes to the deploy branch.

  Stages the version files and creates a commit with the new version number.

  Compensation: Resets the commit (git reset --hard HEAD~1).
  """

  use Reactor.Step

  require Logger

  @version_files ["version.txt", "backend/version.txt", "frontend/package.json"]

  @impl true
  def run(%{workspace: workspace, new_version: new_version}, _context, _options) do

    Logger.info("Committing version bump to #{new_version}")

    # Stage the version files
    add_args = ["add" | @version_files]

    with {_, 0} <- Deploy.Git.cmd(add_args, cd: workspace, stderr_to_stdout: true),
         # Commit with version message
         commit_msg = "Bump version to #{new_version}",
         {_, 0} <- Deploy.Git.cmd(["commit", "-m", commit_msg], cd: workspace, stderr_to_stdout: true),
         # Get the commit SHA
         {sha, 0} <- Deploy.Git.cmd(["rev-parse", "HEAD"], cd: workspace, stderr_to_stdout: true) do
      {:ok, String.trim(sha)}
    else
      {output, exit_code} ->
        {:error, "Failed to commit version bump (exit #{exit_code}): #{output}"}
    end
  end

  @impl true
  def compensate(commit_sha, arguments, _context, _options) do
    workspace = arguments.workspace
    Logger.info("Compensating: resetting version bump commit #{String.slice(commit_sha, 0..6)}")

    case Deploy.Git.cmd(["reset", "--hard", "HEAD~1"], cd: workspace, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} ->
        Logger.warning("Failed to reset version bump commit: #{output}")
        :ok
    end
  end
end
