defmodule Deploy.Reactors.Steps.UpdateLocalBranch do
  @moduledoc """
  Pulls the latest changes from the remote after PRs have been merged.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(%{workspace: workspace, deploy_branch: branch}, _context, _options) do

    Logger.info("Pulling latest changes for #{branch}")

    with :ok <- Deploy.Git.run!(["pull", "origin", branch], cd: workspace, stderr_to_stdout: true) do
      {:ok, workspace}
    end
  end

end
