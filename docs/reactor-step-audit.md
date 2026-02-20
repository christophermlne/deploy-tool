# Reactor Step Improvement Report


## TL;DR

High priority: All rollback logic is in compensate/4 but should be in undo/4. compensate is for self-failure recovery; undo is for rolling back successful steps when a downstream step fails. Since no steps implement undo, Reactor may be skipping rollback entirely. The BumpVersionFiles.compensate even has a phantom clause that pattern-matches on the successful result shape, but compensate receives the error reason — so it never matches.

~~Medium priority: Argument destructuring in function heads (every step manually extracts from the map body), if/equality checks that should be pattern-matched function heads (RequestReview, FetchApprovedPRs, ValidatePRs), and O(n^2) list appending with acc ++ [item] in three steps.~~ **Done.**

~~Low priority: Redundant with/else pass-throughs, no-op compensate callbacks that can be removed,~~ unused DSL features (where/guard for conditional steps, collect instead of ReturnMap, backoff for API retries), ~~redundant wait_for directives, and git command pattern duplication across 7 steps.~~ **Partially done** — Elixir idiom and noise-reduction items are resolved; DSL feature adoption items remain open.

## Context

An audit of all 17 step files in `lib/reactors/steps/` and the 4 reactor compositions against the full capabilities of the Reactor library (`hexdocs.pm/reactor`). The goal: identify where the code could be more idiomatic — both in Reactor DSL usage and in Elixir language patterns.

---

## 1. `compensate` vs `undo` — Rollback Logic Is in the Wrong Callback

**This is the most significant finding.** Every step puts its rollback logic in `compensate/4`, but the Reactor library distinguishes between two different callbacks:

- **`compensate/4`** — called when **this step itself fails**. First argument is the **error reason**. Purpose: decide whether to retry, provide a fallback value, or accept the failure.
- **`undo/4`** — called when this step **succeeded** but a **later step fails**. First argument is the **successful result**. Purpose: reverse the side effects of this step.

Currently, the cleanup logic (deleting workspaces, closing PRs, reverting branches) lives in `compensate`, but it's undo behavior — it should only run when rolling back a *successful* step due to a *downstream* failure. The Reactor library auto-detects `undo` support via `can?/2`; since none of these steps implement `undo`, Reactor may skip rollback entirely for successful steps.

### Affected steps and what should change

| Step | Current `compensate` does | Should be `undo` because | `compensate` should |
|------|--------------------------|--------------------------|---------------------|
| `CreateWorkspace` | `File.rm_rf(workspace)` | Rolls back a successful mkdir | `:ok` or omit |
| `CloneRepo` | Returns `:ok` (no-op) | Correct as-is (workspace handles cleanup) | Omit entirely |
| `GitPush` | Deletes remote branch | Rolls back a successful push | `:ok` or omit |
| `CreateDeployBranch` | Deletes local branch | Rolls back successful branch creation | `:ok` or omit |
| `CommitVersionBump` | `git reset --hard HEAD~1` | Rolls back a successful commit | `:ok` or omit |
| `PushVersionBump` | `git push --force-with-lease` | Rolls back a successful push | `:ok` or omit |
| `ChangePRBases` | Retargets PRs back to staging | Rolls back successful base changes | `:ok` or omit |
| `CreateDeployPR` | Closes the PR | Rolls back a successful PR creation | `:ok` or omit |
| `BumpVersionFiles` | Restores old version files | Rolls back successful file writes | `:ok` or omit |

### Concrete example — `CreateDeployPR`

**Current:**
```elixir
@impl true
def compensate(%{number: pr_number}, arguments, _context, _options) do
  # This pattern-matches on the error reason, but the step returns
  # {:error, reason} where reason is a string — this clause never matches.
  # ...closes the PR...
end
```

**Recommended:**
```elixir
@impl true
def undo(%{number: pr_number}, arguments, _context, _options) do
  # First arg is the successful result — %{number: ..., url: ...}
  # This clause correctly matches.
  Logger.info("Undoing: closing deploy PR ##{pr_number}")
  case Deploy.GitHub.update_pr(client, owner, repo, pr_number, %{state: "closed"}) do
    {:ok, _} -> :ok
    {:error, _reason} -> :ok  # best-effort
  end
end
```

### Related: `BumpVersionFiles.compensate` has a phantom clause

```elixir
def compensate(%{old_version: old_version}, arguments, _context, _options) do
  # Tries to match the successful result shape, but compensate receives
  # the error reason. The step's errors are strings like "Failed to read
  # version file: ..." — this clause never matches.
end

def compensate(_result, _arguments, _context, _options), do: :ok
# ^ This fallback always wins
```

The first clause should be the first clause of `undo/4` instead.

---

## ~~2. Pattern Matching Over Conditionals~~ ✅ Done

### ~~2a. Destructure arguments in function heads~~ ✅

All `run/3` functions now destructure arguments in the function head rather than extracting in the body. Applied across all step files.

### ~~2b. Replace `if`/equality checks with pattern-matching function heads~~ ✅

- `RequestReview.run` — split into `%{reviewers: []}` and `%{reviewers: reviewers, ...}` heads
- `FetchApprovedPRs.run` — split into `%{pr_numbers: [_ | _] = pr_numbers, ...}` and fallback head
- `ValidatePRs.run` — split into `%{skip_validation: true, prs: prs}` and fallback head

### ~~2c. Replace `failures == []` with pattern match~~ ✅

`ValidatePRs.validate_all_prs` now pipes through `|> case do [] -> ...; failures -> ... end`.

---

## ~~3. Elixir Idioms~~ ✅ Done

### ~~3a. List building is O(n^2) — use prepend + reverse~~ ✅

`ChangePRBases`, `FetchApprovedPRs`, and `MergePRs` now use `[item | acc]` + `Enum.reverse` via a `|> then(fn ...)` wrapper around the `reduce_while`.

### ~~3b. Redundant `with/else` that just passes through errors~~ ✅

- `BumpVersionFiles.run` — removed redundant `else {:error, reason} -> {:error, reason}` block
- `CreateDeployPR.run` — replaced `case` with `with {:ok, body} <- ... do`

### ~~3c. Nested `case` → `with`~~ ✅

`GitFetch.run` — replaced nested `case` with a flat `with :ok <- Deploy.Git.run!(...)` chain.

### ~~3d. `CreateDeployPR.run` — unnecessary `case` wrapping~~ ✅

Replaced with `with {:ok, body} <- ... do` (covered in 3b above).

---

## 4. Reactor DSL Features Not Being Used

### 4a. `where` guards for conditional steps

Steps that skip execution based on a flag (like `RequestReview` when `reviewers` is empty, or `ValidatePRs` when `skip_validation` is true) could express this at the DSL level using `where`:

```elixir
# In the reactor composition
step :request_review, Deploy.Reactors.Steps.RequestReview do
  argument :reviewers, input(:reviewers)
  # ...
  where fn %{reviewers: reviewers} -> reviewers != [] end
end
```

This makes the conditional visible in the reactor definition rather than hidden inside the step, and the step code becomes simpler (no branching). The step's result when skipped would be `nil` by default, or you can use `guard` for more control:

```elixir
guard fn %{reviewers: reviewers}, _context ->
  if reviewers == [], do: {:halt, :skipped}, else: :cont
end
```

### 4b. `switch` for branching logic

`FetchApprovedPRs` has two code paths (fetch specific PRs vs discover approved PRs). This could be expressed as a `switch` in the reactor definition:

```elixir
switch :fetch_prs do
  on :pr_numbers

  matches? fn pr_numbers -> pr_numbers != [] end do
    step :fetch_specific, FetchSpecificPRs do ... end
  end

  default do
    step :discover_approved, DiscoverApprovedPRs do ... end
  end
end
```

Whether this is worth it depends on taste — the current single-step approach is simpler and perfectly fine. But it's worth knowing the option exists.

### 4c. `collect` instead of `ReturnMap`

The `ReturnMap` step exists solely to aggregate results into a map:

```elixir
defmodule Deploy.Reactors.Steps.ReturnMap do
  def run(arguments, _context, _options), do: {:ok, arguments}
end
```

Reactor has a built-in `collect` step that does exactly this — no custom module needed. (Note: verify `collect` is available in your version of Reactor before replacing.)

### 4d. Retries and backoff for transient errors

Every step has `max_retries 0`. Some steps interact with GitHub's API, which can return transient errors (rate limits, 502s, network blips). Consider allowing limited retries for API-calling steps with a `backoff/4` callback for exponential delay:

```elixir
# In reactor composition
step :create_deploy_pr, Deploy.Reactors.Steps.CreateDeployPR do
  # ...
  max_retries 2
end

# In the step module
@impl true
def backoff(attempt, _reason, _arguments, _context) do
  :timer.seconds(attempt * 2)  # 2s, 4s
end
```

Git operations and file system operations should remain at `max_retries 0` since those failures aren't transient.

### 4e. `compensate` returning `:retry` for transient GitHub errors

When a GitHub API call fails due to a transient error, `compensate` can return `:retry` to automatically retry the step:

```elixir
def compensate(%Req.TransportError{}, _arguments, _context, _options), do: :retry
def compensate(_reason, _arguments, _context, _options), do: :ok
```

This is more ergonomic than manual retry loops within the step.

### ~~4f. Redundant `wait_for` directives~~ ✅ Done

The redundant `wait_for :create_deploy_branch` was removed from `push_deploy_branch` in `setup.ex` — the `argument :branch, result(:create_deploy_branch)` already creates the dependency.

The remaining `wait_for` directives are NOT redundant:
- `setup.ex`: `fetch_staging` uses `wait_for :clone_repo` — no argument references `clone_repo`'s result
- `deploy_pr.ex`: `push_version_bump` uses `wait_for :commit_version_bump` — no argument references it

### 4g. Input transforms

Inputs can have transforms applied at declaration time. For example, if any inputs need normalization or defaulting, this can be done at the `input` level rather than in each step:

```elixir
input :pr_numbers, transform: {__MODULE__, :default_to_empty_list, []}
```

---

## ~~5. No-Op `compensate` Callbacks Can Be Removed~~ ✅ Done

No-op `compensate/4` callbacks removed from: `CloneRepo`, `FetchApprovedPRs`, `ValidatePRs`, `UpdateLocalBranch`, `UpdatePRDescription`, `ReturnMap`, `RequestReview`, `GitFetch`.

---

## ~~6. Git Command Pattern Duplication~~ ✅ Done

`Deploy.Git.run!/2` helper extracted and adopted in `GitPush`, `PushVersionBump`, `UpdateLocalBranch`, `CreateDeployBranch`, and `GitFetch`. `CloneRepo` still uses `cmd/2` directly because it needs to sanitize tokens from error output. `CommitVersionBump` still uses `cmd/2` because the `rev-parse HEAD` call needs the output value.

---

## Summary — Priority of Recommendations

| Priority | Category | Status |
|----------|----------|--------|
| **High** | Move rollback logic from `compensate` to `undo` | **Open** — rollback may not execute at all currently |
| ~~**Medium**~~ | ~~Destructure arguments in function heads~~ | ✅ Done |
| ~~**Medium**~~ | ~~Replace `if`/`==` with pattern-matched function heads~~ | ✅ Done |
| ~~**Medium**~~ | ~~Fix O(n^2) list appending~~ | ✅ Done |
| ~~**Low**~~ | ~~Remove redundant `with/else` passthroughs~~ | ✅ Done |
| ~~**Low**~~ | ~~Remove no-op `compensate` callbacks~~ | ✅ Done |
| **Low** | Consider `where`/`guard` for conditional steps | **Open** |
| **Low** | Consider retries + backoff for API steps | **Open** |
| ~~**Low**~~ | ~~Extract git command helper~~ | ✅ Done |
| **Low** | Replace `ReturnMap` with `collect` | **Open** |
| ~~**Low**~~ | ~~Remove redundant `wait_for`~~ | ✅ Done |
