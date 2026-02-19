defmodule Deploy.Runner do
  @moduledoc """
  High-level interface for running deployment reactors.

  Usage:

      # Run just the setup phase
      Deploy.Runner.setup()

      # Run with custom options
      Deploy.Runner.setup(deploy_date: "20260131")

      # Resume a failed deploy
      Deploy.Runner.deploy_pr(pr_numbers: [12, 13], resume: true)

      # Force restart (delete existing deploy branch)
      Deploy.Runner.deploy_pr(pr_numbers: [12, 13], resume: :force)

      # Check deploy state without making changes
      Deploy.Runner.check_deploy_state(deploy_date: "20260217")
  """

  require Logger

  alias Deploy.Config
  alias Deploy.GitHub
  alias Deploy.Reactors.Setup
  alias Deploy.Reactors.MergePRs, as: MergePRsReactor
  alias Deploy.Reactors.DeployPR, as: DeployPRReactor
  alias Deploy.Reactors.FullDeploy

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

    context = build_reactor_context(opts, "setup")

    case Reactor.run(Setup, inputs, context) do
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
    - `skip_reviews` — skip approval validation (default: false)
    - `skip_ci` — skip CI validation (default: false)
    - `skip_conflicts` — skip merge conflict validation (default: false)
    - `skip_validation` — skip all validation checks (default: false)
  """
  def merge_prs(opts \\ []) do
    pr_numbers = Keyword.get(opts, :pr_numbers, [])

    # Validation skip options
    skip_validation = Keyword.get(opts, :skip_validation, false)
    skip_reviews = skip_validation || Keyword.get(opts, :skip_reviews, false)
    skip_ci = skip_validation || Keyword.get(opts, :skip_ci, false)
    skip_conflicts = skip_validation || Keyword.get(opts, :skip_conflicts, false)

    with {:ok, %{branch: branch, workspace: workspace}} <- setup(opts) do
      inputs = %{
        deploy_branch: branch,
        workspace: workspace,
        client: Deploy.GitHub.client(Config.github_token()),
        owner: Config.github_owner(),
        repo: Config.github_repo(),
        pr_numbers: pr_numbers,
        skip_reviews: skip_reviews,
        skip_ci: skip_ci,
        skip_conflicts: skip_conflicts,
        skip_validation: skip_validation
      }

      Logger.info("Starting PR merge phase")

      context = build_reactor_context(opts, "merge_prs")

      case Reactor.run(MergePRsReactor, inputs, context) do
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
  Checks the state of an existing deploy without making changes.

  Returns information about:
    - Whether the deploy branch exists
    - Which PRs have been merged into it
    - Whether a deploy PR has been created

  Options:
    - `deploy_date` — override deploy date (default: today)
  """
  def check_deploy_state(opts \\ []) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())
    deploy_branch = "deploy-#{deploy_date}"

    client = GitHub.client(Config.github_token())
    owner = Config.github_owner()
    repo = Config.github_repo()

    with {:ok, exists} <- GitHub.branch_exists?(client, owner, repo, deploy_branch) do
      if exists do
        with {:ok, merged} <- GitHub.list_merged_prs(client, owner, repo, deploy_branch),
             {:ok, pending} <- GitHub.list_prs(client, owner, repo, base: deploy_branch, state: "open"),
             {:ok, deploy_pr} <- GitHub.find_pr(client, owner, repo, deploy_branch, "staging") do
          {:ok,
           %{
             branch_exists: true,
             deploy_branch: deploy_branch,
             merged_prs: merged,
             pending_prs: pending,
             deploy_pr: deploy_pr
           }}
        end
      else
        {:ok, %{branch_exists: false, deploy_branch: deploy_branch}}
      end
    end
  end

  @doc """
  Runs the full deployment: setup, merge PRs, and create deploy PR.

  Options:
    - `pr_numbers` — list of specific PR numbers to merge (default: auto-discover)
    - `deploy_date` — override deploy date (default: today)
    - `reviewers` — list of GitHub usernames to request review from (default: [])
    - `resume` — resume mode:
      - `false` (default) — fail if deploy branch already exists
      - `true` — detect state and continue from where it left off
      - `:force` — delete existing deploy branch and start fresh
    - `skip_reviews` — skip approval validation (default: false)
    - `skip_ci` — skip CI validation (default: false)
    - `skip_conflicts` — skip merge conflict validation (default: false)
    - `skip_validation` — skip all validation checks (default: false)
  """
  def deploy_pr(opts \\ []) do
    resume = Keyword.get(opts, :resume, false)

    if resume do
      deploy_with_resume(opts)
    else
      deploy_fresh(opts)
    end
  end

  defp deploy_fresh(opts) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())
    deploy_branch = "deploy-#{deploy_date}"
    reviewers = Keyword.get(opts, :reviewers, [])
    pr_numbers = Keyword.get(opts, :pr_numbers, [])

    # Validation skip options
    skip_validation = Keyword.get(opts, :skip_validation, false)
    skip_reviews = skip_validation || Keyword.get(opts, :skip_reviews, false)
    skip_ci = skip_validation || Keyword.get(opts, :skip_ci, false)
    skip_conflicts = skip_validation || Keyword.get(opts, :skip_conflicts, false)

    client = GitHub.client(Config.github_token())
    owner = Config.github_owner()
    repo = Config.github_repo()

    # Check if branch already exists before trying to create it
    case GitHub.branch_exists?(client, owner, repo, deploy_branch) do
      {:ok, true} ->
        {:error,
         "Deploy branch #{deploy_branch} already exists. " <>
           "Use resume: true to continue or resume: :force to start fresh."}

      {:ok, false} ->
        inputs = %{
          repo_url: Config.repo_url(),
          github_token: Config.github_token(),
          deploy_date: deploy_date,
          client: client,
          owner: owner,
          repo: repo,
          pr_numbers: pr_numbers,
          skip_reviews: skip_reviews,
          skip_ci: skip_ci,
          skip_conflicts: skip_conflicts,
          skip_validation: skip_validation,
          reviewers: reviewers
        }

        Logger.info("Starting full deployment for #{deploy_date}")

        context = build_reactor_context(opts, "full_deploy")

        case Reactor.run(FullDeploy, inputs, context) do
          {:ok, result} ->
            Logger.info("Deploy complete: #{result.pr_url}")
            {:ok, result}

          {:error, errors} ->
            Logger.error("Deploy failed: #{inspect(errors)}")
            {:error, errors}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deploy_with_resume(opts) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())
    pr_numbers = Keyword.get(opts, :pr_numbers, [])
    reviewers = Keyword.get(opts, :reviewers, [])
    resume = Keyword.get(opts, :resume, true)

    client = GitHub.client(Config.github_token())
    owner = Config.github_owner()
    repo = Config.github_repo()
    deploy_branch = "deploy-#{deploy_date}"

    with {:ok, state} <- detect_resume_state(client, owner, repo, deploy_branch, pr_numbers, resume) do
      case state.resume_from do
        :done ->
          Logger.info("Deploy already complete, returning existing PR")

          {:ok,
           %{
             branch: deploy_branch,
             merged_prs: state.merged_prs,
             pr_number: state.deploy_pr.number,
             pr_url: state.deploy_pr.url
           }}

        :create_deploy_pr ->
          Logger.info("Resuming: creating deploy PR")
          run_deploy_pr_from_existing_branch(opts, deploy_branch, state.merged_prs, reviewers)

        :merge_remaining ->
          Logger.info("Resuming: merging #{length(state.remaining_pr_numbers)} remaining PRs")
          run_from_merge(opts, state.remaining_pr_numbers, state.merged_prs)

        :change_bases ->
          Logger.info("Resuming: changing PR bases and merging")
          run_from_change_bases(opts)

        :setup ->
          Logger.info("Starting fresh deploy")
          deploy_fresh(Keyword.put(opts, :resume, false))
      end
    end
  end

  defp detect_resume_state(client, owner, repo, deploy_branch, pr_numbers, resume) do
    case GitHub.branch_exists?(client, owner, repo, deploy_branch) do
      {:ok, false} ->
        Logger.info("No existing deploy branch found, starting fresh")
        {:ok, %{resume_from: :setup, merged_prs: [], deploy_pr: nil}}

      {:ok, true} when resume == :force ->
        Logger.info("Force mode: deleting existing branch #{deploy_branch}")

        case GitHub.delete_branch(client, owner, repo, deploy_branch) do
          :ok ->
            {:ok, %{resume_from: :setup, merged_prs: [], deploy_pr: nil}}

          {:error, :branch_not_found} ->
            {:ok, %{resume_from: :setup, merged_prs: [], deploy_pr: nil}}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, true} ->
        detect_existing_state(client, owner, repo, deploy_branch, pr_numbers)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp detect_existing_state(client, owner, repo, deploy_branch, pr_numbers) do
    with {:ok, all_merged_prs} <- GitHub.list_merged_prs(client, owner, repo, deploy_branch),
         {:ok, deploy_pr} <- GitHub.find_pr(client, owner, repo, deploy_branch, "staging"),
         {:ok, merged_prs} <- filter_prs_in_branch(client, owner, repo, deploy_branch, all_merged_prs) do
      merged_numbers = MapSet.new(merged_prs, & &1.number)
      requested_numbers = MapSet.new(pr_numbers)
      remaining = MapSet.difference(requested_numbers, merged_numbers)

      resume_from =
        cond do
          deploy_pr != nil ->
            Logger.info("Deploy PR already exists: ##{deploy_pr.number}")
            :done

          MapSet.size(remaining) == 0 and MapSet.size(merged_numbers) > 0 ->
            Logger.info("All requested PRs merged, ready to create deploy PR")
            :create_deploy_pr

          MapSet.size(remaining) < MapSet.size(requested_numbers) ->
            Logger.info(
              "#{MapSet.size(merged_numbers)} PRs merged, #{MapSet.size(remaining)} remaining"
            )

            :merge_remaining

          true ->
            Logger.info("Branch exists but no PRs merged yet")
            :change_bases
        end

      {:ok,
       %{
         resume_from: resume_from,
         merged_prs: merged_prs,
         remaining_pr_numbers: MapSet.to_list(remaining),
         deploy_pr: deploy_pr
       }}
    end
  end

  # Filter PRs to only those whose merge commit is actually in the current branch
  defp filter_prs_in_branch(client, owner, repo, branch, prs) do
    results =
      Enum.reduce_while(prs, {:ok, []}, fn pr, {:ok, acc} ->
        case GitHub.commit_in_branch?(client, owner, repo, pr.sha, branch) do
          {:ok, true} ->
            {:cont, {:ok, [pr | acc]}}

          {:ok, false} ->
            Logger.debug("PR ##{pr.number} merge commit #{pr.sha} not in #{branch}, skipping")
            {:cont, {:ok, acc}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, filtered} -> {:ok, Enum.reverse(filtered)}
      error -> error
    end
  end

  defp run_deploy_pr_reactor(opts, branch, workspace, merged_prs, reviewers) do
    inputs = %{
      workspace: workspace,
      deploy_branch: branch,
      merged_prs: merged_prs,
      client: GitHub.client(Config.github_token()),
      owner: Config.github_owner(),
      repo: Config.github_repo(),
      reviewers: reviewers
    }

    Logger.info("Creating deploy PR")

    context = build_reactor_context(opts, "deploy_pr")

    case Reactor.run(DeployPRReactor, inputs, context) do
      {:ok, %{number: pr_number, url: pr_url}} ->
        Logger.info("Deploy PR created: #{pr_url}")
        {:ok, %{branch: branch, merged_prs: merged_prs, pr_number: pr_number, pr_url: pr_url}}

      {:error, errors} ->
        Logger.error("Deploy PR creation failed: #{inspect(errors)}")
        {:error, errors}
    end
  end

  defp run_deploy_pr_from_existing_branch(opts, deploy_branch, merged_prs, reviewers) do
    # Create a temporary workspace and clone the repo to work with the existing branch
    with {:ok, workspace} <- create_temp_workspace(),
         :ok <- clone_and_checkout_branch(workspace, deploy_branch) do
      run_deploy_pr_reactor(opts, deploy_branch, workspace, merged_prs, reviewers)
    end
  end

  defp run_from_merge(opts, remaining_pr_numbers, already_merged_prs) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())
    reviewers = Keyword.get(opts, :reviewers, [])
    deploy_branch = "deploy-#{deploy_date}"

    # Validation skip options
    skip_validation = Keyword.get(opts, :skip_validation, false)
    skip_reviews = skip_validation || Keyword.get(opts, :skip_reviews, false)
    skip_ci = skip_validation || Keyword.get(opts, :skip_ci, false)
    skip_conflicts = skip_validation || Keyword.get(opts, :skip_conflicts, false)

    with {:ok, workspace} <- create_temp_workspace(),
         :ok <- clone_and_checkout_branch(workspace, deploy_branch) do
      inputs = %{
        deploy_branch: deploy_branch,
        workspace: workspace,
        client: GitHub.client(Config.github_token()),
        owner: Config.github_owner(),
        repo: Config.github_repo(),
        pr_numbers: remaining_pr_numbers,
        skip_reviews: skip_reviews,
        skip_ci: skip_ci,
        skip_conflicts: skip_conflicts,
        skip_validation: skip_validation
      }

      Logger.info("Merging #{length(remaining_pr_numbers)} remaining PRs")

      context = build_reactor_context(opts, "merge_prs")

      case Reactor.run(MergePRsReactor, inputs, context) do
        {:ok, newly_merged_prs} ->
          all_merged = already_merged_prs ++ newly_merged_prs
          Logger.info("Merged #{length(newly_merged_prs)} PRs, total: #{length(all_merged)}")
          run_deploy_pr_reactor(opts, deploy_branch, workspace, all_merged, reviewers)

        {:error, errors} ->
          Logger.error("PR merge failed: #{inspect(errors)}")
          {:error, errors}
      end
    end
  end

  defp run_from_change_bases(opts) do
    # The PRs haven't been retargeted yet, so we run the full merge phase
    # but with an existing branch
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())
    pr_numbers = Keyword.get(opts, :pr_numbers, [])
    reviewers = Keyword.get(opts, :reviewers, [])
    deploy_branch = "deploy-#{deploy_date}"

    # Validation skip options
    skip_validation = Keyword.get(opts, :skip_validation, false)
    skip_reviews = skip_validation || Keyword.get(opts, :skip_reviews, false)
    skip_ci = skip_validation || Keyword.get(opts, :skip_ci, false)
    skip_conflicts = skip_validation || Keyword.get(opts, :skip_conflicts, false)

    with {:ok, workspace} <- create_temp_workspace(),
         :ok <- clone_and_checkout_branch(workspace, deploy_branch) do
      inputs = %{
        deploy_branch: deploy_branch,
        workspace: workspace,
        client: GitHub.client(Config.github_token()),
        owner: Config.github_owner(),
        repo: Config.github_repo(),
        pr_numbers: pr_numbers,
        skip_reviews: skip_reviews,
        skip_ci: skip_ci,
        skip_conflicts: skip_conflicts,
        skip_validation: skip_validation
      }

      Logger.info("Starting merge phase with existing branch")

      context = build_reactor_context(opts, "merge_prs")

      case Reactor.run(MergePRsReactor, inputs, context) do
        {:ok, merged_prs} ->
          Logger.info("Merged #{length(merged_prs)} PRs")
          run_deploy_pr_reactor(opts, deploy_branch, workspace, merged_prs, reviewers)

        {:error, errors} ->
          Logger.error("PR merge failed: #{inspect(errors)}")
          {:error, errors}
      end
    end
  end

  defp create_temp_workspace do
    timestamp = :os.system_time(:millisecond)
    unique_id = :rand.uniform(999_999)
    workspace = "/tmp/deploy-#{timestamp}-#{unique_id}"

    case File.mkdir_p(workspace) do
      :ok ->
        Logger.info("Created workspace: #{workspace}")
        {:ok, workspace}

      {:error, reason} ->
        {:error, "Failed to create workspace: #{inspect(reason)}"}
    end
  end

  defp clone_and_checkout_branch(workspace, branch) do
    repo_url = Config.repo_url()
    token = Config.github_token()

    # Inject token into URL for authenticated clone
    authenticated_url =
      repo_url
      |> String.replace("https://", "https://#{token}@")

    Logger.info("Cloning repo and checking out #{branch}")

    with {_, 0} <- Deploy.Git.cmd(["clone", authenticated_url, "."], cd: workspace, stderr_to_stdout: true),
         {_, 0} <- Deploy.Git.cmd(["checkout", branch], cd: workspace, stderr_to_stdout: true) do
      :ok
    else
      {output, exit_code} ->
        {:error, "Git operation failed (exit #{exit_code}): #{output}"}
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

  # Builds context for Reactor.run with deployment_id and current_phase
  # when available. This enables the EventBroadcaster middleware to
  # track step progress.
  defp build_reactor_context(opts, phase) do
    case Keyword.get(opts, :deployment_id) do
      nil -> %{current_phase: phase}
      deployment_id -> %{deployment_id: deployment_id, current_phase: phase}
    end
  end
end
