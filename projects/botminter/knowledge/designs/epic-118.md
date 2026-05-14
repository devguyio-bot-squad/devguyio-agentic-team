---
type: design
status: draft
parent: "106"
epic: "118"
revision: 2
created: 2026-04-04
updated: 2026-04-04
author: bob (superman)
depends_on:
  - "114"
  - "117"
---

# Epic #118: Automated Codebase Gardening

## Overview

### Problem

BotMinter's two project codebases accumulate entropy through development:

**botminter (Rust + SvelteKit):**
- `cargo clippy` runs in CI (`just clippy`, warnings-as-errors) but never auto-fixes. Fixable warnings accumulate between CI runs.
- No `rustfmt` enforcement — no `rustfmt.toml`, no `cargo fmt` recipe in the Justfile, no `cargo fmt --check` step in CI. Formatting is inconsistent across 16 domain modules in `crates/bm/src/`.
- No dependency security scanning. `cargo-deny`, `cargo-audit`, and `cargo-outdated` are absent. No Justfile recipe, no CI step.
- The SvelteKit console (`console/`) has `svelte-check` and `vitest` but no `npm audit` automation.

**hypershift (Go):**
- `golangci-lint`, `staticcheck`, `codespell`, `gitleaks` are configured with auto-fix capabilities (`make lint-fix`, codespell `-w` flag).
- `make verify` is comprehensive but runs only locally and in pre-push hooks.
- Dependabot runs weekly for Go dependencies; Renovate is configured but globally disabled.

In an agentic SDLC, agents both produce and consume entropy. Agents generate more lint warnings per unit of code than experienced developers, and they work less effectively in codebases with inconsistent style, dead code, and stale dependencies. Without automated gardening, the gap compounds.

### Solution

A periodic gardening system consisting of:

1. **Gardening scanners** — project-specific shell scripts that detect fixable issues, building on #114's check runner and structured output format
2. **Gardening executor** — a coordinator script that runs scanners in defined phases, applies auto-fixes, and creates both PRs and tracking issues
3. **Board integration** — auto-fix PRs get a tracking issue on the team board for code review; high-severity findings become bug issues following the existing simple bug workflow

The system runs on a periodic trigger (not blocking feature work) and produces small, reviewable PRs for auto-fixable issues.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Gardening Executor                          │
│         team/coding-agent/skills/gardening/                  │
│                run-gardening.sh <project>                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Phase 1: Auto-Fix (sequential, tested as unit)              │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │ Lint Scanner  │ ───► │  Fmt Scanner │                     │
│  │  lint-fix.sh  │      │ fmt-check.sh │                     │
│  └──────────────┘      └──────────────┘                     │
│         │                      │                             │
│         └────────┬─────────────┘                             │
│                  ▼                                            │
│         ┌──────────────┐                                     │
│         │  Run tests   │                                     │
│         │  (gate)      │                                     │
│         └──────┬───────┘                                     │
│                │ pass                                         │
│                ▼                                              │
│  ┌──────────────────────────────┐                            │
│  │  Commit + PR (project repo)  │                            │
│  │  + Tracking Issue (team board)│                           │
│  │  at dev:code-review           │                           │
│  └──────────────────────────────┘                            │
│                                                              │
│  Phase 2: Reporting (read-only, no file modifications)       │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │ Dep Scanner  │      │Unused Scanner│                     │
│  │ dep-audit.sh │      │unused-deps.sh│                     │
│  └──────┬───────┘      └──────┬───────┘                     │
│         └────────┬─────────────┘                             │
│                  ▼                                            │
│  ┌──────────────────────────────┐                            │
│  │  Bug Issues (team board)     │                            │
│  │  at bug:investigate           │                           │
│  └──────────────────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

**Working directories:**
- Executor and scanner scripts: `team/coding-agent/skills/gardening/`
- Scanners execute inside the target project directory: `projects/botminter/` or `projects/hypershift/`
- Auto-fix PRs are created on the project repository (e.g., `devguyio-bot-squad/botminter`)
- Tracking issues and bug issues are created on the team repository's GitHub project board

### Execution Model

Gardening runs as a **periodic background activity** that does not block the main board dispatch loop:

1. The board scanner checks for a gardening trigger condition after processing all actionable issues (when `LOOP_COMPLETE` would normally be emitted)
2. If enough time has elapsed since the last gardening run (configurable, default: 7 days), the scanner emits `gardening.scan` **with the project name** for whichever project is most overdue
3. A `gardener` hat handles the `gardening.scan` event, runs the executor for that specific project, creates PRs/issues, and returns control
4. Gardening-created tracking issues enter the normal workflow and are processed by existing hats (`dev_code_reviewer` → `qe_verifier`)

One project per gardening cycle. If multiple projects are overdue, the most overdue runs first; the remaining project will be picked up on the next idle cycle.

### Two-Phase Scanner Execution

Scanners are split into two phases to prevent dirty-state conflicts:

**Phase 1 — Auto-fix (sequential, file-modifying):**
1. `lint-fix.sh` runs first — rewrites code logic (e.g., clippy rewrites `&*x` to `x`)
2. `fmt-check.sh` runs second — normalizes style on the already-fixed code

This order is intentional: lint fixes change semantics (remove redundant borrows, simplify patterns), then the formatter normalizes the resulting style. Running them in reverse would risk clippy reintroducing formatting inconsistencies. Both scanners modify files in the working tree, and the combined result is tested as a single unit before committing.

**Phase 2 — Reporting (read-only, no file modifications):**
3. `dep-audit.sh` — reports security advisories (never auto-fixes)
4. `unused-deps.sh` — reports unused dependencies (never auto-fixes in this design; `go mod tidy` was downgraded to report-only because dependency removal can break builds)

Phase 2 runs after Phase 1 is either committed or reverted. Phase 2 scanners never modify files — they report findings that become bug issues.

**Why not commit per-scanner?** Lint and format fixes are interdependent: clippy may change code that rustfmt then reformats. Testing them individually would require reverting clippy's changes before testing fmt, which is wasteful. The correct unit of testing is "all auto-fixes applied together."

## Components and Interfaces

### 1. Gardening Scanners

Each scanner is a standalone shell script. Scanners use pipe-delimited `FINDING` output rather than #114's multi-line `VIOLATION` format because scanners produce many findings per run (potentially dozens) that need machine-parseable batching. #114's violations are few per check and benefit from human-readable multi-line blocks. Both formats serve their use case.

**Input:** Project directory path (first argument), project name (second argument)

**Output:** Structured findings to stdout, one per line:

```
FINDING|<category>|<severity>|<file>|<description>|<auto-fixable>
```

- **Categories:** `lint`, `format`, `dependency`, `dead-code`
- **Severity:** `low`, `medium`, `high` (high = security advisory)
- **Auto-fixable:** `true` or `false`

**Exit codes:** 0 = no findings, 1 = findings reported, 2+ = scanner error (non-blocking)

#### Scanner: `lint-fix.sh` (Phase 1)

Detects lint warnings fixable by the project's lint tool.

- **botminter:** Runs `cargo clippy --fix --allow-dirty --allow-staged -p bm --features console 2>&1`. Captures which files were modified via `git diff --name-only`.
- **hypershift:** Runs `golangci-lint run --fix ./... 2>&1`. Captures modifications via `git diff --name-only`.

#### Scanner: `fmt-check.sh` (Phase 1)

Detects formatting inconsistencies. Runs **after** lint-fix so it normalizes style on already-fixed code.

- **botminter:** Runs `cargo fmt -- --check` to list files needing formatting, then applies fix via `cargo fmt`.
- **hypershift:** Runs `gofmt -l .` to list unformatted files, then `codespell --check-filenames -q 3` for spelling. Applies fixes via `gofmt -w` and `codespell -w`.

#### Scanner: `dep-audit.sh` (Phase 2 — report only)

Detects dependency security issues. Never modifies files.

- **botminter:** Runs `cargo audit` (requires `cargo-audit` installed). Reports known vulnerabilities in Cargo dependencies.
- **hypershift:** Runs `govulncheck ./...` (Go native vulnerability checker).
- All findings are `auto-fixable: false` — dependency updates need human judgment.

#### Scanner: `unused-deps.sh` (Phase 2 — report only)

Detects unused dependencies. Reports findings but does not apply fixes.

- **botminter:** Runs `cargo machete` (detects unused crate dependencies in `Cargo.toml`). Findings are `auto-fixable: false` (removal needs verification).
- **hypershift:** Runs `go mod tidy -diff` to detect unused Go module dependencies. Findings are `auto-fixable: false` (downgraded from auto-fix; removing dependencies can break builds and needs human review).

### 2. Gardening Executor

**Location:** `team/coding-agent/skills/gardening/run-gardening.sh`

**Arguments:** `<project-name>` (e.g., `botminter`, `hypershift`)

**Behavior:**

1. Verify the project repo has no uncommitted changes. Abort if dirty.
2. Create a `gardening/<YYYY-MM-DD>` branch in the project repo.
3. **Phase 1 — Auto-fix:**
   a. Run `lint-fix.sh` for the project, collecting findings.
   b. Run `fmt-check.sh` for the project, collecting findings.
   c. If any files were modified, run the project's test suite.
   d. If tests pass: commit changes with `chore(gardening): auto-fix lint/format issues`.
   e. If tests fail: revert all Phase 1 changes (`git checkout .`), create a bug issue describing which fixes broke tests. Continue to Phase 2.
4. **Phase 1 PR + tracking issue (if auto-fixes were committed):**
   a. Push the branch and create a PR on the project repo.
   b. Create a tracking issue on the team repo's project board:
      - **Title:** `Review gardening auto-fixes for <project> — <YYYY-MM-DD>`
      - **Kind:** `story` (using `create-issue.sh --kind story`)
      - **Body:** Links to the PR URL, lists the auto-fixes applied (summary of FINDING lines from Phase 1 scanners), and references epic #118
      - **Label:** `project/<project>`
      - **Status:** Set to `dev:code-review` immediately (via `status-transition.sh`)
   c. This tracking issue enters the normal board workflow: `dev:code-review` → `qe:verify` → `done`. The `dev_code_reviewer` hat reviews the linked PR; the `qe_verifier` hat verifies test results.
5. **Phase 2 — Reporting:**
   a. Run `dep-audit.sh` for the project, collecting findings.
   b. Run `unused-deps.sh` for the project, collecting findings.
   c. For non-auto-fixable findings with severity `high`: create a bug issue on the team repo's project board with `project/<project>` label, status `bug:investigate`.
6. Track scanner execution count. If 0 scanners actually ran (all skipped due to missing tools), log a warning and do NOT update last-run timestamp.
7. If at least 1 scanner ran: update last-run timestamp.
8. Output a gardening summary to stdout.

**Idempotency:** If a `gardening/<YYYY-MM-DD>` branch already exists, the executor skips (prevents duplicate PRs).

### 3. Gardener Hat

A new hat added to `ralph.yml`:

```yaml
gardener:
  triggers: ["gardening.scan"]
  publishes: ["gardening.done", "gardening.failed"]
```

Instructions:
1. Extract `<project>` from the `gardening.scan` event payload.
2. Run: `bash team/coding-agent/skills/gardening/run-gardening.sh <project>`
3. If auto-fix PR was created, post a progress update via RObot with the PR link and tracking issue link.
4. If high-severity dependency issues were found, post a progress update.
5. Emit `gardening.done` with summary.

### 4. Board Scanner Integration

The board scanner's dispatch logic gains a gardening trigger in the "no work found" path:

```bash
# After normal dispatch finds no actionable work:

# Iterate all projects, find the most overdue
most_overdue_project=""
max_days=0

for project_dir in team/projects/*/; do
    project=$(basename "$project_dir")
    last_run=$(cat "team/projects/$project/metrics/gardening-last-run.txt" 2>/dev/null \
        || echo "1970-01-01T00:00:00Z")
    days_since=$(( ($(date +%s) - $(date -d "$last_run" +%s)) / 86400 ))

    if [ "$days_since" -ge 7 ] && [ "$days_since" -gt "$max_days" ]; then
        max_days=$days_since
        most_overdue_project=$project
    fi
done

if [ -n "$most_overdue_project" ]; then
    emit("gardening.scan", "$most_overdue_project")
else
    emit("LOOP_COMPLETE")
fi
```

This resolves multi-project routing: the board scanner iterates `team/projects/*/`, compares last-run timestamps, and emits `gardening.scan` for the single most overdue project. One project per cycle prevents long-running gardening from blocking other work. The event payload contains the project name so the gardener hat knows which project to process.

### 5. Tool Prerequisites

The executor requires these tools. Scanners degrade gracefully if a tool is missing (skip that scanner, log a warning).

| Tool | Project | Install | Purpose |
|------|---------|---------|---------|
| `cargo-audit` | botminter | `cargo install cargo-audit` | Security advisory scanning |
| `cargo-machete` | botminter | `cargo install cargo-machete` | Unused dependency detection |
| `rustfmt` | botminter | Ships with `rustup` (already present) | Format enforcement |
| `govulncheck` | hypershift | `go install golang.org/x/vuln/cmd/govulncheck@latest` | Go vulnerability scanning |

Already available: `clippy`, `cargo fmt`, `golangci-lint`, `gofmt`, `codespell`.

**Minimum scanner threshold:** If 0 scanners actually executed (all skipped due to missing tools), the executor logs `WARNING: No scanners executed for <project>. Check tool prerequisites.` and does NOT update the last-run timestamp. This prevents masking a broken setup behind a healthy-looking 7-day cycle.

## Data Models

### Finding Record (stdout line)

```
FINDING|lint|medium|crates/bm/src/bridge/mod.rs|clippy::needless_borrow: redundant borrow|true
FINDING|dependency|high|Cargo.toml|RUSTSEC-2024-0001: vulnerability in serde_yml 0.0.12|false
FINDING|format|low|crates/bm/src/daemon/mod.rs|formatting inconsistency (3 hunks)|true
```

**Why pipe-delimited instead of #114's multi-line VIOLATION format:** Gardening scanners produce many findings per run (potentially dozens of lint warnings + format diffs). Pipe-delimited lines are machine-parseable for batching into summaries and counting. #114's `VIOLATION/RULE/REMEDIATION/REFERENCE` multi-line format is designed for few, detailed check results that are read by humans. Different use cases warrant different formats.

### Tracking Issue (team board)

Created by the executor when an auto-fix PR is opened:

```markdown
## Gardening: Auto-fix review for botminter — 2026-04-04

**PR:** devguyio-bot-squad/botminter#42
**Epic:** #118

### Changes Applied
- 5 clippy auto-fixes (needless_borrow x3, redundant_clone x2)
- 12 files reformatted by rustfmt

### Verification
Unit tests passed before commit (`just unit`).

This issue tracks the PR through code review and QE verification.
```

### Gardening Summary (executor output)

```
GARDENING_SUMMARY|botminter|2026-04-04|scanners_ran=4|findings=12|auto_fixed=8|issues_created=1|pr=projects/botminter#42|tracking_issue=#120
```

### Last Run Timestamp

File: `team/projects/<project>/metrics/gardening-last-run.txt`

Content: Single ISO 8601 timestamp on one line, e.g. `2026-04-04T15:30:00Z`

Only updated when at least 1 scanner actually executed.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Scanner tool not installed | Skip that scanner. Log: `SKIP: cargo-audit not found. Install with: cargo install cargo-audit`. Continue with remaining scanners. Increment skipped-scanner count. |
| All scanner tools missing | Log: `WARNING: No scanners executed for <project>. Check tool prerequisites.` Do NOT update last-run timestamp. |
| Scanner exits with code 2+ | Log error, skip scanner, continue. Finding count unaffected. |
| Phase 1 auto-fixes produce test failures | Revert ALL Phase 1 changes (`git checkout .`). Do not create PR or tracking issue. Create a manual-fix bug issue describing which auto-fixes were attempted and the test failure. Continue to Phase 2. |
| PR creation fails (network) | Log error. Findings remain in the gardening branch locally. Retry next cycle. Do not create tracking issue (no PR to track). |
| Tracking issue creation fails | Log error. PR exists but has no board visibility. On next cycle, executor skips (branch exists), but a fix memory should be recorded for operator awareness. |
| Bug issue creation fails | Log error. Finding is lost for this cycle but will be rediscovered next run. |
| Project repo has uncommitted changes | Abort gardening for that project. Log: `ABORT: uncommitted changes in projects/<project>/`. |
| No findings | Normal exit. Update last-run timestamp (scanners ran successfully, just found nothing). No PR or issues created. |
| Gardening branch already exists for today | Skip execution (idempotent). |

### Test Before Commit (Phase 1 Gate)

Before committing Phase 1 auto-fixes, the executor runs the project's test suite:
- **botminter:** `just unit` (fast unit tests only, not E2E)
- **hypershift:** `make test` (with 10-minute timeout)

If tests fail after Phase 1 auto-fixes, the executor:
1. Reverts ALL Phase 1 changes (lint + format combined)
2. Creates a bug issue describing which scanners ran and the test failure output
3. Continues to Phase 2 (reporting-only scanners)

Since Phase 1 scanners are tested as a combined unit, test failure reverts all auto-fixes together. This is acceptable because lint and format fixes are interdependent (clippy output is reformatted by rustfmt). Per-scanner attribution of test failures is not needed — the bug issue includes the full test failure output for human investigation.

## Acceptance Criteria

**Given** the gardening system is configured and #114's check runner is deployed,
**When** the board scanner detects no actionable work and 7+ days have elapsed since the last gardening run for at least one project,
**Then** the scanner emits `gardening.scan` with the most overdue project name and the gardener hat runs the executor for that project.

**Given** the lint scanner detects auto-fixable clippy warnings in botminter,
**When** the gardening executor applies Phase 1 fixes (lint + format) and unit tests pass,
**Then** a PR is created on the botminter repo with the fixes, AND a tracking issue is created on the team board at `dev:code-review` status linking to the PR.

**Given** a gardening tracking issue exists at `dev:code-review`,
**When** the `dev_code_reviewer` hat processes it,
**Then** it reviews the linked PR on the project repo and advances the tracking issue through the normal workflow (`dev:code-review` → `qe:verify` → `done`).

**Given** the dependency audit scanner finds a high-severity advisory (RUSTSEC or Go vuln),
**When** the gardening executor processes Phase 2 findings,
**Then** a bug issue is created on the team project board with status `bug:investigate`, including the advisory ID and affected dependency.

**Given** a scanner tool (e.g., `cargo-audit`) is not installed,
**When** the executor attempts to run that scanner,
**Then** the scanner is skipped with a logged warning, and remaining scanners continue normally.

**Given** all scanner tools are missing for a project,
**When** the executor runs and 0 scanners execute,
**Then** the last-run timestamp is NOT updated, a warning is logged, and the project will be re-attempted next cycle.

**Given** Phase 1 auto-fixes cause test failures,
**When** the executor runs the test suite after applying lint + format fixes,
**Then** all Phase 1 changes are reverted, no PR or tracking issue is created, and a manual-fix bug issue is created describing the failure.

**Given** the project repo has uncommitted changes,
**When** the gardening executor starts,
**Then** gardening is aborted for that project with a clear log message.

**Given** the workspace has multiple projects (botminter, hypershift),
**When** both projects are overdue for gardening,
**Then** only the most overdue project is processed per cycle, and the other is processed on the next idle cycle.

## Impact on Existing System

### New Files (Team Repo)

| File | Purpose |
|------|---------|
| `team/coding-agent/skills/gardening/run-gardening.sh` | Executor script |
| `team/coding-agent/skills/gardening/scanners/lint-fix.sh` | Lint auto-fix scanner (Phase 1) |
| `team/coding-agent/skills/gardening/scanners/fmt-check.sh` | Format check scanner (Phase 1) |
| `team/coding-agent/skills/gardening/scanners/dep-audit.sh` | Dependency audit scanner (Phase 2) |
| `team/coding-agent/skills/gardening/scanners/unused-deps.sh` | Unused dependency scanner (Phase 2) |
| `team/projects/<project>/metrics/gardening-last-run.txt` | Last run timestamp |

### Changes to ralph.yml

| Section | Change |
|---------|--------|
| `hats` | Add `gardener` hat (triggers: `gardening.scan`, publishes: `gardening.done`, `gardening.failed`) |

### Changes to Board Scanner Skill

The board scanner's "no work found" path gains a gardening trigger check before emitting `LOOP_COMPLETE`. The trigger iterates `team/projects/*/` to find the most overdue project and includes the project name in the `gardening.scan` event payload.

### No Changes To

- BotMinter CLI (`bm`), agent CLI (`bm-agent`), daemon, HTTP API, or web console
- Ralph Orchestrator codebase
- Existing hat instructions (no existing hats are modified)
- Project repo CI configurations (gardening runs from the agent workspace, not CI)
- Existing invariants or check scripts from #114

### Interaction with #114

Gardening builds on #114's foundations:
- Uses the same scanner script location convention (`team/coding-agent/skills/`)
- Scanners live alongside check scripts in the team repo
- The check runner from #114 handles read-only checks; gardening scanners add write capability (auto-fixes)
- If #114's check scripts detect violations, gardening can address auto-fixable ones
- Output format differs intentionally: #114 uses multi-line `VIOLATION/RULE/REMEDIATION/REFERENCE` for detailed human-readable results; #118 uses pipe-delimited `FINDING` for machine-parseable batch processing of many findings

### Interaction with #117

If #117 (Metrics) is deployed:
- Gardening findings count and auto-fix rate can be emitted as metrics via the `workflow-collector.sh`
- Quality reports can include gardening activity trends
- If #117 is not deployed, gardening operates independently (no hard dependency)

## Security Considerations

### Dependency Audit Findings

- `cargo-audit` and `govulncheck` check against known vulnerability databases (RustSec Advisory DB, Go Vulnerability DB)
- High-severity findings create issues visible to the team — they do not auto-fix because dependency updates can introduce breaking changes or require API migration
- The gardening system does not auto-merge PRs; all changes go through `dev:code-review` and `qe:verify` via the tracking issue on the team board

### Auto-Fix Safety

- Auto-fixes are limited to deterministic tool outputs (`clippy --fix`, `rustfmt`, `gofmt`, `codespell`)
- All auto-fixes are tested before commit (project's unit test suite must pass)
- Failed tests cause automatic revert of ALL Phase 1 changes — no broken code is committed
- Auto-fix PRs go through the normal code review and QE verification workflow via a tracking issue on the team board at `dev:code-review`

### No Secret Exposure

- Scanners run in the agent workspace, not in CI — no secrets are passed to scanner scripts
- Gardening PRs are created with the existing `GH_TOKEN` (team token with repo and project scope)
- No new secrets or credentials are introduced

### Supply Chain

- New tool installations (`cargo-audit`, `cargo-machete`, `govulncheck`) are installed from official package registries (crates.io, pkg.go.dev)
- The executor does not download or execute arbitrary code beyond these standard developer tools
- Scanner scripts are committed to the team repo and subject to code review
