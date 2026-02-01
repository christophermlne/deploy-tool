# Deploy Tool Handoff Document

## Project Overview

This is an Elixir application that automates a tedious, manual deployment workflow. The tool uses **Ash Reactor** (a saga orchestrator) to coordinate multi-step deployment processes with proper compensation (rollback) handling when steps fail.

### The Problem

Our current deployment workflow requires extensive manual work:

1. Pull the latest `staging` branch
2. Create a new branch named `deploy-YYYYMMDD` from staging
3. Push the deploy branch to GitHub
4. Change the base branch of all approved PRs to the deploy branch
5. Merge the approved PRs one-by-one into the deploy branch
6. Create a PR for the deploy branch targeting staging
7. Edit the deploy PR description to reference all merged PRs
8. Pull the deploy branch locally
9. Add a commit bumping the version number (changes 3 files)
10. Push the deploy branch again
11. Assign a reviewer and wait for CI
12. When approved and CI is green, merge the deploy PR
13. Copy the GitHub Action run link to a specific Slack channel
14. Monitor deployment until complete
15. When the GitHub Action creates a release, manually edit the release description to include links to all PRs and resolved issues
16. Post the release description as a Slack sub-thread with post-release checklist items

### The Solution

An Elixir application using Reactor to orchestrate these steps as a saga, with:
- Automatic rollback/compensation when steps fail
- GitHub API integration for PR manipulation
- Git CLI integration for repository operations
- Slack webhook integration for notifications
- LiveView dashboard for observability (planned)

---

## Architecture

### Key Design Decisions

1. **Temp folder for repo operations**: Each deployment clones the repo into a unique temp directory (`/tmp/deploy-{timestamp}-{unique_id}`). This provides isolation, predictability, and easy cleanup.

2. **GitHub REST API over CLI**: We use the GitHub REST API directly (via `Req`) rather than the `gh` CLI. This gives us structured error handling, cleaner authentication, and easier testing.

3. **Git CLI via System.cmd**: For actual git operations (clone, checkout, commit, push), we shell out to git. It's battle-tested and handles edge cases well.

4. **Dependency injection for testing**: Each Reactor step accepts its dependencies (git, file system) via options, defaulting to real implementations. Tests inject Mox mocks.

5. **Behaviours for mockable modules**: `Deploy.Git`, `Deploy.FileSystem`, and `Deploy.HTTP` define behaviours that Mox can mock.

### Project Structure

```
deploy_tool/
├── mix.exs
├── test/
│   ├── test_helper.exs
│   └── deploy/
│       ├── github_test.exs
│       └── reactors/steps/
│           ├── create_workspace_test.exs
│           ├── clone_repo_test.exs
│           ├── git_fetch_test.exs
│           ├── create_deploy_branch_test.exs
│           └── git_push_test.exs
└── lib/deploy/
    ├── application.ex
    ├── config.ex
    ├── runner.ex
    ├── git.ex                 # Git CLI wrapper + behaviour
    ├── file_system.ex         # File operations wrapper + behaviour
    ├── http.ex                # HTTP wrapper + behaviour
    ├── github.ex              # GitHub API client
    └── reactors/
        ├── setup.ex           # Setup phase reactor
        └── steps/
            ├── create_workspace.ex
            ├── clone_repo.ex
            ├── git_fetch.ex
            ├── create_deploy_branch.ex
            └── git_push.ex
```

### Reactor Pattern

Each reactor is a module that declares:
- **Inputs**: Values passed in when running the reactor
- **Steps**: Individual operations with their dependencies
- **Return**: The final output value

Each step module implements:
- `run/3`: Execute the step, return `{:ok, result}` or `{:error, reason}`
- `compensate/4`: Undo the step if a later step fails

Example step flow for setup phase:
```
create_workspace → clone_repo → fetch_staging → create_deploy_branch → push_deploy_branch
```

If `push_deploy_branch` fails, compensation runs in reverse:
```
(push failed, no compensation needed) → delete local branch → (fetch is read-only) → (clone handled by workspace) → delete workspace directory
```

---

## What's Implemented

### Setup Phase (Complete)

The `Deploy.Reactors.Setup` reactor handles:
- Creating a temporary workspace
- Cloning the repository with token auth
- Fetching the latest staging branch
- Creating the deploy branch
- Pushing the deploy branch to origin

All steps have compensation logic and are fully tested.

### GitHub API Client (Partial)

`Deploy.GitHub` has functions for:
- `change_pr_base/5` - Retarget a PR to a new base branch
- `merge_pr/5` - Merge a PR (supports squash, merge, rebase)
- `create_pr/4` - Create a new PR
- `update_pr/5` - Update PR title/body
- `get_check_runs/4` - Get CI status for a ref
- `ci_status/4` - High-level CI status check (pending/success/failed)
- `request_review/5` - Request reviewers on a PR
- `get_reviews/4` - Get PR reviews
- `pr_approved?/4` - Check if PR is approved
- `update_release/5` - Update release description
- `get_release_by_tag/4` - Get a release by tag name

Tests use Req's adapter pattern for HTTP mocking.

### Wrapper Modules (Complete)

- `Deploy.Git` - Wraps `System.cmd("git", ...)` for mockability
- `Deploy.FileSystem` - Wraps `File` operations for mockability
- `Deploy.HTTP` - Wraps `Req` operations for mockability

---

## What Needs Implementation

### Phase 2: PR Manipulation

Create `Deploy.Reactors.MergePRs` reactor with steps:

1. **FetchApprovedPRs** - Query GitHub for approved PRs targeting staging
2. **ChangePRBases** - Retarget each PR to the deploy branch
3. **MergePRs** - Merge each PR sequentially into deploy branch
4. **CollectMergedPRInfo** - Gather PR numbers, titles, linked issues for later use

Compensation considerations:
- Changing PR base is reversible (change back to staging)
- Merging PRs is NOT reversible - this is a "point of no return"

### Phase 3: Deploy PR Creation

Create `Deploy.Reactors.CreateDeployPR` reactor with steps:

1. **BumpVersion** - Update version in 3 files (need to identify which files)
2. **CommitVersionBump** - Commit the version changes
3. **PushVersionBump** - Push to deploy branch
4. **CreatePullRequest** - Create PR from deploy branch to staging
5. **UpdatePRDescription** - Add links to all merged PRs
6. **RequestReview** - Assign reviewer(s)

### Phase 4: CI and Merge

Create `Deploy.Reactors.WaitAndMerge` reactor with steps:

1. **WaitForCI** - Poll CI status until complete (needs timeout/retry logic)
2. **WaitForApproval** - Poll for PR approval
3. **MergeDeployPR** - Merge the deploy PR to staging

This phase needs careful handling:
- Polling with exponential backoff
- Configurable timeouts
- Possible human intervention points (approval)

### Phase 5: Notifications and Release

Create `Deploy.Reactors.PostDeploy` reactor with steps:

1. **PostDeployLinkToSlack** - Post GitHub Action run link to Slack channel
2. **WaitForRelease** - Poll for release creation by GitHub Action
3. **UpdateReleaseDescription** - Add PR links and issue links to release
4. **PostReleaseToSlack** - Post release notes as Slack thread with checklist

Needs:
- `Deploy.Slack` module for webhook integration
- Release description template (PRs + issues + checklist)

### Observability (Optional but Recommended)

Add a Phoenix LiveView dashboard showing:
- Current deployment status
- Step progress (pending/running/complete/failed)
- Timing information
- Error details if failed

Implementation approach:
1. Attach Telemetry handler at app startup to listen for Reactor events
2. Broadcast events to Phoenix.PubSub with deployment ID as topic
3. LiveView subscribes to topic and updates assigns
4. Render timeline/checklist view

Reactor emits telemetry events for:
- Reactor start/stop/halt
- Step start/complete/fail
- Compensation start/complete/fail

### Configuration

The current `Deploy.Config` module needs expansion:
- Version file paths (the 3 files that contain version numbers)
- Slack channel/webhook configuration
- Reviewer usernames
- Timeouts for CI/approval polling
- Post-release checklist items

Consider using runtime configuration or a config file.

---

## Technical Notes

### Running the Project

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run setup phase (requires env vars)
export DEPLOY_REPO_URL="https://github.com/yourorg/yourrepo.git"
export GITHUB_TOKEN="ghp_xxxx"
mix deploy
```

### Key Dependencies

- `reactor` (~> 0.10) - Saga orchestrator from Ash
- `req` (~> 0.5) - HTTP client
- `jason` (~> 1.4) - JSON parsing
- `mox` (~> 1.0, test only) - Mocking

### Testing Patterns

**Step tests** use Mox:
```elixir
Deploy.GitMock
|> expect(:cmd, fn args, opts -> {"output", 0} end)

StepModule.run(arguments, %{}, git: Deploy.GitMock)
```

**GitHub client tests** use Req's adapter:
```elixir
client = Req.new(
  adapter: fn request ->
    {request, Req.Response.new(status: 200, body: %{...})}
  end
)
```

### Compensation Best Practices

1. Compensation should be idempotent (safe to run multiple times)
2. Compensation should not fail the reactor - log and continue
3. Mark steps that are "point of no return" (merges) - after these, failures become alerts, not rollbacks

### Token Security

- Never log GitHub tokens - use `String.replace(output, token, "[REDACTED]")`
- Token is injected into clone URL as userinfo: `https://TOKEN@github.com/...`

---

## Open Questions

1. **Which 3 files contain the version number?** Need paths and format (e.g., `mix.exs`, `package.json`, etc.)

2. **What's the Slack channel/webhook setup?** Need webhook URL and channel name.

3. **Who are the default reviewers?** GitHub usernames for the deploy PR.

4. **What's in the post-release checklist?** The 4-5 items mentioned.

5. **How should we handle the "point of no return"?** After PRs are merged, we can't auto-rollback. Options:
   - Just alert and stop
   - Continue to notification phase anyway
   - Human intervention required

6. **Do we need to support concurrent deployments?** Current design allows it (unique workspace per run), but may want to add locking.

7. **Should the tool run as a long-lived service or CLI?** Currently structured for one-off runs, but could be wrapped in a GenServer for scheduled/triggered deployments.

---

## Suggested Next Steps

1. **Complete Phase 2 (PR Manipulation)** - This is the next logical piece and will validate the architecture for multi-PR operations.

2. **Add integration tests** - Test against a real (test) repository to verify git operations work end-to-end.

3. **Implement Slack module** - Simple webhook POST, will be needed for phases 5.

4. **Add version bumping logic** - Once we know which files to modify.

5. **Build the full orchestrator** - A top-level reactor that composes all phases.

---

## File Reference

All implementation files are in the `deploy_tool/` directory. Key files to review:

- `lib/deploy/reactors/setup.ex` - Example reactor structure
- `lib/deploy/reactors/steps/create_workspace.ex` - Example step with compensation
- `lib/deploy/github.ex` - GitHub API patterns
- `test/deploy/reactors/steps/clone_repo_test.exs` - Example Mox test
- `test/deploy/github_test.exs` - Example Req adapter test
