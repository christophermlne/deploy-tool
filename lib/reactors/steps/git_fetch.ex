defmodule Deploy.Reactors.Steps.GitFetch do
  @moduledoc """
  Fetches a specific branch from the remote.

  This ensures we have the latest state of the branch before
  creating our deploy branch from it.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    workspace = arguments.workspace
    branch = arguments.branch

    Logger.info("Fetching latest #{branch} branch")

    # Fetch the specific branch
    case Deploy.Git.cmd(["fetch", "origin", branch], cd: workspace, stderr_to_stdout: true) do
      {_output, 0} ->
        # Reset to the fetched branch to ensure we're at the latest
        case Deploy.Git.cmd(["reset", "--hard", "origin/#{branch}"], cd: workspace, stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, branch}

          {output, exit_code} ->
            {:error, "Git reset failed (exit #{exit_code}): #{output}"}
        end

      {output, exit_code} ->
        {:error, "Git fetch failed (exit #{exit_code}): #{output}"}
    end
  end

  @impl true
  def compensate(_result, _arguments, _context, _options) do
    # Nothing to compensate—this is a read operation
    :ok
  end
end
