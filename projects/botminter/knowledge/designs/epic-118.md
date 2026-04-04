---
type: design
status: draft
parent: "106"
epic: "118"
revision: 1
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
2. **Gardening executor** — a coordinator script that runs scanners, applies auto-fixes, and creates issues for manual fixes
3. **Board integration** — gardening findings become bug-type issues following the existing simple bug workflow

The system runs on a periodic trigger (not blocking feature work) and produces small, reviewable PRs for auto-fixable issues.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Gardening Executor                      │
│         team/coding-agent/skills/gardening/              │
│                run-gardening.sh                          │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Lint Scanner  │  │  Fmt Scanner │  │ Dep Scanner  │  │
│  │  lint-fix.sh  │  │ fmt-check.sh │  │ dep-audit.sh │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                  │          │
│         └────────┬────────┴────────┬─────────┘          │
│                  │                 │                     │
│           ┌──────▼──────┐  ┌──────▼──────┐              │
│           │  Auto-fix   │  │ Issue Create │              │
│           │  + PR       │  │ (manual fix) │              │
│           └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   GitHub Board        │
              │  (simple bug track)   │
              │  bug:investigate →    │
              │  bug:in-progress →    │
              │  dev:code-review →    │
              │  qe:verify → done    │
              └───────────────────────┘
```

**Working directories:**
- Executor and scanner scripts: `team/coding-agent/skills/gardening/`
- Scanners execute inside the target project directory: `projects/botminter/` or `projects/hypershift/`
- Auto-fix PRs are created on the project repository (e.g., `devguyio-bot-squad/botminter`)
- Issue tracking happens on the team repository's GitHub project board

### Execution Model

Gardening runs as a **periodic background activity** that does not block the main board dispatch loop:

1. The board scanner checks for a gardening trigger condition after processing all actionable issues (when `LOOP_COMPLETE` would normally be emitted)
2. If enough time has elapsed since the last gardening run (configurable, default: 7 days), the scanner emits `gardening.scan` instead of `LOOP_COMPLETE`
3. A new `gardener` hat handles the `gardening.scan` event, runs the executor, creates PRs/issues, and returns control
4. Gardening-created issues enter the normal workflow and are processed by existing hats

Gardening fills idle cycles rather than competing with feature development.

## Components and Interfaces

### 1. Gardening Scanners

Each scanner is a standalone shell script following #114's conventions.

**Input:** Project directory path (first argument), project name (second argument)

**Output:** Structured findings to stdout, one per line:

```
FINDING|<category>|<severity>|<file>|<description>|<auto-fixable>
```

- **Categories:** `lint`, `format`, `dependency`, `dead-code`
- **Severity:** `low`, `medium`, `high` (high = security advisory)
- **Auto-fixable:** `true` or `false`

**Exit codes:** 0 = no findings, 1 = findings reported, 2+ = scanner error (non-blocking)

#### Scanner: `lint-fix.sh`

Detects lint warnings fixable by the project's lint tool.

- **botminter:** Runs `cargo clippy --fix --allow-dirty --allow-staged -p bm --features console 2>&1`. Captures which files were modified via `git diff --name-only`.
- **hypershift:** Runs `golangci-lint run --fix ./... 2>&1`. Captures modifications via `git diff --name-only`.

#### Scanner: `fmt-check.sh`

Detects formatting inconsistencies.

- **botminter:** Runs `cargo fmt -- --check`, lists files needing formatting. Applies fix via `cargo fmt`.
- **hypershift:** Runs `gofmt -l .`, lists unformatted files. Also runs `codespell --check-filenames -q 3` for spelling. Applies fixes via `gofmt -w` and `codespell -w`.

#### Scanner: `dep-audit.sh`

Detects dependency security issues.

- **botminter:** Runs `cargo audit` (requires `cargo-audit` installed). Reports known vulnerabilities in Cargo dependencies.
- **hypershift:** Runs `govulncheck ./...` (Go native vulnerability checker).
- Findings are always `auto-fixable: false` — dependency updates need human judgment.

#### Scanner: `unused-deps.sh`

Detects unused dependencies.

- **botminter:** Runs `cargo machete` (detects unused crate dependencies in `Cargo.toml`). Findings are `auto-fixable: false` (removal needs verification).
- **hypershift:** Runs `go mod tidy -diff` to detect unused Go module dependencies. Applies fix via `go mod tidy` (auto-fixable).

### 2. Gardening Executor

**Location:** `team/coding-agent/skills/gardening/run-gardening.sh`

**Arguments:** `<project-name>` (e.g., `botminter`, `hypershift`)

**Behavior:**

1. Verify the project repo has no uncommitted changes. Abort if dirty.
2. Create a `gardening/<YYYY-MM-DD>` branch in the project repo.
3. Run all scanners for that project, collecting findings.
4. Group auto-fixable findings and apply fixes (each scanner's fix mode).
5. Run the project's test suite to verify fixes don't break anything.
6. If tests pass and auto-fixes were applied:
   - Commit changes: `chore(gardening): auto-fix lint/format issues`
   - Create a PR on the project repo
7. For non-auto-fixable findings with severity `high`:
   - Create a bug issue on the team repo's project board with `project/<project>` label
   - Set initial status to `bug:investigate`
8. Update last-run timestamp.
9. Output a gardening summary to stdout.

**Idempotency:** If a `gardening/<YYYY-MM-DD>` branch already exists, the executor skips (prevents duplicate PRs).

### 3. Gardener Hat

A new hat added to `ralph.yml`:

```yaml
gardener:
  triggers: ["gardening.scan"]
  publishes: ["gardening.done", "gardening.failed"]
```

Instructions:
1. Run: `bash team/coding-agent/skills/gardening/run-gardening.sh <project>`
2. If auto-fix PR was created, post a progress update via RObot with the PR link
3. If high-severity dependency issues were found, post a progress update
4. Emit `gardening.done` with summary

### 4. Board Scanner Integration

The board scanner's dispatch logic gains a gardening trigger in the "no work found" path:

```
# After normal dispatch finds no actionable work:
last_run=$(cat team/projects/<project>/metrics/gardening-last-run.txt 2>/dev/null || echo "1970-01-01T00:00:00Z")
days_since=$(( ($(date +%s) - $(date -d "$last_run" +%s)) / 86400 ))

if [ "$days_since" -ge 7 ]; then
    emit("gardening.scan")
else
    emit("LOOP_COMPLETE")
fi
```

### 5. Tool Prerequisites

The executor requires these tools. Scanners degrade gracefully if a tool is missing (skip that scanner, log a warning).

| Tool | Project | Install | Purpose |
|------|---------|---------|---------|
| `cargo-audit` | botminter | `cargo install cargo-audit` | Security advisory scanning |
| `cargo-machete` | botminter | `cargo install cargo-machete` | Unused dependency detection |
| `rustfmt` | botminter | Ships with `rustup` (already present) | Format enforcement |
| `govulncheck` | hypershift | `go install golang.org/x/vuln/cmd/govulncheck@latest` | Go vulnerability scanning |

Already available: `clippy`, `cargo fmt`, `golangci-lint`, `gofmt`, `codespell`.

## Data Models

### Finding Record (stdout line)

```
FINDING|lint|medium|crates/bm/src/bridge/mod.rs|clippy::needless_borrow: redundant borrow|true
FINDING|dependency|high|Cargo.toml|RUSTSEC-2024-0001: vulnerability in serde_yml 0.0.12|false
FINDING|format|low|crates/bm/src/daemon/mod.rs|formatting inconsistency (3 hunks)|true
```

### Gardening Summary (executor output)

```
GARDENING_SUMMARY|botminter|2026-04-04|findings=12|auto_fixed=8|issues_created=1|pr=projects/botminter#42
```

### Last Run Timestamp

File: `team/projects/<project>/metrics/gardening-last-run.txt`

Content: Single ISO 8601 timestamp on one line, e.g. `2026-04-04T15:30:00Z`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Scanner tool not installed | Skip that scanner. Log: `SKIP: cargo-audit not found. Install with: cargo install cargo-audit`. Continue with remaining scanners. |
| Scanner exits with code 2+ | Log error, skip scanner, continue. Finding count unaffected. |
| Auto-fix produces test failures | Discard the gardening branch (`git checkout .`). Do not create PR. Log the failure. Create a manual-fix bug issue instead. |
| PR creation fails (network) | Log error. Findings remain in the gardening branch locally. Retry next cycle. |
| Issue creation fails | Log error. Finding is lost for this cycle but will be rediscovered next run. |
| Project repo has uncommitted changes | Abort gardening for that project. Log: `ABORT: uncommitted changes in projects/<project>/`. |
| No findings | Normal exit. Update last-run timestamp. No PR or issues created. |
| Gardening branch already exists for today | Skip execution (idempotent). |

### Test Before Commit

Before committing auto-fixes, the executor runs the project's test suite:
- **botminter:** `just unit` (fast unit tests only, not E2E)
- **hypershift:** `make test` (with 10-minute timeout)

If tests fail after auto-fixes, the executor:
1. Reverts the auto-fix changes
2. Creates a bug issue describing which auto-fixes broke tests
3. Continues to non-auto-fixable finding reporting

## Acceptance Criteria

**Given** the gardening system is configured and #114's check runner is deployed,
**When** the board scanner detects no actionable work and 7+ days have elapsed since the last gardening run,
**Then** the scanner emits `gardening.scan` and the gardener hat runs the executor.

**Given** the lint scanner detects auto-fixable clippy warnings in botminter,
**When** the gardening executor applies fixes and unit tests pass,
**Then** a PR is created on the botminter repo with the fixes and a conventional commit message (`chore(gardening): auto-fix lint/format issues`).

**Given** the dependency audit scanner finds a high-severity advisory (RUSTSEC or Go vuln),
**When** the gardening executor processes findings,
**Then** a bug issue is created on the team project board with status `bug:investigate`, including the advisory ID and affected dependency.

**Given** a scanner tool (e.g., `cargo-audit`) is not installed,
**When** the executor attempts to run that scanner,
**Then** the scanner is skipped with a logged warning, and remaining scanners continue normally.

**Given** auto-fixes cause test failures,
**When** the executor runs the test suite after applying fixes,
**Then** fixes are reverted, no PR is created, and a manual-fix bug issue is created describing the failure.

**Given** the project repo has uncommitted changes,
**When** the gardening executor starts,
**Then** gardening is aborted for that project with a clear log message.

**Given** a gardening PR is created,
**When** the PR enters the board workflow,
**Then** it follows the normal code review and QE verification path (dev:code-review → qe:verify → done).

## Impact on Existing System

### New Files (Team Repo)

| File | Purpose |
|------|---------|
| `team/coding-agent/skills/gardening/run-gardening.sh` | Executor script |
| `team/coding-agent/skills/gardening/scanners/lint-fix.sh` | Lint auto-fix scanner |
| `team/coding-agent/skills/gardening/scanners/fmt-check.sh` | Format check scanner |
| `team/coding-agent/skills/gardening/scanners/dep-audit.sh` | Dependency audit scanner |
| `team/coding-agent/skills/gardening/scanners/unused-deps.sh` | Unused dependency scanner |
| `team/projects/<project>/metrics/gardening-last-run.txt` | Last run timestamp |

### Changes to ralph.yml

| Section | Change |
|---------|--------|
| `hats` | Add `gardener` hat (triggers: `gardening.scan`, publishes: `gardening.done`, `gardening.failed`) |

### Changes to Board Scanner Skill

The board scanner's "no work found" path gains a gardening trigger check before emitting `LOOP_COMPLETE`.

### No Changes To

- BotMinter CLI (`bm`), agent CLI (`bm-agent`), daemon, HTTP API, or web console
- Ralph Orchestrator codebase
- Existing hat instructions (no existing hats are modified)
- Project repo CI configurations (gardening runs from the agent workspace, not CI)
- Existing invariants or check scripts from #114

### Interaction with #114

Gardening builds on #114's foundations:
- Uses the same structured output conventions (extending `VIOLATION` with `FINDING`)
- Scanners live alongside check scripts in the team repo under `team/coding-agent/skills/`
- The check runner from #114 handles read-only checks; gardening scanners add write capability (auto-fixes)
- If #114's check scripts detect violations, gardening can address auto-fixable ones

### Interaction with #117

If #117 (Metrics) is deployed:
- Gardening findings count and auto-fix rate can be emitted as metrics via the `workflow-collector.sh`
- Quality reports can include gardening activity trends
- If #117 is not deployed, gardening operates independently (no hard dependency)

## Security Considerations

### Dependency Audit Findings

- `cargo-audit` and `govulncheck` check against known vulnerability databases (RustSec Advisory DB, Go Vulnerability DB)
- High-severity findings create issues visible to the team — they do not auto-fix because dependency updates can introduce breaking changes or require API migration
- The gardening system does not auto-merge PRs; all changes go through `dev:code-review` and `qe:verify`

### Auto-Fix Safety

- Auto-fixes are limited to deterministic tool outputs (`clippy --fix`, `rustfmt`, `gofmt`, `codespell`)
- All auto-fixes are tested before commit (project's unit test suite must pass)
- Failed tests cause automatic revert — no broken code is committed
- Auto-fix PRs go through the normal code review and QE verification workflow

### No Secret Exposure

- Scanners run in the agent workspace, not in CI — no secrets are passed to scanner scripts
- Gardening PRs are created with the existing `GH_TOKEN` (team token with repo and project scope)
- No new secrets or credentials are introduced

### Supply Chain

- New tool installations (`cargo-audit`, `cargo-machete`, `govulncheck`) are installed from official package registries (crates.io, pkg.go.dev)
- The executor does not download or execute arbitrary code beyond these standard developer tools
- Scanner scripts are committed to the team repo and subject to code review
