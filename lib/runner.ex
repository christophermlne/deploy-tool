defmodule Deploy.Runner do
  @moduledoc """
  High-level interface for running deployment reactors.

  Usage:

      # Run just the setup phase
      Deploy.Runner.setup()

      # Run with custom options
      Deploy.Runner.setup(deploy_date: "20260131")
  """

  require Logger

  alias Deploy.Config
  alias Deploy.Reactors.Setup
  alias Deploy.Reactors.MergePRs, as: MergePRsReactor
  alias Deploy.Reactors.DeployPR, as: DeployPRReactor

  @doc """
  Runs the setup phase of deployment.

  Returns {:ok, result} where result is a map containing:
    - workspace: path to the temporary workspace
    - branch: name of the created deploy branch

  Or {:error, reason} if any step fails (after compensation).
  """
  def setup(opts \\ []) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())

    inputs = %{
      repo_url: Config.repo_url(),
      github_token: Config.github_token(),
      deploy_date: deploy_date
    }

    Logger.info("Starting deployment setup for #{deploy_date}")

    case Reactor.run(Setup, inputs) do
      {:ok, %{branch: branch_name, workspace: workspace}} ->
        Logger.info("Setup complete. Deploy branch: #{branch_name}")
        {:ok, %{branch: branch_name, workspace: workspace}}

      {:error, errors} ->
        Logger.error("Setup failed: #{inspect(errors)}")
        {:error, errors}
    end
  end

  @doc """
  Runs the PR merge phase of deployment.

  First runs setup to get a workspace and deploy branch, then discovers
  approved PRs and merges them into the deploy branch.

  Options:
    - `pr_numbers` — list of specific PR numbers to merge (default: auto-discover)
    - `deploy_date` — override deploy date (default: today)
  """
  def merge_prs(opts \\ []) do
    pr_numbers = Keyword.get(opts, :pr_numbers, [])

    with {:ok, %{branch: branch, workspace: workspace}} <- setup(opts) do
      inputs = %{
        deploy_branch: branch,
        workspace: workspace,
        client: Deploy.GitHub.client(Config.github_token()),
        owner: Config.github_owner(),
        repo: Config.github_repo(),
        pr_numbers: pr_numbers
      }

      Logger.info("Starting PR merge phase")

      case Reactor.run(MergePRsReactor, inputs) do
        {:ok, merged_prs} ->
          Logger.info("Merged #{length(merged_prs)} PRs")
          {:ok, %{branch: branch, workspace: workspace, merged_prs: merged_prs}}

        {:error, errors} ->
          Logger.error("PR merge failed: #{inspect(errors)}")
          {:error, errors}
      end
    end
  end

  @doc """
  Runs the full deployment: setup, merge PRs, and create deploy PR.

  Options:
    - `pr_numbers` — list of specific PR numbers to merge (default: auto-discover)
    - `deploy_date` — override deploy date (default: today)
    - `reviewers` — list of GitHub usernames to request review from (default: [])
  """
  def deploy_pr(opts \\ []) do
    reviewers = Keyword.get(opts, :reviewers, [])

    with {:ok, %{branch: branch, workspace: workspace, merged_prs: merged_prs}} <- merge_prs(opts) do
      inputs = %{
        workspace: workspace,
        deploy_branch: branch,
        merged_prs: merged_prs,
        client: Deploy.GitHub.client(Config.github_token()),
        owner: Config.github_owner(),
        repo: Config.github_repo(),
        reviewers: reviewers
      }

      Logger.info("Creating deploy PR")

      case Reactor.run(DeployPRReactor, inputs) do
        {:ok, %{number: pr_number, url: pr_url}} ->
          Logger.info("Deploy PR created: #{pr_url}")
          {:ok, %{branch: branch, merged_prs: merged_prs, pr_number: pr_number, pr_url: pr_url}}

        {:error, errors} ->
          Logger.error("Deploy PR creation failed: #{inspect(errors)}")
          {:error, errors}
      end
    end
  end

  @doc """
  Runs the setup phase asynchronously, returning a task.

  Useful for long-running deployments or when you want to
  monitor progress from another process.
  """
  def setup_async(opts \\ []) do
    Task.async(fn -> setup(opts) end)
  end
end
