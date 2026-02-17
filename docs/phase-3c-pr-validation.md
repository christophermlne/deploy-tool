# PR Validation Before Merge

## Overview

This document specifies a `ValidatePRs` step to be added to the MergePRs reactor. The step validates that each PR is ready to merge before attempting any merges, failing fast with actionable error messages.

## Problem

Currently, when specific PR numbers are provided via `pr_numbers: [12, 13]`, the tool fetches them without validation and attempts to merge. This can fail mid-way through the merge process if:
- A PR has no approving review
- A PR has failing CI checks
- A PR has merge conflicts with the base branch

Failing mid-merge is problematic because:
1. Some PRs may already be merged (can't be undone)
2. PR bases have been changed to the deploy branch (compensation reverts this, but it's noisy)
3. The user gets a cryptic GitHub API error instead of a clear validation failure

## Solution

Add a `ValidatePRs` step that runs after `FetchApprovedPRs` and before `ChangePRBases`. This step validates all PRs upfront and fails with a structured error if any PR is not ready.

## Validation Checks

### 1. Approval Check

**Requirement:** At least one `APPROVED` review with no outstanding `CHANGES_REQUESTED`.

**Implementation:** Use existing `Deploy.GitHub.pr_approved?/4`.

**Failure reason:** `:no_approval` or `:changes_requested`

### 2. CI Check

**Requirement:** All CI check runs have completed with `success` conclusion.

**Implementation:** Use existing `Deploy.GitHub.ci_status/4` which returns:
- `:pending` — checks still running
- `:success` — all passed
- `{:failed, failed_runs}` — some failed

**Failure reasons:**
- `:ci_pending` — checks still running
- `{:ci_failed, check_names}` — specific checks failed

### 3. Merge Conflict Check

**Requirement:** PR's `mergeable` field is `true`.

**Implementation:** Use `Deploy.GitHub.get_pr/4` and check `mergeable` field.

**Note:** GitHub computes `mergeable` asynchronously. If `mergeable` is `nil`, poll with a short timeout before failing.

**Failure reason:** `:merge_conflict`

---

## Skip Options

All validation checks can be skipped via options passed to `Deploy.Runner.deploy_pr/1`:

```elixir
# Skip individual checks
Deploy.Runner.deploy_pr(
  pr_numbers: [12, 13],
  skip_reviews: true       # Skip approval check
)

Deploy.Runner.deploy_pr(
  pr_numbers: [12, 13],
  skip_ci: true            # Skip CI check
)

Deploy.Runner.deploy_pr(
  pr_numbers: [12, 13],
  skip_conflicts: true     # Skip mergeable check (use with caution)
)

# Skip all validation
Deploy.Runner.deploy_pr(
  pr_numbers: [12, 13],
  skip_validation: true    # Skip all checks
)
```

**Rationale for skip options:**
- `skip_reviews` — Useful for emergency deploys or when deploying your own PRs
- `skip_ci` — Useful when CI is flaky or a known-failing check is acceptable
- `skip_conflicts` — Rarely needed; conflicts usually mean something is wrong
- `skip_validation` — Convenience shortcut for "just merge these, I know what I'm doing"

---

## Inputs

The `ValidatePRs` step receives:

| Input | Type | Description |
|-------|------|-------------|
| `client` | Req client | GitHub API client |
| `owner` | string | GitHub org/owner |
| `repo` | string | Repository name |
| `prs` | list | PRs from FetchApprovedPRs step |
| `skip_reviews` | boolean | Skip approval validation (default: `false`) |
| `skip_ci` | boolean | Skip CI validation (default: `false`) |
| `skip_conflicts` | boolean | Skip mergeable validation (default: `false`) |

## Output

On success:
```elixir
{:ok, prs}  # Returns the same PR list, validated
```

On failure:
```elixir
{:error, %Deploy.ValidationError{
  message: "2 PRs failed validation",
  failures: [
    %{number: 12, title: "Add auth", reasons: [:no_approval]},
    %{number: 13, title: "Fix bug", reasons: [:ci_pending, :merge_conflict]}
  ]
}}
```

---

## Step Implementation

### Module: `Deploy.Reactors.Steps.ValidatePRs`

```elixir
defmodule Deploy.Reactors.Steps.ValidatePRs do
  use Reactor.Step
  require Logger

  @impl true
  def run(arguments, _context, _options) do
    client = arguments.client
    owner = arguments.owner
    repo = arguments.repo
    prs = arguments.prs

    skip_reviews = Map.get(arguments, :skip_reviews, false)
    skip_ci = Map.get(arguments, :skip_ci, false)
    skip_conflicts = Map.get(arguments, :skip_conflicts, false)

    Logger.info("Validating #{length(prs)} PRs before merge")

    results = Enum.map(prs, fn pr ->
      reasons = validate_pr(client, owner, repo, pr, skip_reviews, skip_ci, skip_conflicts)
      {pr, reasons}
    end)

    failures = Enum.filter(results, fn {_pr, reasons} -> reasons != [] end)

    if failures == [] do
      Logger.info("All PRs passed validation")
      {:ok, prs}
    else
      failure_details = Enum.map(failures, fn {pr, reasons} ->
        %{number: pr.number, title: pr.title, reasons: reasons}
      end)

      Logger.error("#{length(failures)} PRs failed validation: #{inspect(failure_details)}")
      {:error, %{validation_failures: failure_details}}
    end
  end

  defp validate_pr(client, owner, repo, pr, skip_reviews, skip_ci, skip_conflicts) do
    []
    |> maybe_check_approval(client, owner, repo, pr.number, skip_reviews)
    |> maybe_check_ci(client, owner, repo, pr.head_ref, skip_ci)
    |> maybe_check_conflicts(client, owner, repo, pr.number, skip_conflicts)
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
      {:ok, :success} -> reasons
      {:ok, :pending} -> [:ci_pending | reasons]
      {:ok, {:failed, failed_runs}} ->
        names = Enum.map(failed_runs, & &1["name"])
        [{:ci_failed, names} | reasons]
      {:error, _} -> [:ci_check_failed | reasons]
    end
  end

  defp maybe_check_conflicts(reasons, _client, _owner, _repo, _pr_number, true), do: reasons
  defp maybe_check_conflicts(reasons, client, owner, repo, pr_number, false) do
    case poll_mergeable(client, owner, repo, pr_number) do
      {:ok, true} -> reasons
      {:ok, false} -> [:merge_conflict | reasons]
      {:error, _} -> [:conflict_check_failed | reasons]
    end
  end

  # Poll for mergeable status (GitHub computes this asynchronously)
  defp poll_mergeable(client, owner, repo, pr_number, attempts \\ 5) do
    case Deploy.GitHub.get_pr(client, owner, repo, pr_number) do
      {:ok, %{"mergeable" => true}} -> {:ok, true}
      {:ok, %{"mergeable" => false}} -> {:ok, false}
      {:ok, %{"mergeable" => nil}} when attempts > 0 ->
        Process.sleep(1_000)
        poll_mergeable(client, owner, repo, pr_number, attempts - 1)
      {:ok, %{"mergeable" => nil}} -> {:ok, false}  # Assume conflict if still nil
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def compensate(_result, _arguments, _context, _options), do: :ok
end
```

---

## Reactor Changes

### File: `lib/reactors/merge_prs.ex`

Add the validation step and wire up skip options:

```elixir
defmodule Deploy.Reactors.MergePRs do
  use Reactor

  input :deploy_branch
  input :workspace
  input :client
  input :owner
  input :repo
  input :pr_numbers

  # New inputs for validation skip options
  input :skip_reviews, default: false
  input :skip_ci, default: false
  input :skip_conflicts, default: false
  input :skip_validation, default: false

  step :fetch_approved_prs, Deploy.Reactors.Steps.FetchApprovedPRs do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :pr_numbers, input(:pr_numbers)
  end

  # NEW: Validation step
  step :validate_prs, Deploy.Reactors.Steps.ValidatePRs do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :prs, result(:fetch_approved_prs)
    argument :skip_reviews, input(:skip_reviews)
    argument :skip_ci, input(:skip_ci)
    argument :skip_conflicts, input(:skip_conflicts)
    argument :skip_validation, input(:skip_validation)
  end

  step :change_pr_bases, Deploy.Reactors.Steps.ChangePRBases do
    argument :client, input(:client)
    argument :owner, input(:owner)
    argument :repo, input(:repo)
    argument :prs, result(:validate_prs)  # Changed from fetch_approved_prs
    argument :deploy_branch, input(:deploy_branch)
  end

  # ... rest unchanged
end
```

---

## Runner Changes

### File: `lib/runner.ex`

Accept skip options and pass them through:

```elixir
def merge_prs(opts \\ []) do
  pr_numbers = Keyword.get(opts, :pr_numbers, [])

  # Validation skip options
  skip_validation = Keyword.get(opts, :skip_validation, false)
  skip_reviews = skip_validation || Keyword.get(opts, :skip_reviews, false)
  skip_ci = skip_validation || Keyword.get(opts, :skip_ci, false)
  skip_conflicts = skip_validation || Keyword.get(opts, :skip_conflicts, false)

  with {:ok, %{branch: branch, workspace: workspace}} <- setup(opts) do
    inputs = %{
      deploy_branch: branch,
      workspace: workspace,
      client: Deploy.GitHub.client(Config.github_token()),
      owner: Config.github_owner(),
      repo: Config.github_repo(),
      pr_numbers: pr_numbers,
      skip_reviews: skip_reviews,
      skip_ci: skip_ci,
      skip_conflicts: skip_conflicts
    }

    # ... rest unchanged
  end
end

def deploy_pr(opts \\ []) do
  # Same skip options flow through to merge_prs
  # ... existing code
end
```

---

## Error Formatting

For CLI output, format validation failures clearly:

```
Validation failed for 2 PRs:

  PR #12: Add user authentication
    - No approving review

  PR #13: Fix payment bug
    - CI pending (checks still running)
    - Merge conflict with base branch

To skip validation, use:
  Deploy.Runner.deploy_pr(pr_numbers: [12, 13], skip_validation: true)
```

---

## Testing Considerations

### Unit Tests (`test/reactors/steps/validate_prs_test.exs`)

1. **All PRs pass validation** — Returns unchanged PR list
2. **One PR fails approval** — Returns structured error
3. **Multiple PRs fail different checks** — Aggregates all failures
4. **Skip options work** — Each skip option bypasses its check
5. **Mergeable polling** — Handles `nil` → `true` after delay
6. **Mergeable timeout** — Treats persistent `nil` as conflict

### Integration Tests

1. **Validation before merge** — Verify step runs before ChangePRBases
2. **Compensation not needed** — Validation failure doesn't trigger other compensation
3. **Skip options pass through** — Runner options reach the step

---

## Open Questions

1. **Should we allow partial merges?** Currently, if any PR fails validation, none are merged. Should there be an option to merge the valid ones and report failures?

2. **CI check depth** — Should we check CI on the PR's head commit or the merge commit? Head is simpler but merge commit is more accurate.

3. **Required checks only?** — Should we only validate required checks (from branch protection) or all checks?

4. **Approval count** — Some teams require 2+ approvals. Should this be configurable?
