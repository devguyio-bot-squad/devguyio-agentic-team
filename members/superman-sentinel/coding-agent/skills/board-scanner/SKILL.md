---
name: board-scanner
description: >-
  Sentinel-specific board scanner. Scans for merge-ready PRs (linked to
  board issues at po:merge or PRs directly on the board) and orphaned PRs
  (open PRs with no board connection). Dispatches to pr_gate or pr_triage.
metadata:
  author: botminter
  version: 1.0.0
---

# Board Scanner (Sentinel Override)

This skill defines your PLAN step when coordinating. Scan for PRs that
need merge gating and orphaned PRs that need triage, then DELEGATE by
publishing one event per scan cycle.

## Scan Procedure

### 1. Scratchpad

Append a new scan section to the scratchpad with the current timestamp.
Delete `tasks.jsonl` if it exists to prevent state bleed.

### 2. Sync workspace

```bash
git -C team pull --ff-only 2>/dev/null || true
```

### 3. Auto-detect the team repo and project forks

```bash
TEAM_REPO=$(cd team && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
```

If `gh repo view` fails:

```bash
TEAM_REPO=$(cd team && git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')
```

Read project fork URLs from `team/botminter.yml` (the `projects:` section).

### 4. Cache project IDs (once per scan cycle)

```bash
OWNER=$(echo "$TEAM_REPO" | cut -d/ -f1)
PROJECT_NUM=$(gh project list --owner "$OWNER" --format json --jq '.projects[0].number')
PROJECT_ID=$(gh project view "$PROJECT_NUM" --owner "$OWNER" --format json --jq '.id')
FIELD_DATA=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json)
STATUS_FIELD_ID=$(echo "$FIELD_DATA" | jq -r '.fields[] | select(.name=="Status") | .id')
```

### 5. Phase 1 — Find merge-ready PRs

Scan for PRs that are linked to the board and ready for merge gating.

**5a. Board issues at `po:merge`:**

```bash
gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json --limit 1000
```

Filter for items with status `po:merge`. For each:
- If the item is an **issue**: search for linked PRs on the project fork
  (`gh pr list --repo <fork> --search "<issue-number>" --json number,headRefName,state`)
- If the item is a **PR** (GitHub Projects v2 can track PRs directly):
  the item itself is the PR to gate

**5b. PRs linked to board issues at other statuses:**

Skip these — only `po:merge` items are ready for merge gating.

Collect all merge-ready PRs with their issue numbers and project labels.

### 6. Phase 2 — Find orphaned PRs

For each project fork:

```bash
gh pr list --repo <fork> --state open --json number,title,author,createdAt,updatedAt,headRefName,body
```

For each open PR, check if it is linked to any board item:
- Search the PR body/title for issue references (`#<N>`, `Fixes #<N>`, etc.)
- Check if the referenced issue exists on the project board
- If no board connection found, mark as orphaned

Collect all orphaned PRs grouped by project.

### 7. Log to poll-log.txt

```
2026-04-07T10:15:00Z — sentinel.scan — START
2026-04-07T10:15:01Z — sentinel.scan — N merge-ready PRs, M orphaned PRs
2026-04-07T10:15:01Z — sentinel.scan — END
```

### 8. Dispatch (one event per cycle)

**Priority: merge-ready PRs first, triage second.**

| Priority | Condition | Event | Context |
|----------|-----------|-------|---------|
| 1 | Merge-ready PR found | `po.merge_gate` | issue number, PR number, project name, fork repo |
| 2 | Orphaned PRs found (no merge work) | `po.pr_triage` | list of orphaned PRs with project grouping |
| 3 | Nothing found | `LOOP_COMPLETE` | — |

Dispatch exactly ONE event. If multiple merge-ready PRs exist, pick the
one whose issue has been at `po:merge` the longest (FIFO).

**IMPORTANT: Do NOT auto-advance `po:merge` to `done`.** Sentinel exists
to enforce merge gates. The `pr_gate` hat decides whether to merge.

## Failed Processing Escalation

Before dispatching, count comments matching `Processing failed:` on the issue.

- Count < 3 → dispatch normally.
- Count >= 3 → set status to `error`, skip, comment:
  `"Issue #N failed 3 times: [last error]. Status set to error. Please investigate."`

Skip items with Status `error`.

## Comment Format

All board scanner comments use:

```
### 🛡️ sentinel — $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## Rules

- ALWAYS log to poll-log.txt before publishing.
- Publish exactly ONE event per scan cycle.
- When no work is found, emit `LOOP_COMPLETE`.
- NEVER auto-advance `po:merge` — always dispatch to pr_gate hat.
- NEVER auto-advance `arch:sign-off` — bob handles pipeline feeding.
- Merge-ready PRs take priority over triage.
