defmodule Deploy.Reactors.DeployPR do
  @moduledoc """
  Reactor for creating the deploy pull request.

  This phase:
  1. Bumps the version in all version files
  2. Commits and pushes the version bump
  3. Creates a PR from the deploy branch to staging
  4. Populates its description with merged PR references
  5. Optionally requests review
  """

  use Reactor

  middlewares do
    middleware Deploy.Reactors.Middleware.EventBroadcaster
  end

  input :workspace
  input :deploy_branch
  input :merged_prs
  input :client
  input :owner
  input :repo
  input :reviewers  # default []

  step :bump_version_files, Deploy.Reactors.Steps.BumpVersionFiles do
    argument :workspace, input(:workspace)

    max_retries 0
  end

  step :commit_version_bump, Deploy.Reactors.Steps.CommitVersionBump do
    argument :workspace, input(:workspace)
    argument :new_version, result(:bump_version_files, [:new_version])

    max_retries 0
  end

  step :push_version_bump, Deploy.Reactors.Steps.PushVersionBump do
    argument :workspace, input(:workspace)
    argument :deploy_branch, input(:deploy_branch)

    wait_for :commit_version_bump
    max_retries 0
  end

  step :create_deploy_pr, Deploy.Reactors.Steps.CreateDeployPR do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :deploy_branch, input(:deploy_branch)

    wait_for :push_version_bump
    max_retries 0
  end

  step :update_pr_description, Deploy.Reactors.Steps.UpdatePRDescription do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :pr_number, result(:create_deploy_pr, [:number])
    argument :merged_prs, input(:merged_prs)
    argument :deploy_branch, input(:deploy_branch)

    max_retries 0
  end

  step :request_review, Deploy.Reactors.Steps.RequestReview do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :pr_number, result(:create_deploy_pr, [:number])
    argument :reviewers, input(:reviewers)

    max_retries 0
  end

  return :create_deploy_pr
end
