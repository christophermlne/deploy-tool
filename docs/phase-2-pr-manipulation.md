# Phase 2: PR Manipulation

## Overview

Phase 2 handles the manipulation of approved pull requests. After the setup phase creates and pushes the deploy branch, this phase retargets approved PRs from `staging` to the deploy branch and merges them one by one.

This is arguably the most complex phase because it involves coordinating multiple PRs, has partial reversibility, and contains a "point of no return" once merges begin.

## Business Context

In our deployment workflow:
1. Developers create feature PRs targeting `staging`
2. PRs get reviewed and approved
3. At deploy time, we create a `deploy-YYYYMMDD` branch from staging
4. We retarget all approved PRs to the deploy branch
5. We merge them one-by-one into the deploy branch
6. The deploy branch (now containing all approved work) becomes the deploy PR

This batching approach lets us:
- Control exactly what goes into each deployment
- Create a single deploy PR that references all included work
- Roll back the entire batch if needed (before merging)

## Implementation Decisions

### Client passed as input, not built internally

The doc originally showed steps receiving `github_token` and building their own client. Instead, the reactor accepts a pre-built `Req` client as an input. This makes testing straightforward — tests pass `Req.new(plug: fn)` stub clients, matching the pattern used throughout the existing test suite. `Deploy.Runner.merge_prs/1` builds the client via `Deploy.GitHub.client/1` before invoking the reactor.

### No `CollectPRMetadata` step

The doc proposed a separate step to enrich merged PR data (author, linked issues, labels) for use in the deploy PR description. This was deferred — the merge step already returns `%{number, title, sha}` for each merged PR, which is sufficient for now. A metadata enrichment step can be added in Phase 3 if needed.

### No `ConfirmPointOfNoReturn` step

The doc proposed a confirmation gate before merging. This was not implemented — the tool runs non-interactively and the compensation strategy (log warning, return `:ok`) handles the "can't undo merges" concern adequately.

### Branch update polling between merges

Not anticipated in the original doc. When merging multiple PRs sequentially, each merge changes the deploy branch HEAD. The next PR's head branch is then out of date relative to its base. GitHub's `PUT /repos/{owner}/{repo}/pulls/{number}/update-branch` endpoint triggers an async update (returns 202), so the step polls `GET /repos/{owner}/{repo}/pulls/{number}` waiting for `"mergeable": true` before attempting the merge (2s intervals, up to 10 retries).

### No `PartialMergeError` struct

The doc suggested a structured error for partial merge failures. The current implementation returns a plain error string from the step identifying which PR failed. The reactor's compensation logs a warning that merges can't be undone. A structured error type can be added if the runner needs to make decisions based on partial success.

### Setup reactor returns workspace

Phase 1's Setup reactor was modified to return `%{branch: ..., workspace: ...}` instead of just the branch name string. This is needed so `Runner.merge_prs/1` can pass the workspace path to the Phase 2 reactor. A `ReturnMap` step aggregates the two values.

### Configuration options deferred

The doc proposed configurable merge method, CI checks, label filters, and merge order. None of these are implemented yet — squash merge is hardcoded, no CI pre-check, no label filtering, PRs merge in the order given/discovered.

## Inputs

| Input | Type | Description |
|-------|------|-------------|
| `workspace` | string | Path to the cloned repo (from Phase 1) |
| `deploy_branch` | string | Name of deploy branch, e.g., `deploy-20260123` |
| `client` | Req client | Pre-built GitHub API client (from `Deploy.GitHub.client/1`) |
| `owner` | string | GitHub org/owner name |
| `repo` | string | GitHub repository name |
| `pr_numbers` | list | Specific PRs to include, or `[]` to auto-discover |

## Outputs

The reactor returns a list of merged PR metadata:

```elixir
[
  %{number: 42, title: "Add user authentication", sha: "abc123..."},
  %{number: 43, title: "Fix login bug", sha: "def456..."}
]
```

`Deploy.Runner.merge_prs/1` wraps this as `{:ok, %{branch: ..., merged_prs: [...]}}`.

## Steps

### Step 1: FetchApprovedPRs

**Purpose**: Get a list of PRs that are approved and ready to merge.

**Logic**:
- If `pr_numbers` is non-empty, fetch each PR individually via `GET /repos/{owner}/{repo}/pulls/{number}`
- Otherwise, list open PRs targeting staging via `GET /repos/{owner}/{repo}/pulls?state=open&base=staging`, then filter to those where `pr_approved?/4` returns true

**Output**: List of `%{number, title, head_ref}` maps

**Compensation**: `:ok` (read-only)

---

### Step 2: ChangePRBases

**Purpose**: Retarget each approved PR from `staging` to the deploy branch.

**API call**: `PATCH /repos/{owner}/{repo}/pulls/{number}` with `{"base": "deploy-YYYYMMDD"}`

**Compensation**: Changes each PR's base back to `"staging"`. Tracks which PRs were successfully changed.

**Failure**: Stops on first error, returns which PR failed.

---

### Step 3: MergePRs

**Purpose**: Merge each retargeted PR into the deploy branch via squash merge.

**Logic**:
1. For the first PR, merge directly
2. For subsequent PRs, call `PUT /repos/{owner}/{repo}/pulls/{number}/update-branch` to sync the PR's head with the updated base, then poll until `"mergeable": true`, then merge
3. Stop on first failure

**Compensation**: Logs a warning, returns `:ok`. Merges cannot be undone.

**Output**: List of `%{number, title, sha}` maps

---

### Step 4: UpdateLocalBranch

**Purpose**: Sync the local workspace with the remote after all merges.

**Logic**: `git pull origin {deploy_branch}`

**Compensation**: `:ok` (read-only)

---

## Reactor Definition

```elixir
defmodule Deploy.Reactors.MergePRs do
  use Reactor

  input :deploy_branch
  input :workspace
  input :client
  input :owner
  input :repo
  input :pr_numbers

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
```

## GitHub API Functions Added

- `Deploy.GitHub.list_prs/4` — `GET /repos/{owner}/{repo}/pulls` with `base` and `state` filters
- `Deploy.GitHub.get_pr/4` — `GET /repos/{owner}/{repo}/pulls/{number}`
- `Deploy.GitHub.update_branch/4` — `PUT /repos/{owner}/{repo}/pulls/{number}/update-branch`

## Future Work

- `CollectPRMetadata` step for enriched PR data (author, linked issues, labels)
- Configurable merge method (squash/merge/rebase)
- CI status pre-check before merge
- Label-based filtering for auto-discovery
- `PartialMergeError` struct for structured partial failure reporting
- Merge ordering policy (by creation date, PR number, etc.)
