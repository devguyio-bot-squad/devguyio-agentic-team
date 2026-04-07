---
name: board-scanner
description: >-
  Bob-specific board scanner override. Identical to the team default
  except po:merge is NOT auto-advanced to done — sentinel handles
  merge gating at that status.
metadata:
  author: botminter
  version: 1.0.0
---

# Board Scanner (Bob Override)

This skill defines your PLAN step when coordinating. Scan the GitHub
Projects v2 board, handle auto-advance transitions, then DELEGATE by
publishing exactly one event to the appropriate hat.

## Scan Procedure

### 1. Scratchpad

Append a new scan section to the scratchpad with the current timestamp.
Delete `tasks.jsonl` if it exists to prevent state bleed from previous
hat activations.

### 2. Sync workspace

```bash
git -C team pull --ff-only 2>/dev/null || true
```

### 3. Auto-detect the team repo

```bash
TEAM_REPO=$(cd team && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
```

If `gh repo view` fails (e.g., remote is a local path), extract from git remote:

```bash
TEAM_REPO=$(cd team && git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')
```

### 4. Cache project IDs (once per scan cycle)

```bash
OWNER=$(echo "$TEAM_REPO" | cut -d/ -f1)
PROJECT_NUM=$(gh project list --owner "$OWNER" --format json --jq '.projects[0].number')
PROJECT_ID=$(gh project view "$PROJECT_NUM" --owner "$OWNER" --format json --jq '.id')
FIELD_DATA=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json)
STATUS_FIELD_ID=$(echo "$FIELD_DATA" | jq -r '.fields[] | select(.name=="Status") | .id')
```

### 5. Query the project board

```bash
gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json --limit 1000
```

Parse the JSON to extract items with their Status field values.

### 6. Log to poll-log.txt

Use `$(date -u +%Y-%m-%dT%H:%M:%SZ)` for all timestamps.

```
2026-03-02T10:15:00Z — board.scan — START
2026-03-02T10:15:01Z — board.scan — 3 issues found
2026-03-02T10:15:01Z — board.scan — END
```

### 7. Auto-advance

Before dispatching, handle auto-advance statuses. Use the cached IDs to
transition statuses via `gh project item-edit`:

```bash
ITEM_ID=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json \
  --jq ".items[] | select(.content.number == $ISSUE_NUM) | .id")
OPTION_ID=$(echo "$FIELD_DATA" | jq -r '.fields[] | select(.name=="Status") | .options[] | select(.name=="<target-status>") | .id')
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" --single-select-option-id "$OPTION_ID"
```

Transitions:

- `arch:sign-off` -> set status to `po:merge`, comment, log.

NOTE: `po:merge` is NOT auto-advanced to `done`. The sentinel member
handles merge gating at this status. Items at `po:merge` should be
left for sentinel to process.

Comment format for auto-advance:

```
### 🦸 superman — $(date -u +%Y-%m-%dT%H:%M:%SZ)

Auto-advance: arch:sign-off → po:merge
```

After auto-advancing all eligible issues, continue to dispatch with the
updated board state.

### 8. Dispatch

Dispatch based on the highest-priority project status found. Process one
item at a time. Match each item's status against the tables below in order:
Epic -> Story -> Bug -> Content. The first match wins.

The tables are organized by workflow phase, not by issue type. The scanner
does NOT need to query the issue type — it dispatches purely by status.
Hats that handle shared statuses (e.g., `po:plan-review`, `qe:verify`)
are responsible for querying the issue type themselves.

**Epic priority (highest first):**

| # | Status | Event |
|---|--------|-------|
| 1 | `po:triage` | `po.backlog` |
| 2 | `po:design-review` | `po.review` |
| 3 | `po:plan-review` | `po.review` |
| 4 | `po:accept` | `po.review` |
| 5 | `lead:design-review` | `lead.review` |
| 6 | `lead:plan-review` | `lead.review` |
| 7 | `lead:breakdown-review` | `lead.review` |
| 8 | `arch:breakdown` | `arch.breakdown` |
| 9 | `arch:plan` | `arch.plan` |
| 10 | `arch:design` | `arch.design` |
| 11 | `po:backlog` | `po.backlog` |
| 12 | `po:ready` | `po.backlog` |
| 13 | `arch:in-progress` | `arch.in_progress` |

**Story priority (highest first — closer to finish line wins):**

| # | Status | Event |
|---|--------|-------|
| 1 | `qe:verify` | `qe.verify` |
| 2 | `dev:code-review` | `dev.code_review` |
| 3 | `dev:implement` | `dev.implement` |
| 4 | `qe:test-design` | `qe.test_design` |
| 5 | `sre:infra-setup` | `sre.setup` |

**Bug priority (highest first — closer to finish line wins):**

| # | Status | Event |
|---|--------|-------|
| 1 | `qe:verify` | `qe.verify` |
| 2 | `bug:in-progress` | `bug.in_progress` |
| 3 | `arch:review` | `arch.review` |
| 4 | `bug:investigate` | `qe.investigate` |
| 5 | `arch:refine` | `arch.refine` |
| 6 | `bug:breakdown` | `arch.breakdown` |

Note: `po:plan-review` and `qe:verify` are shared with Epic/Story tables. Bugs at these statuses are dispatched to the same hats, which query the issue type to determine the correct path.

**Content priority (highest first — closer to finish line wins):**

| # | Status | Event |
|---|--------|-------|
| 1 | `cw:review` | `cw.review` |
| 2 | `cw:write` | `cw.write` |

No work found -> emit `LOOP_COMPLETE`.

## Idempotency

Before dispatching, verify the issue is not already at the target output
status. If it is, skip it and check the next issue.

Include the issue number in the published event context so downstream hats
know which issue to work on.

## Failed Processing Escalation

Before dispatching, count comments matching `Processing failed:` on the issue.

- Count < 3 -> dispatch normally.
- Count >= 3 -> set the issue's project status to `error` (via item-edit),
  skip dispatch, add a comment:
  `"Issue #N failed 3 times: [last error]. Status set to error. Please investigate."`
  If RObot is enabled, also send a `ralph tools interact progress` notification.

Skip items with Status `error` during dispatch.

## Error Handling

If any `gh` command fails during the scan:

1. Log the error to `errors-log.txt` with the full command and output.
2. If the failure is on a specific issue (item-edit, issue comment), skip
   that issue and continue scanning the rest.
3. If the failure is systemic (project not found, auth failure), emit
   `LOOP_COMPLETE` and log the reason.

## Comment Format

All board scanner comments use:

```
### 🦸 superman — $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## Review Status Handling (Non-Blocking)

Issues at review statuses (`po:design-review`, `po:plan-review`, `po:accept`)
are dispatched to `po_reviewer` each scan cycle. The `po_reviewer` hat checks
for a human response comment, acts if found, and returns control if not. This
is non-blocking. Issues without a human response remain at their review status
and will be re-checked on the next scan cycle. NEVER skip review-status
issues — always dispatch them.

## Rules

- ALWAYS log to poll-log.txt before publishing.
- Publish exactly ONE event per scan cycle to dispatch work.
- When no work is found, emit `LOOP_COMPLETE`.
- NEVER auto-advance `po:merge` — sentinel handles merge gating.
