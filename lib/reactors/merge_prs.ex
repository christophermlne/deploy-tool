defmodule Deploy.Reactors.MergePRs do
  @moduledoc """
  Reactor for the PR merge phase of deployment.

  This phase:
  1. Discovers or fetches approved PRs
  2. Validates PRs are ready (approval, CI status)
  3. Retargets them to the deploy branch
  4. Merges them sequentially (with pre-merge conflict checks)
  5. Syncs the local workspace
  """

  use Reactor

  middlewares do
    middleware Deploy.Reactors.Middleware.EventBroadcaster
  end

  input :deploy_branch
  input :workspace
  input :client
  input :owner
  input :repo
  input :pr_numbers  # optional, default []

  # Validation skip options
  input :skip_reviews     # default: false
  input :skip_ci          # default: false
  input :skip_conflicts   # default: false
  input :skip_validation  # default: false (skips all checks)

  step :fetch_approved_prs, Deploy.Reactors.Steps.FetchApprovedPRs do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :pr_numbers, input(:pr_numbers)

    max_retries 0
  end

  step :validate_prs, Deploy.Reactors.Steps.ValidatePRs do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :prs, result(:fetch_approved_prs)
    argument :skip_reviews, input(:skip_reviews)
    argument :skip_ci, input(:skip_ci)
    argument :skip_validation, input(:skip_validation)

    # Validation failures should not retry - they need user intervention
    max_retries 0
  end

  step :change_pr_bases, Deploy.Reactors.Steps.ChangePRBases do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :prs, result(:validate_prs)
    argument :deploy_branch, input(:deploy_branch)

    max_retries 0
  end

  step :merge_prs, Deploy.Reactors.Steps.MergePRs do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :prs, result(:change_pr_bases)
    argument :skip_conflicts, input(:skip_conflicts)

    max_retries 0
  end

  step :update_local_branch, Deploy.Reactors.Steps.UpdateLocalBranch do
    argument :workspace, input(:workspace)
    argument :deploy_branch, input(:deploy_branch)

    wait_for :merge_prs
    max_retries 0
  end

  return :merge_prs
end
