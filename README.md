# Deploy

An Elixir tool that automates the deployment workflow using Ash Reactor for saga orchestration.

## Setup

```bash
# Install dependencies
mix setup

# Set required environment variables
export DEPLOY_REPO_URL="https://github.com/yourorg/yourrepo.git"
export GITHUB_TOKEN="ghp_xxxx"
```

## Usage

### Mix Task

The primary interface is the `mix deploy` task:

```bash
# Deploy specific PRs
mix deploy 12 13

# Deploy with all validation skipped (for testing)
mix deploy 12 13 --skip-validation

# Skip specific checks
mix deploy 12 13 --skip-reviews --skip-ci

# Resume a failed deploy
mix deploy 12 13 --resume

# Force restart (delete existing branch and start fresh)
mix deploy 12 13 --force

# Request review from specific users
mix deploy 12 13 --reviewers alice,bob
```

### Options

| Option | Description |
|--------|-------------|
| `--skip-reviews` | Skip approval validation |
| `--skip-ci` | Skip CI validation |
| `--skip-conflicts` | Skip merge conflict validation |
| `--skip-validation` | Skip all validation checks |
| `--reviewers USER,USER` | Comma-separated list of reviewers |
| `--resume` | Resume from existing deploy branch state |
| `--force` | Delete existing deploy branch and start fresh |

### Programmatic API

```elixir
# Full deployment
Deploy.Runner.deploy_pr(
  pr_numbers: [12, 13],
  reviewers: ["alice", "bob"],
  skip_validation: true
)

# Just setup phase
Deploy.Runner.setup()

# Just merge phase
Deploy.Runner.merge_prs(pr_numbers: [12, 13])

# Check deploy state
Deploy.Runner.check_deploy_state()
```

## Validation

Before merging PRs, the tool validates:

1. **Approval** - At least one approved review, no outstanding change requests
2. **CI Status** - All checks completed successfully
3. **Merge Conflicts** - PR is mergeable (checked before each merge)

Validation can be skipped individually or entirely using the skip options.

## Testing

```bash
mix test
```
