defmodule Deploy.Reactors.Steps.ValidatePRs do
  @moduledoc """
  Validates PRs are ready to merge before attempting any merges.

  Performs upfront validation checks:
  - Approval: At least one APPROVED review, no CHANGES_REQUESTED
  - CI status: All checks completed with success

  Merge conflict checking is NOT done here — it happens before each
  individual merge in the MergePRs step, since each merge can introduce
  new conflicts for subsequent PRs.
  """

  use Reactor.Step

  require Logger

  @impl true
  def run(arguments, _context, _options) do
    client = arguments.client
    owner = arguments.owner
    repo = arguments.repo
    prs = arguments.prs

    skip_validation = Map.get(arguments, :skip_validation, false)
    skip_reviews = Map.get(arguments, :skip_reviews, false)
    skip_ci = Map.get(arguments, :skip_ci, false)

    if skip_validation do
      Logger.info("Skipping all PR validation (skip_validation: true)")
      {:ok, prs}
    else
      validate_all_prs(client, owner, repo, prs, skip_reviews, skip_ci)
    end
  end

  defp validate_all_prs(client, owner, repo, prs, skip_reviews, skip_ci) do
    Logger.info("Validating #{length(prs)} PRs before merge")

    results =
      Enum.map(prs, fn pr ->
        reasons = validate_pr(client, owner, repo, pr, skip_reviews, skip_ci)
        {pr, reasons}
      end)

    failures = Enum.filter(results, fn {_pr, reasons} -> reasons != [] end)

    if failures == [] do
      Logger.info("All PRs passed validation")
      {:ok, prs}
    else
      failure_details =
        Enum.map(failures, fn {pr, reasons} ->
          %{number: pr.number, title: pr.title, reasons: reasons}
        end)

      Logger.error("#{length(failures)} PRs failed validation: #{inspect(failure_details)}")
      {:error, %{validation_failures: failure_details}}
    end
  end

  defp validate_pr(client, owner, repo, pr, skip_reviews, skip_ci) do
    []
    |> maybe_check_approval(client, owner, repo, pr.number, skip_reviews)
    |> maybe_check_ci(client, owner, repo, pr.head_ref, skip_ci)
  end

  defp maybe_check_approval(reasons, _client, _owner, _repo, _pr_number, true), do: reasons

  defp maybe_check_approval(reasons, client, owner, repo, pr_number, false) do
    case Deploy.GitHub.pr_approved?(client, owner, repo, pr_number) do
      {:ok, true} -> reasons
      {:ok, false} -> [:no_approval | reasons]
      {:error, _} -> [:approval_check_failed | reasons]
    end
  end

  defp maybe_check_ci(reasons, _client, _owner, _repo, _ref, true), do: reasons

  defp maybe_check_ci(reasons, client, owner, repo, ref, false) do
    case Deploy.GitHub.ci_status(client, owner, repo, ref) do
      {:ok, :success} ->
        reasons

      {:ok, :pending} ->
        [:ci_pending | reasons]

      {:ok, {:failed, failed_runs}} ->
        names = Enum.map(failed_runs, & &1["name"])
        [{:ci_failed, names} | reasons]

      {:error, _} ->
        [:ci_check_failed | reasons]
    end
  end

end
