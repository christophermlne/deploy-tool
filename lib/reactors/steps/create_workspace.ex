defmodule Deploy.Reactors.Steps.CreateWorkspace do
  @moduledoc """
  Creates a temporary workspace directory for the deployment.

  The workspace is created in the system temp directory with a unique
  identifier to allow for parallel deployments if needed.

  Compensation: Removes the workspace directory and all contents.
  """

  use Reactor.Step

  @impl true
  def run(_arguments, _context, _options) do
    base_dir = System.tmp_dir!()
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    unique_id = :erlang.unique_integer([:positive])

    workspace = Path.join(base_dir, "deploy-#{timestamp}-#{unique_id}")

    case File.mkdir_p(workspace) do
      :ok ->
        {:ok, workspace}

      {:error, reason} ->
        {:error, "Failed to create workspace at #{workspace}: #{inspect(reason)}"}
    end
  end

  @impl true
  def compensate(workspace, _arguments, _context, _options) do
    case File.rm_rf(workspace) do
      {:ok, _} ->
        :ok

      {:error, reason, path} ->
        # Log but don't fail compensation—best effort cleanup
        require Logger
        Logger.warning("Failed to clean up workspace #{path}: #{inspect(reason)}")
        :ok
    end
  end
end
