defmodule Mix.Tasks.Deploy do
  @moduledoc """
  Runs the full deployment: setup, merge PRs, and create deploy PR.

  ## Usage

      mix deploy PR_NUMBER [PR_NUMBER ...]

  ## Options

      --skip-reviews      Skip approval validation
      --skip-ci           Skip CI validation
      --skip-conflicts    Skip merge conflict validation
      --skip-validation   Skip all validation checks
      --reviewers         Comma-separated list of GitHub usernames to request review from
      --resume            Resume from existing deploy branch state
      --force             Delete existing deploy branch and start fresh

  ## Examples

      # Deploy specific PRs with all validation
      mix deploy 12 13

      # Deploy with all validation skipped (for testing)
      mix deploy 12 13 --skip-validation

      # Deploy with specific checks skipped
      mix deploy 12 13 --skip-reviews --skip-ci

      # Resume a failed deploy
      mix deploy 12 13 --resume

      # Force restart (delete existing branch)
      mix deploy 12 13 --force

      # Request review from specific users
      mix deploy 12 13 --reviewers alice,bob
  """

  use Mix.Task

  @shortdoc "Run the full deployment workflow"

  @switches [
    skip_reviews: :boolean,
    skip_ci: :boolean,
    skip_conflicts: :boolean,
    skip_validation: :boolean,
    reviewers: :string,
    resume: :boolean,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    # Start the application so we have access to config and HTTP client
    Mix.Task.run("app.start")

    {opts, pr_numbers_str, _} = OptionParser.parse(args, switches: @switches)

    pr_numbers =
      pr_numbers_str
      |> Enum.map(&String.to_integer/1)

    if pr_numbers == [] do
      Mix.shell().error("Error: At least one PR number is required")
      Mix.shell().info("\nUsage: mix deploy PR_NUMBER [PR_NUMBER ...] [options]")
      Mix.shell().info("\nRun `mix help deploy` for more information.")
      exit({:shutdown, 1})
    end

    # Build options for Deploy.Runner.deploy_pr/1
    deploy_opts =
      [pr_numbers: pr_numbers]
      |> maybe_add_opt(:skip_reviews, opts[:skip_reviews])
      |> maybe_add_opt(:skip_ci, opts[:skip_ci])
      |> maybe_add_opt(:skip_conflicts, opts[:skip_conflicts])
      |> maybe_add_opt(:skip_validation, opts[:skip_validation])
      |> maybe_add_reviewers(opts[:reviewers])
      |> maybe_add_resume(opts[:resume], opts[:force])

    Mix.shell().info("Starting deployment with PRs: #{inspect(pr_numbers)}")
    Mix.shell().info("Options: #{inspect(Keyword.delete(deploy_opts, :pr_numbers))}")

    case Deploy.Runner.deploy_pr(deploy_opts) do
      {:ok, result} ->
        Mix.shell().info("\nDeployment successful!")
        Mix.shell().info("  Branch: #{result.branch}")
        Mix.shell().info("  PR: ##{result.pr_number}")
        Mix.shell().info("  URL: #{result.pr_url}")
        Mix.shell().info("  Merged PRs: #{length(result.merged_prs)}")

      {:error, %{validation_failures: failures}} ->
        Mix.shell().error("\nValidation failed for #{length(failures)} PR(s):\n")

        for failure <- failures do
          Mix.shell().error("  PR ##{failure.number}: #{failure.title}")

          for reason <- failure.reasons do
            Mix.shell().error("    - #{format_reason(reason)}")
          end
        end

        Mix.shell().info("\nTo skip validation, use: mix deploy #{Enum.join(pr_numbers_str, " ")} --skip-validation")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("\nDeployment failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, false), do: opts
  defp maybe_add_opt(opts, key, true), do: Keyword.put(opts, key, true)

  defp maybe_add_reviewers(opts, nil), do: opts

  defp maybe_add_reviewers(opts, reviewers_str) do
    reviewers = String.split(reviewers_str, ",", trim: true)
    Keyword.put(opts, :reviewers, reviewers)
  end

  defp maybe_add_resume(opts, nil, nil), do: opts
  defp maybe_add_resume(opts, true, _), do: Keyword.put(opts, :resume, true)
  defp maybe_add_resume(opts, _, true), do: Keyword.put(opts, :resume, :force)

  defp format_reason(:no_approval), do: "No approving review"
  defp format_reason(:ci_pending), do: "CI checks still running"
  defp format_reason({:ci_failed, names}), do: "CI failed: #{Enum.join(names, ", ")}"
  defp format_reason({:merge_conflict, _}), do: "Merge conflict with base branch"
  defp format_reason(:approval_check_failed), do: "Failed to check approval status"
  defp format_reason(:ci_check_failed), do: "Failed to check CI status"
  defp format_reason(other), do: inspect(other)
end
