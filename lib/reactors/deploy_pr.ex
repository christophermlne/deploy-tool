defmodule Deploy.Reactors.DeployPR do
  @moduledoc """
  Reactor for creating the deploy pull request.

  This phase:
  1. Creates a PR from the deploy branch to staging
  2. Populates its description with merged PR references
  3. Optionally requests review
  """

  use Reactor

  input :deploy_branch
  input :merged_prs
  input :client
  input :owner
  input :repo
  input :reviewers  # default []

  step :create_deploy_pr, Deploy.Reactors.Steps.CreateDeployPR do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :deploy_branch, input(:deploy_branch)
  end

  step :update_pr_description, Deploy.Reactors.Steps.UpdatePRDescription do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :pr_number, result(:create_deploy_pr, [:number])
    argument :merged_prs, input(:merged_prs)
    argument :deploy_branch, input(:deploy_branch)
  end

  step :request_review, Deploy.Reactors.Steps.RequestReview do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :pr_number, result(:create_deploy_pr, [:number])
    argument :reviewers, input(:reviewers)
  end

  return :create_deploy_pr
end
