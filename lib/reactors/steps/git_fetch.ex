defmodule Deploy.Reactors.Steps.GitFetch do
  @moduledoc """
  Fetches a specific branch from the remote.

  This ensures we have the latest state of the branch before
  creating our deploy branch from it.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{workspace: workspace, branch: branch}, _context, _options) do

    Logger.info("Fetching latest #{branch} branch")

    opts = [cd: workspace, stderr_to_stdout: true]

    with :ok <- Deploy.Git.run!(["fetch", "origin", branch], opts),
         :ok <- Deploy.Git.run!(["reset", "--hard", "origin/#{branch}"], opts) do
      {:ok, branch}
    end
  end

end
