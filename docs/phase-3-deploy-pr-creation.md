# Phase 3: Deploy PR Creation

## Overview

Phase 3 creates the deploy pull request. At this point, the deploy branch exists and contains all the merged feature PRs from Phase 2. This phase adds the version bump commit, creates the PR, populates its description with references to all included work, and requests review.

## Prerequisites

Phase 3 expects the following from earlier phases:

- A workspace with the cloned repo
- A deploy branch (e.g., `deploy-20260123`) that has been pushed to origin
- Metadata about merged PRs (numbers, titles, linked issues) from Phase 2

## Inputs

| Input | Description |
|-------|-------------|
| `workspace` | Path to the cloned repo |
| `deploy_branch` | Name of the deploy branch |
| `merged_prs` | List of PR metadata from Phase 2 (numbers, titles, authors, linked issues) |
| `github_token` | GitHub API token |
| `owner` | GitHub org/owner |
| `repo` | GitHub repository name |
| `reviewers` | List of GitHub usernames to request review from |

## Outputs

```elixir
%{
  pr_number: 99,
  pr_url: "https://github.com/org/repo/pull/99",
  version: "1.2.3",
  head_sha: "abc123..."
}
```

## Steps

### Step 1: DetermineNextVersion

**Purpose**: Figure out what the new version number should be.

**Considerations**:
- How is versioning handled? Semver? Date-based? Build number?
- Is version auto-incremented (patch bump) or specified as input?
- May need to read current version from a file first

**Output**: The new version string (e.g., `"1.2.3"` or `"2026.01.23"`)

---

### Step 2: BumpVersionFiles

**Purpose**: Update all files that contain the version number.

**You mentioned 3 files need updating**. Common patterns:
- `mix.exs` — `version: "x.y.z"` in project config
- `package.json` — `"version": "x.y.z"`
- A VERSION file or version module

**Logic**:
1. For each file, read contents
2. Find and replace version string (use regex or structured parsing)
3. Write updated contents

**Compensation**: Revert files to original content (or just rely on git checkout)

**Output**: List of modified file paths

---

### Step 3: CommitVersionBump

**Purpose**: Create a git commit with the version changes.

**Git operations**:
```bash
git add <file1> <file2> <file3>
git commit -m "Bump version to 1.2.3"
```

**Compensation**: `git reset --hard HEAD~1` (undo the commit)

**Output**: Commit SHA

---

### Step 4: PushVersionBump

**Purpose**: Push the version bump commit to the remote deploy branch.

**Git operations**:
```bash
git push origin deploy-20260123
```

**Compensation**: Force push to remove the commit (risky but possible)
```bash
git push origin deploy-20260123 --force-with-lease
```

**Output**: Updated remote ref

---

### Step 5: CreateDeployPR

**Purpose**: Create the pull request from deploy branch to staging (or main).

**GitHub API**:
```
POST /repos/{owner}/{repo}/pulls
{
  "title": "Deploy 2026-01-23",
  "head": "deploy-20260123",
  "base": "staging",
  "body": ""  // Will be populated in next step
}
```

**Compensation**: Close the PR
```
PATCH /repos/{owner}/{repo}/pulls/{pr_number}
{"state": "closed"}
```

**Output**: PR number and URL

---

### Step 6: UpdatePRDescription

**Purpose**: Populate the PR body with information about included PRs and issues.

**Description template** (example):
```markdown
## Deploy 2026-01-23

### Included Pull Requests
- #42 Add user authentication (@developer1)
- #43 Fix payment processing bug (@developer2)
- #47 Update dependencies (@developer3)

### Resolved Issues
- #123 Users cannot log in with SSO
- #124 Payment fails for international cards

### Checklist
- [ ] Verify deployment completes successfully
- [ ] Smoke test authentication flow
- [ ] Verify payment processing
- [ ] Check error rates in monitoring
```

**GitHub API**:
```
PATCH /repos/{owner}/{repo}/pulls/{pr_number}
{"body": "<description>"}
```

**Compensation**: Not strictly needed (PR will be closed if earlier compensation runs)

**Output**: Updated PR data

---

### Step 7: RequestReview

**Purpose**: Assign reviewers to the deploy PR.

**GitHub API**:
```
POST /repos/{owner}/{repo}/pulls/{pr_number}/requested_reviewers
{"reviewers": ["reviewer1", "reviewer2"]}
```

**Compensation**: Not needed

**Output**: Confirmation of requested reviewers

---

## PR Description Template

This should probably be configurable. Key sections:

1. **Title/Header** — Deploy date and/or version
2. **Included PRs** — List with links, authors
3. **Resolved Issues** — Aggregated from PR metadata
4. **Checklist** — Post-deploy verification items (configurable list)

Consider storing the template as a config or separate file that can be customized per project.

---

## Error Handling

This phase is fully reversible until the PR is created and review is requested. If any step fails:

1. Compensation runs in reverse order
2. Version bump commit can be reset
3. PR can be closed
4. Deploy branch remains intact for retry

Unlike Phase 2, there's no "point of no return" here—worst case, you end up with a closed PR and can retry.

---

## Configuration Needs

To implement this phase, you'll need to know:

1. **Version file locations and formats**
   - Which files contain the version?
   - What's the format/regex to find and replace?

2. **Versioning scheme**
   - How to determine the next version?
   - Auto-increment? Date-based? Manual input?

3. **PR description template**
   - What sections to include?
   - Formatting preferences?

4. **Default reviewers**
   - Who should be assigned?
   - Is this configurable per-deploy?

5. **Target branch**
   - Usually `staging`, but should be configurable

6. **Post-deploy checklist items**
   - What verification steps should be listed?

---

## Integration with Phase 2

Phase 2 outputs `merged_prs` which should include:
```elixir
[
  %{
    number: 42,
    title: "Add user authentication",
    author: "developer1",
    url: "https://github.com/org/repo/pull/42",
    linked_issues: [123, 456]
  },
  # ...
]
```

Phase 3 uses this to build the PR description. Make sure Phase 2's output structure matches what Phase 3 expects, or add a transformation step.

---

## Testing Considerations

- **Version bump**: Test with actual file formats you use
- **PR creation**: Mock GitHub API responses
- **Description generation**: Test template rendering with various inputs (no PRs, many PRs, PRs with/without linked issues)
- **Compensation**: Verify PR gets closed, commit gets reverted

---

## Open Questions

1. **What are the 3 version files and their formats?**

2. **How should version be determined?** Options:
   - Patch bump from current version
   - Date-based (2026.01.23)
   - Provided as input
   - Read from changelog/commit messages

3. **Should the checklist be static or dynamic?** Could it vary based on what PRs are included?

4. **Team vs individual reviewers?** GitHub supports requesting review from teams.

5. **Draft PR first?** Some teams create as draft, then mark ready after description is complete.
