defmodule Deploy.Reactors.MergePRs do
  @moduledoc """
  Reactor for the PR merge phase of deployment.

  This phase:
  1. Discovers or fetches approved PRs
  2. Retargets them to the deploy branch
  3. Merges them sequentially
  4. Syncs the local workspace
  """

  use Reactor

  input :deploy_branch
  input :workspace
  input :client
  input :owner
  input :repo
  input :pr_numbers  # optional, default []

  step :fetch_approved_prs, Deploy.Reactors.Steps.FetchApprovedPRs do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :pr_numbers, input(:pr_numbers)
  end

  step :change_pr_bases, Deploy.Reactors.Steps.ChangePRBases do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :prs, result(:fetch_approved_prs)
    argument :deploy_branch, input(:deploy_branch)
  end

  step :merge_prs, Deploy.Reactors.Steps.MergePRs do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :prs, result(:change_pr_bases)
  end

  step :update_local_branch, Deploy.Reactors.Steps.UpdateLocalBranch do
    argument :workspace, input(:workspace)
    argument :deploy_branch, input(:deploy_branch)

    wait_for :merge_prs
  end

  return :merge_prs
end
