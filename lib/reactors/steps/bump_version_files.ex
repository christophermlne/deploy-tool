defmodule Deploy.Reactors.Steps.BumpVersionFiles do
  @moduledoc """
  Reads the current version, increments the patch number, and updates
  all version files in the workspace.

  Files updated:
  - ./version.txt (plain text)
  - backend/version.txt (plain text)
  - frontend/package.json (JSON, "version" key)

  Compensation: Restores original file contents.
  """

  use Reactor.Step

  require Logger

  @version_files ["version.txt", "backend/version.txt"]
  @package_json "frontend/package.json"

  @impl true
  def run(arguments, _context, _options) do
    workspace = arguments.workspace

    # Read current version from canonical source
    version_file = Path.join(workspace, "version.txt")

    with {:ok, current_version} <- read_version(version_file),
         new_version = increment_patch(current_version),
         :ok <- update_version_files(workspace, new_version),
         :ok <- update_package_json(workspace, new_version) do
      Logger.info("Bumped version from #{current_version} to #{new_version}")
      {:ok, %{old_version: current_version, new_version: new_version}}
    end
  end

  @impl true
  def compensate(%{old_version: old_version}, arguments, _context, _options) do
    workspace = arguments.workspace
    Logger.info("Compensating: restoring version to #{old_version}")

    # Restore version files
    Enum.each(@version_files, fn file ->
      path = Path.join(workspace, file)
      File.write(path, old_version)
    end)

    # Restore package.json
    restore_package_json(workspace, old_version)

    :ok
  end

  def compensate(_result, _arguments, _context, _options), do: :ok

  defp read_version(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, String.trim(content)}
      {:error, reason} -> {:error, "Failed to read version file: #{reason}"}
    end
  end

  @doc """
  Increments the patch component of a semver version string.

  ## Examples

      iex> Deploy.Reactors.Steps.BumpVersionFiles.increment_patch("2.4.10")
      "2.4.11"

      iex> Deploy.Reactors.Steps.BumpVersionFiles.increment_patch("1.0.0")
      "1.0.1"
  """
  def increment_patch(version_string) do
    [major, minor, patch] =
      version_string
      |> String.trim()
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    "#{major}.#{minor}.#{patch + 1}"
  end

  defp update_version_files(workspace, new_version) do
    results =
      Enum.map(@version_files, fn file ->
        path = Path.join(workspace, file)
        File.write(path, new_version)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, "Failed to update version file: #{reason}"}
    end
  end

  defp update_package_json(workspace, new_version) do
    path = Path.join(workspace, @package_json)

    with {:ok, content} <- File.read(path),
         {:ok, json} <- Jason.decode(content),
         updated = Map.put(json, "version", new_version),
         {:ok, encoded} <- Jason.encode(updated, pretty: true) do
      File.write(path, encoded <> "\n")
    else
      {:error, %Jason.DecodeError{} = err} ->
        {:error, "Failed to parse package.json: #{Exception.message(err)}"}

      {:error, reason} ->
        {:error, "Failed to update package.json: #{inspect(reason)}"}
    end
  end

  defp restore_package_json(workspace, old_version) do
    path = Path.join(workspace, @package_json)

    with {:ok, content} <- File.read(path),
         {:ok, json} <- Jason.decode(content),
         updated = Map.put(json, "version", old_version),
         {:ok, encoded} <- Jason.encode(updated, pretty: true) do
      File.write(path, encoded <> "\n")
    else
      _ -> :ok
    end
  end
end
