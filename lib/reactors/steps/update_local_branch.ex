defmodule Deploy.Reactors.Steps.UpdateLocalBranch do
  @moduledoc """
  Pulls the latest changes from the remote after PRs have been merged.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    workspace = arguments.workspace
    branch = arguments.deploy_branch

    Logger.info("Pulling latest changes for #{branch}")

    case Deploy.Git.cmd(["pull", "origin", branch], cd: workspace, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, workspace}

      {output, exit_code} ->
        {:error, "Git pull failed (exit #{exit_code}): #{output}"}
    end
  end

  @impl true
  def compensate(_result, _arguments, _context, _options), do: :ok
end
