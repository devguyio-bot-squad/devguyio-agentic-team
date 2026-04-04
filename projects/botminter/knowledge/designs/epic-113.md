# Design: Metrics and Feedback Loops

**Epic:** #113 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's `poll-log.txt` provides an audit trail of board scans but no analytics. Nobody can answer: what's the rejection rate at code review? How long do issues wait for human approval? Is cycle time improving?

Without metrics, graduated autonomy (#112) is guesswork. With metrics, it's evidence.

This epic adds structured transition logging and derived metrics that enable data-driven retrospectives and provide the quality evidence needed to justify autonomy graduation.

### Harness Pattern

Harness maintains quality grades per domain and uses them to drive automated cleanup and autonomy decisions. Their system tracks deviations from golden principles and surfaces them in regular reports.

BotMinter's version is simpler: log every status transition with a timestamp, then derive cycle times, rejection rates, and gate wait times from the log.

### Scope

- JSONL transition logging in the board scanner
- Derived metric definitions
- Weekly report generation via `cw_writer`

### Out of Scope

- Quality grading per domain (future, builds on this foundation)
- Real-time dashboards (JSONL is sufficient for batch analysis)
- Integration with external metrics systems

---

## 2. Architecture

### Data Flow

```
Board scanner transitions an issue
  → Appends JSONL entry to metrics/transitions.jsonl
    → Gardener (#110) checks report freshness
      → Creates cw:write issue if >7 days since last report
        → cw_writer reads JSONL, generates summary
          → Report stored in team/projects/<project>/knowledge/reports/
```

### Transition Log Format

One JSON line per status transition:

```json
{"issue": 108, "type": "Epic", "from": "po:triage", "to": "arch:design", "ts": "2026-04-04T10:30:00Z", "hat": "po_backlog"}
```

Fields:
- `issue` — issue number
- `type` — issue type (Epic, Task, Bug)
- `from` — previous status
- `to` — new status
- `ts` — ISO 8601 timestamp (UTC)
- `hat` — which hat performed the transition

The log is append-only. No entries are modified or deleted. The file grows indefinitely — at ~150 bytes per entry, a project processing 100 transitions/week produces ~780 KB/year.

---

## 3. Components and Interfaces

### Board Scanner Integration

The board scanner skill gains one instruction: after each status transition (via `status-transition.sh`), append a JSONL entry to `metrics/transitions.jsonl`. This is a single-line addition to the skill's instructions.

Implementation: the `status-transition.sh` script (or a wrapper) appends the line after confirming the transition succeeded. If the JSONL write fails, the transition is not rolled back — metrics are observational, not transactional.

### Derived Metrics

Computed from the JSONL log by the report generator:

| Metric | Computation | Use |
|---|---|---|
| Design cycle time | Time from `arch:design` to `po:ready` | Identify design bottlenecks |
| Implementation cycle time | Time from `dev:implement` to `qe:verify` completion | Track velocity |
| Human gate wait time | Duration in `po:design-review`, `po:plan-review`, `po:accept` | Justify graduated autonomy |
| Rejection rate per gate | Transitions from a review status back to a work status / total at that gate | Quality signal. <15% qualifies for guided tier. |
| First-pass rate | Issues reaching `done` without any rejection transition | Overall quality indicator |
| Throughput | Issues completed per week | Capacity tracking |

### Report Generation

The gardener (#110) triggers report generation by checking file timestamps in `team/projects/<project>/knowledge/reports/`. If >7 days since the last report: create a `cw:write` issue with the body specifying "Generate weekly metrics report from `metrics/transitions.jsonl`."

The `cw_writer` hat reads the JSONL, computes the metrics above, and writes a summary to `team/projects/<project>/knowledge/reports/week-YYYY-MM-DD.md`.

Report format:

```markdown
# Metrics Report: Week of 2026-04-04

## Summary
- Issues completed: 5
- Average design cycle time: 2.3 days
- Average implementation cycle time: 1.1 days
- Human gate wait time (median): 4.2 hours
- Rejection rate at code review: 8%
- First-pass rate: 72%

## Details
[per-issue breakdown]
```

The `retrospective` skill receives these reports for data-driven retros.

---

## 4. Acceptance Criteria

- **Given** the board scanner transitions an issue status, **when** the transition completes, **then** a JSONL entry is appended to `metrics/transitions.jsonl` with issue number, type, from/to status, timestamp, and hat name.
- **Given** >7 days since the last report and the gardener runs, **when** it creates a `cw:write` issue, **then** `cw_writer` generates a summary with cycle times, rejection rates, and throughput.
- **Given** the JSONL write fails, **when** the status transition was successful, **then** the transition is not rolled back (metrics are observational).
- **Given** a JSONL log with transition data, **when** a retrospective is run, **then** the `retrospective` skill can access computed metrics.

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| Board scanner skill instructions | Add JSONL append step after each transition |
| `metrics/transitions.jsonl` | New file (workspace root) |
| `team/projects/<project>/knowledge/reports/` | New directory for weekly reports |
| `cw_writer` hat instructions | Add metrics report generation capability |

No changes to: `status-transition.sh` behavior, poll-log.txt (kept as audit trail), Ralph Orchestrator engine, status graph.

`poll-log.txt` continues as the human-readable audit log. `metrics/transitions.jsonl` is the machine-readable analytics source. They serve different purposes and coexist.

---

## 6. Security Considerations

Transition logs contain issue numbers, status names, timestamps, and hat names. No PII, credentials, or application data. The JSONL file is workspace-local — not pushed to any remote. Weekly reports stored in the team repo contain the same non-sensitive data. Metrics cannot be used to infer authentication details or access patterns beyond what's visible on the public project board.
