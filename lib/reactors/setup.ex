defmodule Deploy.Reactors.Setup do
  @moduledoc """
  Reactor for the setup phase of deployment.

  This phase:
  1. Creates a temporary workspace directory
  2. Clones the repository into the workspace
  3. Creates a deploy branch from staging

  All steps are reversible—if any step fails, previous steps
  will be compensated (workspace deleted, etc.)
  """

  use Reactor

  input :repo_url
  input :github_token
  input :deploy_date  # e.g., "20260123"

  step :create_workspace, Deploy.Reactors.Steps.CreateWorkspace do
    # No inputs needed—just creates a temp directory
  end

  step :clone_repo, Deploy.Reactors.Steps.CloneRepo do
    argument :workspace, result(:create_workspace)
    argument :repo_url, input(:repo_url)
    argument :github_token, input(:github_token)
  end

  step :fetch_staging, Deploy.Reactors.Steps.GitFetch do
    argument :workspace, result(:create_workspace)
    argument :branch, value("staging")

    wait_for :clone_repo
  end

  step :create_deploy_branch, Deploy.Reactors.Steps.CreateDeployBranch do
    argument :workspace, result(:create_workspace)
    argument :deploy_date, input(:deploy_date)
    argument :base_branch, value("staging")

    wait_for :fetch_staging
  end

  step :push_deploy_branch, Deploy.Reactors.Steps.GitPush do
    argument :workspace, result(:create_workspace)
    argument :branch, result(:create_deploy_branch)

    wait_for :create_deploy_branch
  end

  return :push_deploy_branch
end
