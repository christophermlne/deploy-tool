defmodule Deploy.Reactors.Steps.CloneRepo do
  @moduledoc """
  Clones the repository into the workspace directory.

  Uses the GitHub token for authentication to handle private repos.
  The token is injected into the clone URL.

  Compensation: Not needed—workspace cleanup handles this.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    workspace = arguments.workspace
    repo_url = arguments.repo_url
    token = arguments.github_token

    # Inject token into URL for authentication
    # Converts https://github.com/org/repo.git to https://token@github.com/org/repo.git
    authenticated_url = inject_token(repo_url, token)

    Logger.info("Cloning repository into #{workspace}")

    # Clone with depth=1 for speed if you don't need full history
    # Remove --depth 1 if you need to do operations that require history
    args = ["clone", "--depth", "1", "--branch", "staging", authenticated_url, "."]

    case Deploy.Git.cmd(args, cd: workspace, stderr_to_stdout: true) do
      {_output, 0} ->
        # Configure git user for commits we'll make later
        configure_git_user(workspace)
        {:ok, workspace}

      {output, exit_code} ->
        # Sanitize output to not leak token
        safe_output = String.replace(output, token, "[REDACTED]")
        {:error, "Git clone failed (exit #{exit_code}): #{safe_output}"}
    end
  end

  defp inject_token(url, token) do
    url
    |> URI.parse()
    |> Map.put(:userinfo, token)
    |> URI.to_string()
  end

  defp configure_git_user(workspace) do
    # Use a bot identity for deployment commits
    Deploy.Git.cmd(["config", "user.name", "Deploy Bot"], cd: workspace)
    Deploy.Git.cmd(["config", "user.email", "deploy-bot@example.com"], cd: workspace)
  end
end
