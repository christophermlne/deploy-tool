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

## Inputs

The Phase 2 reactor should receive:

| Input | Type | Description |
|-------|------|-------------|
| `workspace` | string | Path to the cloned repo (from Phase 1) |
| `deploy_branch` | string | Name of deploy branch, e.g., `deploy-20260123` |
| `github_token` | string | GitHub API token |
| `owner` | string | GitHub org/owner name |
| `repo` | string | GitHub repository name |
| `pr_numbers` | list (optional) | Specific PRs to include, or nil to auto-discover |

## Outputs

The reactor should return a map containing:

```elixir
%{
  merged_prs: [
    %{
      number: 42,
      title: "Add user authentication",
      author: "developer1",
      url: "https://github.com/org/repo/pull/42",
      linked_issues: [123, 456]  # Issue numbers closed by this PR
    },
    # ... more PRs
  ],
  deploy_branch: "deploy-20260123",
  head_sha: "abc123..."  # SHA of deploy branch after all merges
}
```

This output is used by Phase 3 to populate the deploy PR description.

## Steps

### Step 1: FetchApprovedPRs

**Purpose**: Get a list of PRs that are approved and ready to merge.

**Logic**:
1. Query GitHub API for open PRs targeting `staging` (or `main`, depending on your workflow)
2. For each PR, check if it has at least one approval and no "changes requested"
3. Optionally filter by labels (e.g., `ready-to-deploy`)
4. Return list of PR numbers and metadata

**GitHub API calls**:
```
GET /repos/{owner}/{repo}/pulls?state=open&base=staging
GET /repos/{owner}/{repo}/pulls/{pr_number}/reviews
```

**Compensation**: None needed (read-only operation)

**Edge cases**:
- No approved PRs found → Return empty list, reactor should handle gracefully
- PR approved but CI failing → Decide policy: skip or include? (recommend: skip with warning)
- PR has merge conflicts with staging → Will fail at merge step

**Output**: List of PR metadata maps

---

### Step 2: ChangePRBases

**Purpose**: Retarget each approved PR from `staging` to the deploy branch.

**Logic**:
1. For each PR from Step 1, call GitHub API to change base branch
2. Collect results, noting any failures
3. If any fail, may need to decide: abort all or continue with successful ones

**GitHub API calls**:
```
PATCH /repos/{owner}/{repo}/pulls/{pr_number}
Body: {"base": "deploy-20260123"}
```

**Compensation**: 
- Change each PR's base back to `staging`
- Must track which PRs were successfully changed to know what to revert

**Edge cases**:
- PR was closed/merged between Step 1 and Step 2 → Skip with warning
- PR has conflicts with deploy branch → API will still succeed (conflicts checked at merge time)
- Rate limiting → Implement retry with backoff

**Output**: Map of `pr_number => {:ok, pr_data} | {:error, reason}`

---

### Step 3: MergePRs

**Purpose**: Merge each retargeted PR into the deploy branch.

**⚠️ POINT OF NO RETURN**: Once a PR is merged, it cannot be automatically undone. The reactor should clearly mark this boundary.

**Logic**:
1. For each PR (in order), attempt to merge via GitHub API
2. Use squash merge (configurable) for cleaner history
3. After each merge, pull the deploy branch locally to stay in sync
4. If a merge fails, stop and report (don't continue with remaining PRs)

**GitHub API calls**:
```
PUT /repos/{owner}/{repo}/pulls/{pr_number}/merge
Body: {"merge_method": "squash", "commit_title": "PR title (#number)"}
```

**Local git operations** (after each merge):
```bash
git fetch origin deploy-20260123
git reset --hard origin/deploy-20260123
```

**Compensation**:
- **Cannot automatically compensate merged PRs**
- Options:
  1. Alert and require manual intervention
  2. Create a revert commit (risky, changes history)
  3. Delete deploy branch and start over (loses all merges)
- Recommended: Alert, log what was merged, stop the reactor

**Edge cases**:
- Merge conflicts → Stop, report which PR conflicted, require manual resolution
- CI required but not passing → GitHub API will reject merge (if branch protection enabled)
- PR was already merged → Skip with warning
- PR was closed → Skip with warning

**Output**: List of successfully merged PR numbers and their merge commits

---

### Step 4: CollectPRMetadata

**Purpose**: Gather detailed information about merged PRs for the deploy PR description.

**Logic**:
1. For each merged PR, fetch:
   - Title, number, author
   - Linked issues (from PR body or GitHub's linked issues)
   - Labels
2. Format into a structure for Phase 3

**GitHub API calls**:
```
GET /repos/{owner}/{repo}/pulls/{pr_number}
GET /repos/{owner}/{repo}/issues/{pr_number}/timeline  # For linked issues
```

Or use GraphQL for efficiency:
```graphql
query {
  repository(owner: "org", name: "repo") {
    pullRequest(number: 42) {
      title
      number
      author { login }
      closingIssuesReferences(first: 10) {
        nodes { number title }
      }
    }
  }
}
```

**Compensation**: None needed (read-only)

**Output**: Enriched PR metadata list

---

### Step 5: UpdateLocalBranch

**Purpose**: Ensure local workspace has the final state of the deploy branch.

**Logic**:
```bash
git fetch origin deploy-20260123
git checkout deploy-20260123
git reset --hard origin/deploy-20260123
```

**Compensation**: None needed

**Output**: Final HEAD SHA of deploy branch

---

## Reactor Definition Sketch

```elixir
defmodule Deploy.Reactors.MergePRs do
  use Reactor

  input :workspace
  input :deploy_branch
  input :github_token
  input :owner
  input :repo
  input :pr_numbers  # optional, nil = auto-discover

  step :fetch_approved_prs, Deploy.Reactors.Steps.FetchApprovedPRs do
    argument :github_token, input(:github_token)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :explicit_prs, input(:pr_numbers)
  end

  step :change_pr_bases, Deploy.Reactors.Steps.ChangePRBases do
    argument :github_token, input(:github_token)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :deploy_branch, input(:deploy_branch)
    argument :prs, result(:fetch_approved_prs)
  end

  # Mark point of no return - consider a custom step that logs/confirms
  step :confirm_point_of_no_return, Deploy.Reactors.Steps.ConfirmNoReturn do
    argument :prs_to_merge, result(:change_pr_bases)
    wait_for :change_pr_bases
  end

  step :merge_prs, Deploy.Reactors.Steps.MergePRs do
    argument :github_token, input(:github_token)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :workspace, input(:workspace)
    argument :prs, result(:change_pr_bases)
    
    wait_for :confirm_point_of_no_return
  end

  step :collect_metadata, Deploy.Reactors.Steps.CollectPRMetadata do
    argument :github_token, input(:github_token)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :merged_prs, result(:merge_prs)
  end

  step :update_local, Deploy.Reactors.Steps.UpdateLocalBranch do
    argument :workspace, input(:workspace)
    argument :deploy_branch, input(:deploy_branch)
    
    wait_for :merge_prs
  end

  return :collect_metadata
end
```

## Error Handling Strategy

### Before Point of No Return

If any step fails before `merge_prs`:
1. Compensation runs automatically (revert PR base changes)
2. Reactor returns error with details
3. User can fix issues and retry

### After Point of No Return

If `merge_prs` or later steps fail:
1. **Do NOT attempt to compensate merged PRs**
2. Log exactly which PRs were successfully merged
3. Log which PR failed and why
4. Return a structured error that includes:
   - Successfully merged PRs
   - Failed PR and error
   - Current state of deploy branch
5. Require manual intervention

### Suggested Error Structure

```elixir
{:error, %Deploy.PartialMergeError{
  merged_prs: [41, 42, 43],
  failed_pr: 44,
  failure_reason: "Merge conflict in lib/foo.ex",
  deploy_branch: "deploy-20260123",
  deploy_branch_sha: "abc123",
  recovery_instructions: "Resolve conflicts manually or delete deploy branch to restart"
}}
```

## Testing Considerations

### Unit Tests (with Mox)

- `FetchApprovedPRs`: Mock GitHub API responses for various scenarios
- `ChangePRBases`: Test success, partial failure, already-closed PRs
- `MergePRs`: Test success, conflict failure, already-merged

### Integration Tests

Consider a test repository with:
- Pre-created branches and PRs
- Tests that create PRs, run the reactor, verify merges
- Cleanup in test teardown

### Manual Testing Checklist

- [ ] No approved PRs → Handles gracefully
- [ ] Single approved PR → Works end to end
- [ ] Multiple approved PRs → Merges in order
- [ ] PR with merge conflict → Fails gracefully, reports which PR
- [ ] PR closed during process → Skips with warning
- [ ] Network failure mid-process → Compensation works (before merge)
- [ ] Network failure after merge → Proper error state reported

## Configuration Options

Consider making these configurable:

```elixir
config :deploy,
  merge_method: :squash,           # :squash | :merge | :rebase
  require_ci_pass: true,           # Skip PRs with failing CI?
  required_labels: ["ready-to-deploy"],  # Filter PRs by label
  auto_discover_prs: true,         # Or require explicit list
  merge_order: :created_asc        # Order to merge PRs
```

## Open Questions for Implementation

1. **Merge order**: Should PRs be merged in a specific order? (creation date, PR number, custom priority?)

2. **Partial success handling**: If PR 3 of 5 fails to merge, should we:
   - Stop immediately (current recommendation)
   - Try remaining PRs anyway
   - Let user configure behavior

3. **CI status check**: Should we verify CI passes before attempting merge, or let GitHub's branch protection handle it?

4. **Linked issues detection**: Use GitHub's automatic linking, parse PR body for `Fixes #123`, or both?

5. **Notification hooks**: Should this phase emit events/notifications for:
   - Each PR merged
   - Failures
   - Point of no return crossed

## Dependencies on Existing Code

This phase will use:
- `Deploy.GitHub.change_pr_base/5` ✅ (exists)
- `Deploy.GitHub.merge_pr/5` ✅ (exists)
- `Deploy.GitHub.get_reviews/4` ✅ (exists)
- `Deploy.GitHub.pr_approved?/4` ✅ (exists)
- `Deploy.Git.cmd/2` ✅ (exists)

May need to add:
- `Deploy.GitHub.list_prs/4` - List PRs with filters
- `Deploy.GitHub.get_pr/4` - Get single PR details
- `Deploy.GitHub.get_linked_issues/4` - Get issues linked to PR
