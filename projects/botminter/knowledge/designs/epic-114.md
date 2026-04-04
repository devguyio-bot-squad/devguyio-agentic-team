# Design: Executable Invariant Checks

**Epic:** #114 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's codebase has 11 ADRs in `.planning/adrs/` and 11 project invariants in `invariants/`. All are enforced by prose and agent judgment. ADR-0007 (domain-command layering) prohibits domain modules from using `println!`, `eprintln!`, or referencing CLI libraries (`clap`, `comfy_table`, `dialoguer`, `cliclack`). Today, 9 `eprintln!` calls across 4 domain modules violate this — undetected by the current workflow.

This epic adds executable check scripts with structured, agent-readable output. A check runner integrates these into the `dev_code_reviewer` and `qe_verifier` hats and runs in CI.

This is a BotMinter product capability: the check script contract, runner, and baseline profile-generic scripts ship as part of the scrum-compact profile. Each project authors its own project-specific checks. BotMinter dogfoods both levels.

### Harness Pattern

> "Because the lints are custom, we write the error messages to inject remediation instructions into agent context."

> "In a human-first workflow, these rules might feel pedantic or constraining. With agents, they become multipliers: once encoded, they apply everywhere at once."

Harness enforces a layered domain architecture (Types -> Config -> Repo -> Service -> Runtime -> UI) with custom linters that validate dependency directions mechanically. BotMinter's ADR-0007 defines a simpler two-layer model (command -> domain) with the same principle: mechanical enforcement over prose instructions.

### Scope

- Check script contract (output format, exit codes, working directory)
- Check runner script
- 4 baseline check scripts (2 profile-generic, 2 project-specific)
- Hat instruction updates (`dev_code_reviewer`, `qe_verifier`)
- CI integration (check runner as a CI step on every PR)
- CLAUDE.md update (reference check runner and key directories)

### Out of Scope

- Fixing the 9 existing ADR-0007 `eprintln!` violations (separate stories after checks are in place)
- AST-level analysis (checks are grep-level shell scripts)
- Ralph Orchestrator changes (no orchestrator-level modifications needed)
- Changes to the status graph or review workflow

---

## 2. Architecture

### 2.1 BotMinter Architecture Context

BotMinter is a multi-binary Rust application with:
- **CLI** (`bm`) — operator-facing CLI with 20+ subcommands
- **Agent CLI** (`bm-agent`) — agent-consumed tools binary
- **HTTP Daemon** (`daemon/`) — background process with Axum HTTP API (9 source files)
- **Web Console** (`web/`) — Axum routes serving a SvelteKit SPA (9 source files, embedded via `rust-embed`)

The codebase follows ADR-0006 (directory modules) and ADR-0007 (domain-command layering):
- **16 directory modules** under `crates/bm/src/`
- **15 domain modules** (everything except `commands/`)
- **Command layer** = `commands/`, `main.rs`, `cli.rs`, `agent_main.rs`, `agent_cli.rs`

Check scripts operate on the project repo source tree. They analyze static code properties — they are not runtime tests.

### 2.2 Two Check Scopes

| Scope | Location | Contains |
|---|---|---|
| Profile-generic | `team/invariants/checks/` | Checks for any project using scrum-compact |
| Project-specific | `projects/<project>/invariants/checks/` | Checks for this project's ADRs/invariants |

Profile-generic checks are extracted from the scrum-compact profile into `team/invariants/` during `bm init`. Project-specific checks live in the project repo.

### 2.3 Check Runner Flow

```
Hat invokes runner with project name
  -> Runner discovers .sh files in both check directories
    -> Runner sets cwd = projects/<project>/ for each script
      -> Script runs, produces VIOLATION output or exits clean
        -> Runner classifies: violation (exit 1 + VIOLATION) vs crash (exit 1 without, or exit >1)
          -> Runner aggregates: exit 0 if all pass, exit 1 if any violation
```

Runner location: `team/coding-agent/skills/check-runner/run-checks.sh`

Invocation by hats: `bash team/coding-agent/skills/check-runner/run-checks.sh botminter`

The runner sets `cwd = projects/botminter/` before executing each script. All relative paths in check scripts resolve against the project repo root — a script grepping `crates/bm/src/` works because `cwd` is the project repo.

### 2.4 Relationship to Existing Test Strategy

BotMinter has a three-tier test strategy:
- **Unit tests** — inline in source files (`cargo test -p bm`)
- **Integration/E2E tests** — `crates/bm/tests/e2e/` with `libtest-mimic` harness, real GitHub API
- **Exploratory tests** — `crates/bm/tests/exploratory/` with standalone bash scripts per phase

Check scripts are a **fourth tier** — static analysis that runs before any test execution. They catch structural violations early, before agents start coding or testing. They complement, not replace, the existing test infrastructure.

CI runs check scripts as a gate before running `cargo test` and E2E tests. This catches invariant violations before compilation and testing even begin.

---

## 3. Components and Interfaces

### 3.1 Check Script Contract

**Output format on violation (exit 1):**

```
VIOLATION: Domain module crates/bm/src/bridge/provisioning.rs uses eprintln! (lines 81, 183)
RULE: ADR-0007 domain-command layering — domain modules must not format output for the terminal
REMEDIATION: Return structured Result types from domain functions. Use tracing::warn! for diagnostics. Let the command layer display.
REFERENCE: .planning/adrs/0007-domain-command-layering.md
```

The REMEDIATION line gives the agent its next action. REFERENCE points to the governing rule.

**Exit codes:**
- 0 = pass
- 1 + VIOLATION on stdout = violation found
- 1 without VIOLATION, or >1 = script crash (logged as warning, does not block)

### 3.2 Baseline Check Scripts

**Profile-generic** (`team/invariants/checks/`):

| Script | Invariant | What It Checks |
|---|---|---|
| `file-size-limit.sh` | ADR-0006 (directory modules) | `wc -l` on `.rs` files under source dirs. Fail if >300 non-test lines. Exclude `target/`, test fixtures. |
| `test-path-isolation.sh` | `test-path-isolation` | `dirs::home_dir()` and `std::env::home_dir()` in `#[cfg(test)]` blocks without temp dir setup. |

**Project-specific** (`projects/botminter/invariants/checks/`):

| Script | Invariant | What It Checks |
|---|---|---|
| `domain-layer-imports.sh` | ADR-0007 | Greps for `println!`, `eprintln!`, `use clap`, `use comfy_table`, `use dialoguer`, `use cliclack` in all dirs under `crates/bm/src/` except the command layer (`commands/`, `main.rs`, `cli.rs`, `agent_main.rs`, `agent_cli.rs`). Uses directory exclusion — new domain modules are scanned automatically. |
| `no-hardcoded-profiles.sh` | `no-hardcoded-profiles` | Known profile name strings (`"scrum-compact"`, `"scrum"`) in `.rs` files. Excludes `tests/`, `test-fixtures/`, `profiles/`. |

### 3.3 Custom Linter Implementation Details

Each check script is a standalone shell script using `grep`/`rg` and `find`. No build tooling, no compiled linters.

**`domain-layer-imports.sh` implementation sketch:**

```bash
#!/usr/bin/env bash
# cwd is set to project root by the runner

EXCLUDE_DIRS="commands"
EXCLUDE_FILES="main.rs|cli.rs|agent_main.rs|agent_cli.rs"
PATTERNS="println!|eprintln!|use clap|use comfy_table|use dialoguer|use cliclack"
DOMAIN_ROOT="crates/bm/src"

violations=0

for dir in "$DOMAIN_ROOT"/*/; do
    dirname=$(basename "$dir")
    [[ "$dirname" == "commands" ]] && continue

    matches=$(grep -rn -E "$PATTERNS" "$dir" 2>/dev/null)
    if [[ -n "$matches" ]]; then
        while IFS= read -r match; do
            file=$(echo "$match" | cut -d: -f1)
            line=$(echo "$match" | cut -d: -f2)
            content=$(echo "$match" | cut -d: -f3-)
            echo "VIOLATION: Domain module $file uses prohibited import/call (line $line): $content"
            echo "RULE: ADR-0007 domain-command layering"
            echo "REMEDIATION: Move presentation to command layer. Use tracing macros for diagnostics."
            echo "REFERENCE: .planning/adrs/0007-domain-command-layering.md"
            echo ""
            violations=$((violations + 1))
        done <<< "$matches"
    fi
done

exit $((violations > 0 ? 1 : 0))
```

**False positive analysis:**
- `eprintln!` in `#[cfg(test)]` blocks: test code may legitimately use `eprintln!` for debugging. The script excludes `#[cfg(test)]` blocks from violations.
- String literals containing pattern words (e.g., `"eprintln! is prohibited"`): unlikely in domain modules; low false positive risk.

### 3.4 Known First-Run Violations

`domain-layer-imports.sh` will flag 9 existing `eprintln!` violations:

| Module | File | Lines | What |
|---|---|---|---|
| bridge | `bridge/provisioning.rs` | 81, 183 | Progress/warning during provisioning |
| formation | `formation/start_members.rs` | 167 | Status during member start |
| formation | `formation/local/linux/mod.rs` | 209 | Status during daemon start |
| git | `git/manifest_flow.rs` | 244, 249, 252 | Progress during App installation check |
| profile | `profile/agent.rs` | 151, 159 | Status messages during Minty config init |

Per ADR-0007: replace with `tracing::warn!`/`tracing::info!` or return structured `Result` types to the command layer. Fixing these is the first concrete deliverable after checks are in place.

### 3.5 Hat Integration

**`dev_code_reviewer`** gains in hat instructions:
> Before reviewing, run: `bash team/coding-agent/skills/check-runner/run-checks.sh <project>`. If any VIOLATION is reported, reject to `dev:implement` with the VIOLATION/REMEDIATION output as feedback.

**`qe_verifier`** gains:
> As part of verification, run the check runner. Violations block verification.

### 3.6 CI Integration

CI runs the same runner on every PR targeting the project repo:

```bash
bash team/coding-agent/skills/check-runner/run-checks.sh botminter
```

Same exit codes, same output. The e2e test harness (`crates/bm/tests/e2e/`, `libtest-mimic`, `--features e2e`) validates runtime behavior; check scripts validate static properties. They complement each other.

Exploratory tests (per invariants `exploratory-test-scope`, `exploratory-test-user-journey`) remain agent-driven. Check scripts catch static violations before agents start testing.

### 3.7 CLAUDE.md Changes

The project CLAUDE.md (`projects/botminter/CLAUDE.md`) gains:
- Reference to the check runner as a pre-review step
- Reference to `invariants/checks/` as the location for project-specific check scripts
- Guidance that new invariants should have corresponding check scripts when mechanically enforceable

---

## 4. Acceptance Criteria

- **Given** a code change introduces `println!` in a domain module, **when** `dev_code_reviewer` runs the check runner, **then** the check fails with VIOLATION output naming the file, line, rule (ADR-0007), and remediation.
- **Given** all checks pass, **when** `dev_code_reviewer` runs the runner, **then** review proceeds normally (exit 0).
- **Given** the existing 9 `eprintln!` violations, **when** `domain-layer-imports.sh` runs, **then** each is reported with file path, line numbers, and specific remediation.
- **Given** a new `.sh` script is added to either checks directory, **when** the runner executes, **then** the new script is discovered and run automatically.
- **Given** a check script has a syntax error (exit >1), **when** the runner executes it, **then** the crash is logged as a warning but does not block review.
- **Given** the runner runs in CI on a PR, **when** a domain-layer violation exists, **then** CI fails with the same VIOLATION output agents see locally.

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| `team/invariants/checks/` | New directory + 2 profile-generic scripts |
| `projects/botminter/invariants/checks/` | New directory + 2 project-specific scripts |
| `team/coding-agent/skills/check-runner/` | New runner script |
| `team/knowledge/check-script-contract.md` | New knowledge doc defining the contract |
| `dev_code_reviewer` hat instructions | Add check-running step before review |
| `qe_verifier` hat instructions | Add check-running step during verification |
| `projects/botminter/CLAUDE.md` | Reference check runner and invariant checks |

**No changes to:** Ralph Orchestrator, existing invariant markdown files, status graph, formation system, bridge system, daemon/web console, existing 11 ADRs, existing test infrastructure.

---

## 6. Security Considerations

Check scripts are read-only file analyzers. They scan code with `grep`/`find` — they do not modify files, make network requests, or alter git state. Scripts are version-controlled in the team repo (profile-generic) or project repo (project-specific).

**Attack surface:** A malicious check script could only read files the agent already has access to. The runner does not execute arbitrary user input — it discovers and runs `.sh` files from known directories.

**Crash isolation:** Three consecutive crashes from the same script are classified as crashes (not violations) and logged. The runner does not retry crashed scripts — it reports them and continues with the remaining checks.

**No secret exposure:** Check scripts operate on source code files only. They do not access `.env`, credentials, or runtime secrets.
