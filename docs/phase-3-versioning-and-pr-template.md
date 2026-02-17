# Phase 3 Implementation Details: Versioning & PR Template

## Task

Update the Phase 3 implementation with concrete versioning logic and PR description format.

---

## Version Bumping

### Files to Update

Three files contain the version number:

| File | Format |
|------|--------|
| `./version.txt` | Plain text, just the version string (e.g., `2.4.10`) |
| `backend/version.txt` | Plain text, just the version string |
| `frontend/package.json` | JSON, update the `"version"` key |

### Version Format

- Format: `MAJOR.MINOR.PATCH` (e.g., `2.4.10`)
- Increment: Always bump the PATCH number by 1
- Example: `2.4.10` → `2.4.11`

### Implementation

1. **Read current version** from `./version.txt` (treat this as the canonical source)

2. **Parse and increment**:
   ```elixir
   def increment_patch(version_string) do
     [major, minor, patch] = 
       version_string
       |> String.trim()
       |> String.split(".")
       |> Enum.map(&String.to_integer/1)
     
     "#{major}.#{minor}.#{patch + 1}"
   end
   ```

3. **Update each file**:
   - `./version.txt` — Overwrite entire file with new version string
   - `backend/version.txt` — Overwrite entire file with new version string  
   - `frontend/package.json` — Parse JSON, update `"version"` key, write back

---

## PR Description Template

### Format

The deploy PR body should simply list merged PR numbers, one per line:

```
#2654
#2378
#2401
```

That's it. No headers, no author names, no additional formatting.

### Implementation

Given a list of merged PR numbers from Phase 2:

```elixir
def format_pr_description(pr_numbers) do
  pr_numbers
  |> Enum.map(&"##{&1}")
  |> Enum.join("\n")
end
```

### Example

If Phase 2 merged PRs 2654, 2378, and 2401, the PR body should be:

```
#2654
#2378
#2401
```

---

## Summary of Changes

1. Implement `increment_patch/1` function for version bumping
2. Update version bump step to modify all 3 files:
   - `./version.txt`
   - `backend/version.txt`
   - `frontend/package.json`
3. Simplify PR description generation to just list `#NUMBER` per line
