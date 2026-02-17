# Deploy Recovery and Resumption

## Overview

This document specifies the ability to resume a failed deploy without manual cleanup. When a deploy fails mid-way, the user can re-run the deploy command with `resume: true` to continue from where it left off.

## Problem

If a deploy fails mid-way (especially after PRs have been merged), the user must:
1. Manually delete the deploy branch on GitHub
2. Re-open feature PRs (change their base back to `staging`)
3. Start the deploy again from scratch

This is tedious and error-prone. Worse, if PRs have already been merged into the deploy branch, those merges cannot be undone — the user must either continue the deploy or create a new deploy branch with a different date.

### Failure Scenarios

| Failure Point | Current State | Manual Cleanup Required |
|---------------|---------------|------------------------|
| Setup (clone/branch) | Nothing committed | None |
| ChangePRBases | PRs retargeted to deploy branch | Retarget PRs back to staging |
| MergePRs (partial) | Some PRs merged | Can't undo merges; must continue or start new deploy |
| CreateDeployPR | Deploy branch ready | Delete deploy branch |
| After PR created | Deploy PR exists | Close PR and delete branch |

## Solution

Add resume capability that:
1. Detects an existing deploy branch for the given date
2. Queries GitHub to reconstruct what work has been done
3. Skips completed steps and continues from the failure point

No file-based state persistence is needed — the state is reconstructed from GitHub.

---

## User Interface

### Basic Resume

```elixir
# First attempt fails
Deploy.Runner.deploy_pr(pr_numbers: [12, 13])
# => {:error, "Network timeout during PR creation"}

# Resume continues from where it failed
Deploy.Runner.deploy_pr(pr_numbers: [12, 13], resume: true)
# => {:ok, %{branch: "deploy-20260217", pr_number: 99, ...}}
```

### Force Fresh Start

```elixir
# Delete existing deploy branch and start over
Deploy.Runner.deploy_pr(pr_numbers: [12, 13], resume: :force)
```

### Check Existing State

```elixir
# Dry-run to see what state exists
Deploy.Runner.check_deploy_state(deploy_date: "20260217")
# => {:ok, %{
#      branch_exists: true,
#      merged_prs: [%{number: 12, title: "..."}],
#      pending_prs: [%{number: 13, title: "..."}],
#      deploy_pr: nil
#    }}
```

---

## State Detection

### Step 1: Check for Existing Branch

Query GitHub to see if the deploy branch exists:

```elixir
def branch_exists?(client, owner, repo, branch_name) do
  case Req.get(client, url: "/repos/#{owner}/#{repo}/branches/#{branch_name}") do
    {:ok, %{status: 200}} -> {:ok, true}
    {:ok, %{status: 404}} -> {:ok, false}
    {:error, reason} -> {:error, reason}
  end
end
```

Alternatively, use `git ls-remote` in the workspace:
```bash
git ls-remote --heads origin deploy-20260217
```

### Step 2: Get Merged PRs

Find PRs that were merged into the deploy branch:

```elixir
def list_merged_prs(client, owner, repo, base_branch) do
  # List closed PRs that targeted the deploy branch
  case Req.get(client,
    url: "/repos/#{owner}/#{repo}/pulls",
    params: %{state: "closed", base: base_branch}
  ) do
    {:ok, %{status: 200, body: prs}} ->
      merged = Enum.filter(prs, & &1["merged_at"])
      {:ok, Enum.map(merged, &normalize_pr/1)}
    {:error, reason} -> {:error, reason}
  end
end

defp normalize_pr(pr) do
  %{
    number: pr["number"],
    title: pr["title"],
    sha: pr["merge_commit_sha"],
    merged_at: pr["merged_at"]
  }
end
```

### Step 3: Get Pending PRs

Find PRs that are still open and targeting the deploy branch:

```elixir
def list_pending_prs(client, owner, repo, base_branch) do
  case Req.get(client,
    url: "/repos/#{owner}/#{repo}/pulls",
    params: %{state: "open", base: base_branch}
  ) do
    {:ok, %{status: 200, body: prs}} ->
      {:ok, Enum.map(prs, &normalize_pr/1)}
    {:error, reason} -> {:error, reason}
  end
end
```

### Step 4: Check for Existing Deploy PR

Find if a deploy PR already exists:

```elixir
def find_deploy_pr(client, owner, repo, head_branch, base_branch \\ "staging") do
  case Req.get(client,
    url: "/repos/#{owner}/#{repo}/pulls",
    params: %{state: "open", head: "#{owner}:#{head_branch}", base: base_branch}
  ) do
    {:ok, %{status: 200, body: [pr | _]}} ->
      {:ok, %{number: pr["number"], url: pr["html_url"]}}
    {:ok, %{status: 200, body: []}} ->
      {:ok, nil}
    {:error, reason} -> {:error, reason}
  end
end
```

---

## Resume Logic

### State Machine

Based on detected state, determine the resume point:

```elixir
defmodule Deploy.ResumeState do
  defstruct [
    :branch_exists,
    :merged_prs,
    :pending_prs,
    :deploy_pr,
    :resume_from
  ]

  def detect(client, owner, repo, deploy_branch, requested_prs) do
    with {:ok, exists} <- Deploy.GitHub.branch_exists?(client, owner, repo, deploy_branch),
         {:ok, merged} <- maybe_get_merged(client, owner, repo, deploy_branch, exists),
         {:ok, pending} <- maybe_get_pending(client, owner, repo, deploy_branch, exists),
         {:ok, deploy_pr} <- maybe_get_deploy_pr(client, owner, repo, deploy_branch, exists) do

      state = %__MODULE__{
        branch_exists: exists,
        merged_prs: merged,
        pending_prs: pending,
        deploy_pr: deploy_pr,
        resume_from: determine_resume_point(exists, merged, pending, deploy_pr, requested_prs)
      }

      {:ok, state}
    end
  end

  defp determine_resume_point(false, _, _, _, _), do: :setup
  defp determine_resume_point(true, [], [], nil, _), do: :change_bases
  defp determine_resume_point(true, merged, [], nil, requested) when length(merged) < length(requested), do: :merge_remaining
  defp determine_resume_point(true, _merged, [], nil, _), do: :create_deploy_pr
  defp determine_resume_point(true, _merged, pending, nil, _) when pending != [], do: :merge_remaining
  defp determine_resume_point(true, _, _, %{} = _pr, _), do: :done

  defp maybe_get_merged(_, _, _, _, false), do: {:ok, []}
  defp maybe_get_merged(client, owner, repo, branch, true), do: Deploy.GitHub.list_merged_prs(client, owner, repo, branch)

  # ... similar for pending and deploy_pr
end
```

### Resume Points

| Resume Point | What to Skip | What to Run |
|--------------|--------------|-------------|
| `:setup` | Nothing | Full deploy (fresh start) |
| `:change_bases` | Setup | ChangePRBases → MergePRs → DeployPR |
| `:merge_remaining` | Setup, ChangePRBases, some merges | Remaining merges → DeployPR |
| `:create_deploy_pr` | Setup, ChangePRBases, MergePRs | DeployPR reactor only |
| `:done` | Everything | Return existing PR info |

---

## Implementation

### New GitHub Functions

Add to `lib/github.ex`:

```elixir
@doc """
Checks if a branch exists on the remote.
"""
def branch_exists?(client, owner, repo, branch_name) do
  case Req.get(client, url: "/repos/#{owner}/#{repo}/branches/#{branch_name}") do
    {:ok, %{status: 200}} -> {:ok, true}
    {:ok, %{status: 404}} -> {:ok, false}
    {:ok, %{status: status, body: body}} ->
      {:error, "Failed to check branch (#{status}): #{inspect(body)}"}
    {:error, reason} -> {:error, reason}
  end
end

@doc """
Lists PRs that were merged into a specific branch.
"""
def list_merged_prs(client, owner, repo, base_branch) do
  case Req.get(client,
    url: "/repos/#{owner}/#{repo}/pulls",
    params: %{state: "closed", base: base_branch}
  ) do
    {:ok, %{status: 200, body: prs}} ->
      merged = prs
        |> Enum.filter(& &1["merged_at"])
        |> Enum.map(fn pr ->
          %{
            number: pr["number"],
            title: pr["title"],
            sha: pr["merge_commit_sha"]
          }
        end)
      {:ok, merged}
    {:ok, %{status: status, body: body}} ->
      {:error, "Failed to list PRs (#{status}): #{inspect(body)}"}
    {:error, reason} -> {:error, reason}
  end
end

@doc """
Finds an existing PR from head branch to base branch.
"""
def find_pr(client, owner, repo, head_branch, base_branch) do
  case Req.get(client,
    url: "/repos/#{owner}/#{repo}/pulls",
    params: %{state: "open", head: "#{owner}:#{head_branch}", base: base_branch}
  ) do
    {:ok, %{status: 200, body: [pr | _]}} ->
      {:ok, %{number: pr["number"], url: pr["html_url"]}}
    {:ok, %{status: 200, body: []}} ->
      {:ok, nil}
    {:ok, %{status: status, body: body}} ->
      {:error, "Failed to find PR (#{status}): #{inspect(body)}"}
    {:error, reason} -> {:error, reason}
  end
end

@doc """
Deletes a branch from the remote repository.
"""
def delete_branch(client, owner, repo, branch_name) do
  Logger.info("Deleting branch: #{branch_name}")

  case Req.delete(client, url: "/repos/#{owner}/#{repo}/git/refs/heads/#{branch_name}") do
    {:ok, %{status: 204}} -> :ok
    {:ok, %{status: 422}} -> {:error, :branch_not_found}
    {:ok, %{status: status, body: body}} ->
      {:error, "Failed to delete branch (#{status}): #{inspect(body)}"}
    {:error, reason} -> {:error, reason}
  end
end
```

### New Step: DetectExistingDeploy

```elixir
defmodule Deploy.Reactors.Steps.DetectExistingDeploy do
  use Reactor.Step
  require Logger

  @impl true
  def run(arguments, _context, _options) do
    client = arguments.client
    owner = arguments.owner
    repo = arguments.repo
    deploy_branch = arguments.deploy_branch
    resume = arguments.resume
    pr_numbers = arguments.pr_numbers

    case Deploy.GitHub.branch_exists?(client, owner, repo, deploy_branch) do
      {:ok, false} ->
        Logger.info("No existing deploy branch found, starting fresh")
        {:ok, %{resume_from: :setup, merged_prs: [], deploy_pr: nil}}

      {:ok, true} when resume == false ->
        {:error, "Deploy branch #{deploy_branch} already exists. Use resume: true to continue or resume: :force to start fresh."}

      {:ok, true} when resume == :force ->
        Logger.info("Force mode: deleting existing branch #{deploy_branch}")
        :ok = Deploy.GitHub.delete_branch(client, owner, repo, deploy_branch)
        {:ok, %{resume_from: :setup, merged_prs: [], deploy_pr: nil}}

      {:ok, true} ->
        detect_resume_state(client, owner, repo, deploy_branch, pr_numbers)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp detect_resume_state(client, owner, repo, deploy_branch, pr_numbers) do
    with {:ok, merged_prs} <- Deploy.GitHub.list_merged_prs(client, owner, repo, deploy_branch),
         {:ok, deploy_pr} <- Deploy.GitHub.find_pr(client, owner, repo, deploy_branch, "staging") do

      merged_numbers = MapSet.new(merged_prs, & &1.number)
      requested_numbers = MapSet.new(pr_numbers)
      remaining = MapSet.difference(requested_numbers, merged_numbers)

      resume_from = cond do
        deploy_pr != nil ->
          Logger.info("Deploy PR already exists: ##{deploy_pr.number}")
          :done
        MapSet.size(remaining) == 0 ->
          Logger.info("All PRs merged, ready to create deploy PR")
          :create_deploy_pr
        MapSet.size(remaining) < MapSet.size(requested_numbers) ->
          Logger.info("#{MapSet.size(merged_numbers)} PRs merged, #{MapSet.size(remaining)} remaining")
          :merge_remaining
        true ->
          Logger.info("Branch exists but no PRs merged yet")
          :change_bases
      end

      {:ok, %{
        resume_from: resume_from,
        merged_prs: merged_prs,
        remaining_pr_numbers: MapSet.to_list(remaining),
        deploy_pr: deploy_pr
      }}
    end
  end

  @impl true
  def compensate(_result, _arguments, _context, _options), do: :ok
end
```

### Modified Setup Reactor

The Setup reactor needs to handle the case where the branch already exists:

```elixir
defmodule Deploy.Reactors.Setup do
  use Reactor

  input :repo_url
  input :github_token
  input :deploy_date
  input :resume, default: false  # NEW

  # ... existing steps ...

  step :create_deploy_branch, Deploy.Reactors.Steps.CreateDeployBranch do
    argument :workspace, result(:clone_repo)
    argument :deploy_date, input(:deploy_date)
    argument :resume, input(:resume)  # NEW: pass through
  end

  # ... rest unchanged
end
```

### Modified CreateDeployBranch Step

```elixir
defmodule Deploy.Reactors.Steps.CreateDeployBranch do
  # ... existing code ...

  @impl true
  def run(arguments, _context, _options) do
    workspace = arguments.workspace
    deploy_date = arguments.deploy_date
    resume = Map.get(arguments, :resume, false)

    branch_name = "deploy-#{deploy_date}"
    base_branch = "staging"

    # Check if branch already exists locally (from clone)
    case Deploy.Git.cmd(["rev-parse", "--verify", branch_name], cd: workspace, stderr_to_stdout: true) do
      {_, 0} when resume in [true, :force] ->
        # Branch exists, just check it out
        Logger.info("Using existing deploy branch: #{branch_name}")
        {_, 0} = Deploy.Git.cmd(["checkout", branch_name], cd: workspace, stderr_to_stdout: true)
        {:ok, branch_name}

      {_, 0} ->
        {:error, "Deploy branch #{branch_name} already exists locally"}

      {_, _} ->
        # Branch doesn't exist, create it
        create_new_branch(workspace, branch_name, base_branch)
    end
  end

  defp create_new_branch(workspace, branch_name, base_branch) do
    # ... existing creation logic ...
  end
end
```

### Modified Runner

```elixir
defmodule Deploy.Runner do
  # ... existing code ...

  @doc """
  Checks the state of an existing deploy without making changes.
  """
  def check_deploy_state(opts \\ []) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())
    deploy_branch = "deploy-#{deploy_date}"

    client = Deploy.GitHub.client(Config.github_token())
    owner = Config.github_owner()
    repo = Config.github_repo()

    with {:ok, exists} <- Deploy.GitHub.branch_exists?(client, owner, repo, deploy_branch) do
      if exists do
        with {:ok, merged} <- Deploy.GitHub.list_merged_prs(client, owner, repo, deploy_branch),
             {:ok, pending} <- Deploy.GitHub.list_prs(client, owner, repo, base: deploy_branch, state: "open"),
             {:ok, deploy_pr} <- Deploy.GitHub.find_pr(client, owner, repo, deploy_branch, "staging") do
          {:ok, %{
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

  def deploy_pr(opts \\ []) do
    resume = Keyword.get(opts, :resume, false)

    # Early check for existing state if resuming
    if resume do
      deploy_with_resume(opts)
    else
      deploy_fresh(opts)
    end
  end

  defp deploy_fresh(opts) do
    # ... existing deploy_pr logic ...
  end

  defp deploy_with_resume(opts) do
    deploy_date = Keyword.get(opts, :deploy_date, Config.deploy_date())
    pr_numbers = Keyword.get(opts, :pr_numbers, [])
    reviewers = Keyword.get(opts, :reviewers, [])
    resume = Keyword.get(opts, :resume, true)

    client = Deploy.GitHub.client(Config.github_token())
    owner = Config.github_owner()
    repo = Config.github_repo()
    deploy_branch = "deploy-#{deploy_date}"

    # Detect current state
    with {:ok, state} <- detect_state(client, owner, repo, deploy_branch, pr_numbers, resume) do
      case state.resume_from do
        :done ->
          {:ok, %{
            branch: deploy_branch,
            merged_prs: state.merged_prs,
            pr_number: state.deploy_pr.number,
            pr_url: state.deploy_pr.url
          }}

        :create_deploy_pr ->
          run_deploy_pr_only(deploy_branch, state.merged_prs, reviewers)

        :merge_remaining ->
          run_from_merge(opts, state.remaining_pr_numbers, state.merged_prs)

        :change_bases ->
          run_from_change_bases(opts)

        :setup ->
          deploy_fresh(opts)
      end
    end
  end

  # ... helper functions for each resume point ...
end
```

---

## Testing Considerations

### Unit Tests

1. **Branch detection** — Test `branch_exists?` returns correct boolean
2. **Merged PR listing** — Test filtering by `merged_at`
3. **Deploy PR finding** — Test exact match on head/base
4. **Resume state detection** — Test each resume point determination
5. **Force mode** — Test branch deletion

### Integration Tests

1. **Fresh deploy** — Normal path without resume
2. **Resume after setup failure** — Detect existing branch, continue
3. **Resume after partial merge** — Detect merged PRs, merge remaining
4. **Resume after all merged** — Skip to deploy PR creation
5. **Resume when done** — Return existing PR
6. **Force restart** — Delete and start fresh

### Edge Cases

1. **PR merged outside deploy tool** — Should be detected and skipped
2. **Deploy PR closed manually** — Should detect as :create_deploy_pr
3. **Branch deleted after partial merge** — Should handle gracefully
4. **Different PR list on resume** — Handle mismatch between original and resume PR lists

---

## Error Messages

Clear error messages for resume scenarios:

```
Deploy branch deploy-20260217 already exists.

Current state:
  - 2 PRs merged: #12, #13
  - 1 PR pending: #14
  - No deploy PR created yet

Options:
  - To continue: Deploy.Runner.deploy_pr(pr_numbers: [12, 13, 14], resume: true)
  - To start fresh: Deploy.Runner.deploy_pr(pr_numbers: [12, 13, 14], resume: :force)
```

---

## Open Questions

1. **What if the PR list differs on resume?** If the original deploy was `pr_numbers: [12, 13, 14]` but resume is called with `pr_numbers: [12, 13]`, should we:
   - Ignore the difference and continue?
   - Warn and require confirmation?
   - Fail and require explicit handling?

2. **Should we support adding PRs on resume?** If 12 and 13 are merged, can the user resume with `pr_numbers: [12, 13, 14, 15]` to add more?

3. **Workspace handling on resume** — Should we reuse an existing workspace if found, or always create a fresh clone?

4. **State file as optional enhancement?** While GitHub query is the primary state source, an optional local state file could provide:
   - Faster state detection (no API calls)
   - Record of original intent (which PRs were requested)
   - Timestamp/audit trail

5. **Auto-resume behavior?** Should the tool auto-detect and resume by default (like `git rebase --continue`), or require explicit `resume: true`?
