# Reactor Step Improvement Report


## TL;DR

High priority: All rollback logic is in compensate/4 but should be in undo/4. compensate is for self-failure recovery; undo is for rolling back successful steps when a downstream step fails. Since no steps implement undo, Reactor may be skipping rollback entirely. The BumpVersionFiles.compensate even has a phantom clause that pattern-matches on the successful result shape, but compensate receives the error reason — so it never matches.

Medium priority: Argument destructuring in function heads (every step manually extracts from the map body), if/equality checks that should be pattern-matched function heads (RequestReview, FetchApprovedPRs, ValidatePRs), and O(n^2) list appending with acc ++ [item] in three steps.

Low priority: Redundant with/else pass-throughs, no-op compensate callbacks that can be removed, unused DSL features (where/guard for conditional steps, collect instead of ReturnMap, backoff for API retries), redundant wait_for directives, and git command pattern duplication across 7 steps.

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

## 2. Pattern Matching Over Conditionals

### 2a. Destructure arguments in function heads

Every `run/3` manually extracts arguments at the top of the function body:

```elixir
# Current — in 14 of 17 steps
def run(arguments, _context, _options) do
  workspace = arguments.workspace
  repo_url = arguments.repo_url
  token = arguments.github_token
  # ...
end
```

**Recommended — destructure in the function head:**
```elixir
def run(%{workspace: workspace, repo_url: repo_url, github_token: token}, _context, _options) do
  # ...
end
```

This is more idiomatic, fails fast with a clear `FunctionClauseError` on missing keys, and reduces boilerplate.

### 2b. Replace `if`/equality checks with pattern-matching function heads

**`RequestReview.run`** — `if reviewers == []`
```elixir
# Current
if reviewers == [] do
  {:ok, :skipped}
else
  Deploy.GitHub.request_review(...)
end

# Recommended — separate function heads
def run(%{reviewers: []}, _context, _options), do: {:ok, :skipped}

def run(%{reviewers: reviewers, client: client, owner: owner, repo: repo,
          pr_number: pr_number}, _context, _options) do
  Deploy.GitHub.request_review(client, owner, repo, pr_number, reviewers)
end
```

**`FetchApprovedPRs.run`** — `if pr_numbers != []`
```elixir
# Current
if pr_numbers != [] do
  fetch_specific_prs(...)
else
  discover_approved_prs(...)
end

# Recommended
def run(%{pr_numbers: [_ | _]} = args, _context, _options) do
  fetch_specific_prs(args.client, args.owner, args.repo, args.pr_numbers)
end

def run(%{pr_numbers: []} = args, _context, _options) do
  discover_approved_prs(args.client, args.owner, args.repo)
end
```

**`ValidatePRs.run`** — `if skip_validation`
```elixir
# Could use a function head or guard
def run(%{skip_validation: true, prs: prs}, _context, _options) do
  Logger.info("Skipping all PR validation")
  {:ok, prs}
end

def run(%{prs: prs} = args, _context, _options) do
  validate_all_prs(...)
end
```

### 2c. Replace `failures == []` with pattern match

In `ValidatePRs.validate_all_prs`:
```elixir
# Current
if failures == [] do ...

# Recommended
case failures do
  [] -> ...
  failures -> ...
end
```

---

## 3. Elixir Idioms

### 3a. List building is O(n^2) — use prepend + reverse

Three steps build lists with `acc ++ [item]` inside `Enum.reduce_while`. Appending to a linked list is O(n) per operation, making the total O(n^2). The idiomatic approach is prepend + reverse:

**Affected:** `ChangePRBases`, `FetchApprovedPRs`, `MergePRs`

```elixir
# Current
{:cont, {:ok, acc ++ [merged]}}

# Recommended
{:cont, {:ok, [merged | acc]}}
# ...then at the end:
{:ok, merged} -> {:ok, Enum.reverse(merged)}
```

For these step counts (probably <50 PRs) the performance impact is negligible, but it's a code-smell that signals unfamiliarity with list semantics to experienced Elixir readers.

### 3b. Redundant `with/else` that just passes through errors

Several steps have `with` chains where the `else` clause just returns the error unchanged:

```elixir
# Current — in BumpVersionFiles, and others
with {:ok, current_version} <- read_version(version_file),
     :ok <- update_version_files(workspace, new_version) do
  {:ok, result}
else
  {:error, reason} -> {:error, reason}  # This is what `with` does by default
end
```

When every non-matching clause is `{:error, reason}`, the `else` block can be dropped entirely — `with` already returns the first non-matching value as-is.

**Affected:** `BumpVersionFiles.run`, `CreateDeployPR.run` (the `case` that just passes through `{:error, reason}`)

### 3c. Nested `case` → `with`

`GitFetch.run` has a nested case that's a natural fit for `with`:

```elixir
# Current
case Deploy.Git.cmd(["fetch", ...]) do
  {_output, 0} ->
    case Deploy.Git.cmd(["reset", ...]) do
      {_output, 0} -> {:ok, branch}
      {output, exit_code} -> {:error, "Git reset failed..."}
    end
  {output, exit_code} -> {:error, "Git fetch failed..."}
end

# Recommended
with {_, 0} <- Deploy.Git.cmd(["fetch", ...], cd: workspace, stderr_to_stdout: true),
     {_, 0} <- Deploy.Git.cmd(["reset", "--hard", "origin/#{branch}"], cd: workspace, stderr_to_stdout: true) do
  {:ok, branch}
else
  {output, exit_code} ->
    {:error, "Git operation failed (exit #{exit_code}): #{output}"}
end
```

### 3d. `CreateDeployPR.run` — unnecessary `case` wrapping

```elixir
# Current
case Deploy.GitHub.create_pr(client, owner, repo, attrs) do
  {:ok, body} -> {:ok, %{number: body["number"], url: body["html_url"]}}
  {:error, reason} -> {:error, reason}
end

# Recommended — use `with` and transform
with {:ok, body} <- Deploy.GitHub.create_pr(client, owner, repo, attrs) do
  {:ok, %{number: body["number"], url: body["html_url"]}}
end
```

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

### 4f. Redundant `wait_for` directives

Several `wait_for` directives are redundant because the step already has an `argument` dependency on the same step:

```elixir
# In setup.ex — redundant wait_for
step :push_deploy_branch, Deploy.Reactors.Steps.GitPush do
  argument :branch, result(:create_deploy_branch)  # ← already creates dependency
  wait_for :create_deploy_branch                     # ← redundant
end
```

The Reactor automatically orders steps based on argument dependencies. `wait_for` is only needed when you need ordering *without* consuming a result. Removing the redundant ones reduces noise.

**Affected (possibly, verify by checking if any argument already references the waited-for step):**
- `setup.ex`: `push_deploy_branch` waits for `create_deploy_branch` but already uses `result(:create_deploy_branch)`
- `setup.ex`: `fetch_staging` uses `wait_for :clone_repo` — this one is NOT redundant since no argument references `clone_repo`'s result
- `deploy_pr.ex`: `push_version_bump` uses `wait_for :commit_version_bump` — NOT redundant, no argument references it

### 4g. Input transforms

Inputs can have transforms applied at declaration time. For example, if any inputs need normalization or defaulting, this can be done at the `input` level rather than in each step:

```elixir
input :pr_numbers, transform: {__MODULE__, :default_to_empty_list, []}
```

---

## 5. No-Op `compensate` Callbacks Can Be Removed

Both `compensate/4` and `undo/4` are optional callbacks in the Reactor.Step behaviour. Steps that return `:ok` unconditionally from `compensate` can simply omit the callback entirely:

**Affected (no-op compensate):** `CloneRepo`, `FetchApprovedPRs`, `ValidatePRs`, `UpdateLocalBranch`, `UpdatePRDescription`, `ReturnMap`, `RequestReview`

Removing boilerplate makes the meaningful compensation/undo logic stand out.

---

## 6. Git Command Pattern Duplication

Nearly every git-related step has the same pattern:

```elixir
case Deploy.Git.cmd(args, cd: workspace, stderr_to_stdout: true) do
  {_output, 0} -> {:ok, result}
  {output, exit_code} -> {:error, "Operation failed (exit #{exit_code}): #{output}"}
end
```

This appears in `CloneRepo`, `CreateDeployBranch`, `GitPush`, `GitFetch`, `CommitVersionBump`, `PushVersionBump`, `UpdateLocalBranch` — 7 of 17 steps. A small helper would reduce duplication:

```elixir
# In a shared module, e.g. Deploy.Git
def run!(args, opts) do
  case cmd(args, opts) do
    {_output, 0} -> :ok
    {output, code} -> {:error, "git #{hd(args)} failed (exit #{code}): #{output}"}
  end
end
```

---

## Summary — Priority of Recommendations

| Priority | Category | Impact |
|----------|----------|--------|
| **High** | Move rollback logic from `compensate` to `undo` | Rollback may not execute at all currently |
| **Medium** | Destructure arguments in function heads | Idiomatic, clearer contracts, better errors |
| **Medium** | Replace `if`/`==` with pattern-matched function heads | Idiomatic Elixir |
| **Medium** | Fix O(n^2) list appending | Code smell (perf is fine at current scale) |
| **Low** | Remove redundant `with/else` passthroughs | Noise reduction |
| **Low** | Remove no-op `compensate` callbacks | Noise reduction |
| **Low** | Consider `where`/`guard` for conditional steps | DSL expressiveness |
| **Low** | Consider retries + backoff for API steps | Resilience |
| **Low** | Extract git command helper | DRY |
| **Low** | Replace `ReturnMap` with `collect` | Use built-in |
| **Low** | Remove redundant `wait_for` | Noise reduction |
