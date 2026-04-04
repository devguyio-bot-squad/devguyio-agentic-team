# Design: Metrics and Feedback Loops

**Epic:** #117 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's SDLC workflow produces no structured quality data. Three categories of raw data exist but go unconsumed:

- **Board scan log** (`poll-log.txt`) — timestamped dispatch entries, but no cycle time extraction
- **Loop history** (`.ralph/history.jsonl`) — loop session boundaries (`loop_started` with prompt, `loop_completed` with reason), but no session duration or completion-reason analysis
- **Cargo test output** — pass/fail exit codes, but no test count tracking or result archiving

Without quality data:
- Agents can't assess whether their changes improved or degraded the codebase
- Operators have no visibility into workflow efficiency (How long do issues spend in each status? What's the rejection rate?)
- Phase 3 "Graduated Autonomy" (#106) can't evaluate whether autonomy should increase or decrease — the autonomy model needs quality signals to make trust decisions

This epic introduces three capabilities:
1. **Metric collectors** — shell scripts that extract structured metrics from existing data sources
2. **Metric store** — append-only JSONL files for time-series metric data
3. **Feedback integration** — hat instruction updates that surface relevant metrics to agents during their work

### Harness Pattern

> "When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it both legible and enforceable for the agent?'"

Quality data is the missing capability. Without feedback, agents "try harder" — they can't diagnose systemic issues. Metrics make quality legible; feedback loops make improvement enforceable.

> "Build times, test pass rates, and deployment frequency are tracked automatically. The data feeds into dashboards and into agent prompts."

This epic brings that pattern to BotMinter: collect metrics that already exist as raw data, structure them, and feed them back to agents.

### Scope

- Metric collector scripts for build/test, workflow, and agent performance
- JSONL metric store convention (file format, retention, storage location)
- Build/test metric collection integrated into dev and QE hats
- Workflow metric collection from GitHub issue timeline
- Agent performance metrics from Ralph loop history
- Feedback integration into 4 hats (`dev_implementer`, `dev_code_reviewer`, `qe_verifier`, `arch_designer`)
- On-demand quality summary reports (operator-triggered content writer issue)

### Out of Scope

- External dashboards or web UIs (BotMinter has a web console, but metrics visualization is a separate concern)
- Real-time alerting or notifications (reports are periodic, not event-driven)
- Check script metrics (that's #114's domain — this design accommodates integration when ready)
- Automated autonomy decisions (that's Phase 3 "Graduated Autonomy" — this design provides the data it needs)
- Prometheus, OpenTelemetry, or external metrics backends (file-based is sufficient for pre-alpha)
- Changes to the status graph or review workflow
- CI pipeline metrics (CI integration is part of #114)

---

## 2. Architecture

### 2.1 BotMinter Architecture Context

BotMinter is a multi-binary Rust application with CLI (`bm`), agent CLI (`bm-agent`), HTTP daemon (`daemon/`, Axum, 9 source files), and web console (`web/`, SvelteKit SPA embedded via `rust-embed`, 9 source files). The team repo is the coordination control plane.

The project repo already produces:
- `cargo test` output (stdout with pass/fail counts, exit code)
- `cargo build` output (build time, warnings)
- `cargo clippy` output (lint warnings)

The team repo/workspace already produces:
- `poll-log.txt` — board scan entries with timestamps and dispatch decisions
- `.ralph/history.jsonl` — loop session boundaries: `loop_started` entries (with prompt) and `loop_completed` entries (with reason: `consecutive_failures`, `completion_promise`, or `max_iterations`). No per-iteration records — each entry represents a full loop session, not individual iterations within a session
- GitHub issue comments — status transitions with ISO timestamps (via attribution comments)

These are all raw data sources. This design extracts, structures, and feeds them back.

### 2.2 Metrics Architecture

```
Data Sources                    Collectors                  Store                    Consumers
─────────────                   ──────────                  ─────                    ─────────

cargo test/build ──────┐
                       ├──► build-test-collector.sh ──┐
cargo clippy ──────────┘                              │
                                                      ├──► metrics/
poll-log.txt ──────────────► workflow-collector.sh ────┤    ├── build-test.jsonl
                                                      │    ├── workflow.jsonl      ──► Hat feedback
.ralph/history.jsonl ──────► agent-collector.sh ───────┘    └── agent.jsonl             (inline context)
                                                                    │
GitHub issue timeline ─────► workflow-collector.sh                   │
                                                                    ▼
                                                             summary.sh
                                                                    │
                                                                    ▼
                                                             Quality reports
                                                             (content writer)
```

### 2.3 Collection Points

Metric collection happens at natural workflow moments — not as a separate step:

| Trigger | Collector | What's Measured |
|---------|-----------|-----------------|
| `dev_implementer` finishes build/test | build-test-collector | Build time, test pass/fail counts, test duration, clippy warnings |
| `qe_verifier` runs verification | build-test-collector | Same, with verification-phase context |
| Issue reaches terminal status (`done`) | workflow-collector | Time in each status, total cycle time, rejection count |
| Ralph loop completes | agent-collector | Session count, session duration (from paired start/end timestamps), completion reasons |

### 2.4 Storage Model

Metrics are stored as append-only JSONL files in the team repo:

```
team/projects/<project>/metrics/
  build-test.jsonl    — build and test results
  workflow.jsonl      — issue lifecycle timing
  agent.jsonl         — agent loop performance
```

JSONL is chosen for the same reasons as Ralph's existing `history.jsonl`: git-friendly, append-only, simple to parse with `jq`, no schema migration needed. Each line is a self-contained JSON object with a timestamp. No inter-line dependencies.

### 2.5 Feedback Loops

Metrics flow back to agents in two ways:

1. **Inline context** — hat instructions tell agents to read recent metrics before starting work. Example: `dev_implementer` reads the last 5 build-test entries to see if build times are trending up or clippy warnings are growing.

2. **Periodic reports** — a quality summary report is produced as a `cw:write` issue when >7 days have elapsed since the last report. The report aggregates trends from all three metric files.

---

## 3. Components and Interfaces

### 3.1 Build/Test Metric Collector

**Script:** `team/coding-agent/skills/metrics/build-test-collector.sh`

**Input:** Project name, issue number, phase (implement/verify)

**What it does:**
1. Runs `cargo test` in the project directory, capturing the summary line (`test result: ok. N passed; M failed; I ignored; ...`)
2. Captures build duration (wall clock via `time` or `date` bracketing)
3. Runs `cargo clippy --message-format=json` if available, counts warning entries
4. Appends a single JSON line to `team/projects/<project>/metrics/build-test.jsonl`

**Output format:**

```json
{
  "ts": "2026-04-04T16:30:00Z",
  "type": "build-test",
  "issue": 42,
  "phase": "implement",
  "build_secs": 45,
  "tests_passed": 128,
  "tests_failed": 0,
  "tests_ignored": 3,
  "test_secs": 12,
  "clippy_warnings": 2,
  "branch": "story-42-impl"
}
```

**Integration:** `dev_implementer` and `qe_verifier` hat instructions call this after running builds/tests:

```bash
bash team/coding-agent/skills/metrics/build-test-collector.sh botminter --issue 42 --phase implement
```

**Cargo test parsing:** The collector parses the standard `test result:` summary line via regex. This is the stable output format across all Rust toolchain versions — no nightly features required. Example parsed line:

```
test result: ok. 128 passed; 0 failed; 3 ignored; 0 measured; 0 filtered out; finished in 12.34s
```

### 3.2 Workflow Metric Collector

**Script:** `team/coding-agent/skills/metrics/workflow-collector.sh`

**Input:** Issue number

**What it does:**
1. Reads the issue's comment timeline via `github-project` skill (query-issues --type single)
2. Parses status transition comments (format: `Status: <from> → <to>` with ISO timestamps in comment headers)
3. Computes: time in each status (seconds between transitions), total cycle time, rejection count (transitions that go backward)
4. Appends a JSON line to `team/projects/<project>/metrics/workflow.jsonl`

**Output format:**

```json
{
  "ts": "2026-04-04T16:30:00Z",
  "type": "workflow",
  "issue": 42,
  "issue_type": "Task",
  "status_durations": {
    "qe:test-design": 1800,
    "dev:implement": 7200,
    "dev:code-review": 900,
    "qe:verify": 600
  },
  "total_cycle_secs": 10500,
  "rejections": 1,
  "rejection_statuses": ["dev:code-review"]
}
```

**Integration:** Called when an issue reaches terminal status (`done`). The board scanner's auto-advance logic for `po:merge` → `done` triggers this collector before closing the issue.

**Auto-advance failure semantics:** If the collector fails (GitHub API rate limit, network error, comment parsing failure), auto-advance proceeds normally — the issue is still closed and transitions to `done`. Missing workflow metrics never block workflow progression. The collector logs a warning to stderr; the metric entry for that issue is simply absent from `workflow.jsonl`.

### 3.3 Agent Performance Collector

**Script:** `team/coding-agent/skills/metrics/agent-collector.sh`

**Input:** Ralph root directory, project name

**Actual data source:** `.ralph/history.jsonl` contains two entry types:

```json
{"ts":"2026-03-28T01:50:07Z","type":{"kind":"loop_started","prompt":"..."}}
{"ts":"2026-03-30T20:53:09Z","type":{"kind":"loop_completed","reason":"consecutive_failures"}}
```

Entries are **loop-session-level** — each `loop_started`/`loop_completed` pair represents an entire Ralph loop session (which may contain many internal iterations). There are no per-iteration records, no per-iteration duration fields, and no event-emission counts.

**What it does:**
1. Reads `.ralph/history.jsonl` (entries since the previous collection timestamp, stored in `team/projects/<project>/metrics/.agent-cursor`)
2. Pairs `loop_started` and `loop_completed` entries by adjacency (a `loop_completed` pairs with the most recent preceding `loop_started`)
3. Computes session-level metrics from the paired entries:
   - **session_count:** number of completed sessions in the window
   - **avg_session_duration_secs:** average wall-clock time from `loop_started.ts` to `loop_completed.ts`
   - **completion_reasons:** count of each reason (`completion_promise`, `max_iterations`, `consecutive_failures`)
   - **failure_rate:** proportion of sessions ending in `consecutive_failures` over total completed sessions
4. Appends a single JSON line to `team/projects/<project>/metrics/agent.jsonl`

**Output format:**

```json
{
  "ts": "2026-04-04T16:30:00Z",
  "type": "agent",
  "window_start": "2026-03-28T00:00:00Z",
  "window_end": "2026-04-04T16:30:00Z",
  "sessions": 15,
  "avg_session_duration_secs": 3600,
  "completion_reasons": {
    "completion_promise": 8,
    "max_iterations": 5,
    "consecutive_failures": 2
  },
  "failure_rate": 0.13
}
```

**Integration:** Called at the end of each Ralph loop session (when `LOOP_COMPLETE` is emitted). The cursor file ensures each session is counted exactly once across collections.

### 3.4 Metric Summary Script

**Script:** `team/coding-agent/skills/metrics/summary.sh`

**Input:** Project name, time window (e.g., `7d`, `30d`)

**What it does:**
1. Reads entries from all three JSONL files within the specified time window
2. Computes aggregates: average build time trend, test pass rate, average cycle time per issue type, agent failure rate trend
3. Flags metrics that changed >20% from the previous period
4. Outputs a markdown summary to stdout

**Output:** Structured markdown suitable for:
- Injection into hat context (via hat instructions reading recent metrics)
- Quality summary reports (via content writer)
- Human consumption (operator can run manually)

### 3.5 Hat Instruction Updates

Four hats receive instruction updates:

| Hat | New Behavior |
|-----|-------------|
| `dev_implementer` | After build/test, call build-test-collector. Before starting, read last 3 build-test entries for the project to check for regressions (increasing build time, growing clippy warnings). |
| `dev_code_reviewer` | Read build-test metrics for the story's branch. Flag if tests failed or clippy warnings increased versus the previous entry for this project. |
| `qe_verifier` | After verification build/test, call build-test-collector. Compare test counts against the implementation-phase entry — flag if tests were removed or reduced. |
| `arch_designer` | At the start of design work, read the metric summary (last 7 days) for project health context. Cycle time and rejection rate inform design complexity decisions. |

### 3.6 Quality Summary Report

Quality summary reports are produced on demand via a standalone workflow — the board scanner is NOT involved in report creation. The scanner remains a pure dispatcher.

**Trigger:** The operator creates a `cw:write` issue when they want a quality report (e.g., "Quality Summary Report — Week of 2026-04-04"). Alternatively, hats that read metrics (e.g., `arch_designer` per §3.5) may recommend a report in their issue comments if the last report in `team/projects/<project>/knowledge/reports/` is older than 7 days, but they do not create issues themselves.

**Workflow once a `cw:write` issue exists:**
1. The `cw_writer` hat runs `summary.sh botminter 7d` to generate a markdown quality report
2. The hat writes the report to `team/projects/<project>/knowledge/reports/quality-YYYY-MM-DD.md`
3. The issue transitions through the normal content workflow (`cw:write` → `cw:review` → `po:merge` → `done`)

**Report contents:**
- **Build health:** average build time, test count trend, failure rate
- **Workflow efficiency:** average cycle time by issue type, rejection rate, bottleneck statuses
- **Agent performance:** session count, session duration trend, completion reason distribution, failure rate
- **Notable changes:** metrics that changed >20% from the previous period

### 3.7 Check Script Integration (Future)

When #114 (Executable Invariant Checks) ships, the build-test collector gains a `check_violations` field:

```json
{
  "check_violations": 3,
  "check_scripts_run": 4,
  "check_scripts_passed": 1
}
```

This field is absent until #114 is implemented. The collector script checks whether the check runner exists at `team/coding-agent/skills/check-runner/run-checks.sh` and includes its results if available. No code changes needed in the collector — it's a conditional inclusion.

---

## 4. Data Models

### 4.1 Metric Entry Schema (JSONL)

All metric entries share a common header:

| Field | Type | Description |
|-------|------|-------------|
| `ts` | string | ISO 8601 UTC timestamp |
| `type` | string | `"build-test"`, `"workflow"`, or `"agent"` |

Type-specific fields are defined in Sections 3.1–3.3.

### 4.2 File Layout

```
team/projects/<project>/
  metrics/
    build-test.jsonl   — one entry per build/test run
    workflow.jsonl     — one entry per issue lifecycle completion
    agent.jsonl        — one entry per collection (covers loop sessions since previous cursor)
    .agent-cursor      — timestamp of last agent-collector run
  knowledge/
    reports/
      quality-2026-04-04.md   — weekly quality summary reports
```

### 4.3 Retention

JSONL files are append-only. No automated retention policy at pre-alpha stage — files grow indefinitely. If files become large (>10MB), manual truncation is appropriate. A future iteration could add rotation (keep last 90 days).

---

## 5. Error Handling

- **Collector script failure:** If a collector script fails (e.g., `cargo test` output unparseable, `jq` not found), the hat proceeds with its primary work. Missing metrics never block the workflow. The collector logs a warning to stderr but does not fail the hat's task.
- **Missing metric files:** If a JSONL file doesn't exist when a hat tries to read it, the hat proceeds without historical context. First run creates the file. No special initialization needed.
- **Malformed JSONL entries:** Consumers skip lines that fail JSON parsing (`jq` handles this gracefully). One bad entry doesn't invalidate the file.
- **Git conflicts on metric files:** JSONL is append-only. Merge conflicts on the same file are resolved by keeping both entries (both lines are valid observations). Conflicts on the same line are unlikely since entries are timestamped.
- **Stale metrics:** The summary script applies recency weighting — metrics older than 30 days are excluded from trend calculations.
- **GitHub API rate limits:** The workflow collector reads issue comments via the `github-project` skill, which respects rate limits. If the API call fails, the workflow metric for that issue is skipped — it can be collected on the next opportunity.
- **Workflow collector failure during auto-advance:** When the workflow collector is triggered during the board scanner's `po:merge` → `done` auto-advance, any collector failure (API, parsing, write) is non-blocking. The auto-advance and issue close proceed normally. The missing metric entry is simply absent from `workflow.jsonl` — there is no retry mechanism since the issue is already closed.
- **Empty metric files:** If all files are empty (first run), the summary script outputs "No metrics data available yet" and hats proceed without feedback context.

---

## 6. Acceptance Criteria

- **Given** `dev_implementer` runs `cargo test` on a story branch, **when** the build completes, **then** the build-test collector appends a JSONL entry to `team/projects/botminter/metrics/build-test.jsonl` with test counts, build duration, and branch name.

- **Given** a story issue reaches `done` status, **when** the workflow collector runs, **then** a JSONL entry is appended to `workflow.jsonl` with the time spent in each status and the total cycle time.

- **Given** `dev_implementer` starts working on a story, **when** the hat reads the last 3 build-test entries, **then** it can identify if build time or clippy warnings are trending upward and mention this in its approach.

- **Given** `qe_verifier` runs verification, **when** test counts are compared against the implementation-phase entry, **then** a decrease in test count is flagged as a concern in the verification comment.

- **Given** a `cw:write` issue for a quality summary report exists, **when** the `cw_writer` hat runs `summary.sh`, **then** a markdown report is written to `team/projects/<project>/knowledge/reports/quality-YYYY-MM-DD.md` with build health, workflow efficiency, and agent performance sections.

- **Given** a Ralph loop session completes (LOOP_COMPLETE), **when** the agent-collector runs, **then** a JSONL entry is appended to `agent.jsonl` with session count, average session duration, completion reason distribution, and failure rate computed from paired `loop_started`/`loop_completed` entries in `history.jsonl`.

- **Given** the metric summary script runs with a 7-day window, **when** data exists for all three metric types, **then** the output includes build health, workflow efficiency, and agent performance sections with trend indicators.

- **Given** a build-test collector fails to parse `cargo test` output, **when** the failure occurs, **then** the hat logs a warning but completes its primary work without blocking.

---

## 7. Impact on Existing System

| Component | Change |
|-----------|--------|
| `team/coding-agent/skills/metrics/` | New directory with 4 scripts: build-test-collector.sh, workflow-collector.sh, agent-collector.sh, summary.sh |
| `team/projects/<project>/metrics/` | New directory with 3 JSONL files (created on first run) |
| `team/projects/<project>/knowledge/reports/` | New directory for periodic quality summary reports |
| `dev_implementer` hat instructions | Call build-test collector after builds; read recent metrics before starting |
| `dev_code_reviewer` hat instructions | Read build-test metrics during review |
| `qe_verifier` hat instructions | Call build-test collector; compare against implementation-phase metrics |
| `arch_designer` hat instructions | Read metric summary for project health context |
| Board scanner (auto-advance) | Call workflow-collector during `po:merge` → `done` auto-advance; non-blocking on failure |
| `cw_writer` hat instructions | Run `summary.sh` when handling quality summary report issues |

**No changes to:** Ralph Orchestrator, BotMinter CLI (`bm`), agent CLI (`bm-agent`), daemon/web console, existing status graph, existing invariant files, existing test infrastructure, existing 11 ADRs, `.planning/` directory, `specs/` directory, check script system (#114), plan artifact system (#116).

---

## 8. Security Considerations

Metric files contain build statistics, timing data, and issue references — no secrets, credentials, or runtime state. All data is derived from sources already accessible to the agent (cargo output, GitHub API, Ralph logs).

**No new attack surface:** Metric collectors read existing outputs and write to team repo files. No new permissions, no external network requests beyond existing GitHub API usage (for workflow-collector reading issue comments via the `github-project` skill).

**Data sensitivity:** Metric files may reveal internal development velocity, failure rates, and workflow patterns. These are team-internal artifacts in a private team repo — the same trust model as existing knowledge files and `poll-log.txt`.

**No executable code in metrics:** JSONL entries are pure data. No metric file is executed or interpreted as code. The summary script reads and aggregates — it does not `eval` or source metric data.

**Prompt injection risk:** Lower than markdown-based knowledge files. Consumers parse metric entries as JSON with `jq`, not as natural language. A malicious JSONL entry would need to break `jq` parsing to cause issues, and even then the error handling (skip malformed lines) prevents propagation. Team repo write access remains the primary control.
