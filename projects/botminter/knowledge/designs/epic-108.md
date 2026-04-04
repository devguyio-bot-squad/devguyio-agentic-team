# Design: Executable Invariant Checks

**Epic:** #108 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's codebase has 11 ADRs in `.planning/adrs/` and 11 project invariants in `invariants/`. All are enforced by prose and agent judgment. ADR-0007 (domain-command layering) prohibits domain modules from using `println!`, `eprintln!`, or referencing CLI libraries (`clap`, `comfy_table`, `dialoguer`, `cliclack`). Today, 9 `eprintln!` calls across 5 domain modules violate this — undetected.

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
- CI integration

### Out of Scope

- Fixing the 9 existing ADR-0007 `eprintln!` violations (separate stories after checks are in place)
- AST-level analysis (checks are grep-level shell scripts per ADR-0002's shell script bridge pattern)
- Ralph Orchestrator changes

---

## 2. Architecture

### Two Check Scopes

| Scope | Location | Contains |
|---|---|---|
| Profile-generic | `team/invariants/checks/` | Checks for any project using scrum-compact |
| Project-specific | `projects/<project>/invariants/checks/` | Checks for this project's ADRs/invariants |

Profile-generic checks are extracted from the scrum-compact profile into `team/invariants/` during `bm init`. Project-specific checks live in the project repo.

### Check Runner Flow

```
Hat invokes runner with project name
  → Runner discovers .sh files in both check directories
    → Runner sets cwd = projects/<project>/ for each script
      → Script runs, produces VIOLATION output or exits clean
        → Runner classifies: violation (exit 1 + VIOLATION) vs crash (exit 1 without, or exit >1)
          → Runner aggregates: exit 0 if all pass, exit 1 if any violation
```

Runner location: `team/coding-agent/skills/check-runner/run-checks.sh`

Invocation by hats: `bash team/coding-agent/skills/check-runner/run-checks.sh botminter`

All relative paths in check scripts resolve against `cwd = projects/botminter/`. A script grepping `crates/bm/src/` works because `cwd` is the project repo root.

---

## 3. Components and Interfaces

### Check Script Contract

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

### Baseline Check Scripts

**Profile-generic** (`team/invariants/checks/`):

| Script | Invariant | What It Greps |
|---|---|---|
| `file-size-limit.sh` | ADR-0006 | `wc -l` on `.rs` files under domain module dirs. Fail if >300 non-test lines. Exclude `target/`. |
| `test-path-isolation.sh` | `test-path-isolation` | `dirs::home_dir()` and `std::env::home_dir()` in `#[cfg(test)]` blocks without temp dir setup. |

**Project-specific** (`projects/botminter/invariants/checks/`):

| Script | Invariant | What It Greps |
|---|---|---|
| `domain-layer-imports.sh` | ADR-0007 | `println!`, `eprintln!`, `use clap`, `use comfy_table`, `use dialoguer`, `use cliclack` in all dirs under `crates/bm/src/` except the command layer (`commands/`, `main.rs`, `cli.rs`, `agent_main.rs`, `agent_cli.rs`). Uses directory exclusion — new domain modules are scanned automatically. |
| `no-hardcoded-profiles.sh` | `no-hardcoded-profiles` | Known profile name strings (`"scrum-compact"`, `"scrum"`) in `.rs` files. Excludes `tests/`, `test-fixtures/`, `profiles/`. |

### Known First-Run Violations

`domain-layer-imports.sh` will flag 9 existing violations:

| Module | File | Lines | What |
|---|---|---|---|
| profile | `profile/agent.rs` | 151, 159 | Status messages during Minty config init |
| bridge | `bridge/provisioning.rs` | 81, 183 | Progress/warning during provisioning |
| formation | `formation/start_members.rs` | 167 | Status during member start |
| formation | `formation/local/linux/mod.rs` | 209 | Status during daemon start |
| git | `git/manifest_flow.rs` | 244, 249, 252 | Progress during App installation check |

Per ADR-0007: replace with `tracing::warn!`/`tracing::info!` or return structured `Result` types to the command layer. Fixing these is the first concrete deliverable after checks are in place.

### Hat Integration

**`dev_code_reviewer`** gains in hat instructions:
> Before reviewing, run: `bash team/coding-agent/skills/check-runner/run-checks.sh <project>`. If any VIOLATION is reported, reject to `dev:implement` with the VIOLATION/REMEDIATION output as feedback.

**`qe_verifier`** gains:
> As part of verification, run the check runner. Violations block verification.

### CI Integration

CI runs the same runner on every PR: `bash team/coding-agent/skills/check-runner/run-checks.sh botminter`. Same exit codes, same output. The e2e test harness (`tests/e2e/`, `libtest-mimic`, `--features e2e`) validates runtime behavior; check scripts validate static properties. They complement each other.

Exploratory tests (per invariants `exploratory-test-scope`, `exploratory-test-user-journey`) remain agent-driven. Check scripts catch static violations before agents start testing.

---

## 4. Acceptance Criteria

- **Given** a code change introduces `println!` in a domain module, **when** `dev_code_reviewer` runs the check runner, **then** the check fails with VIOLATION output naming the file, line, rule (ADR-0007), and remediation.
- **Given** all checks pass, **when** `dev_code_reviewer` runs the runner, **then** review proceeds normally.
- **Given** the existing 9 `eprintln!` violations, **when** `domain-layer-imports.sh` runs, **then** each is reported with file path, line numbers, and specific remediation.
- **Given** a new `.sh` script is added to either checks directory, **when** the runner executes, **then** the new script is discovered and run.
- **Given** a check script has a syntax error (exit >1), **when** the runner executes it, **then** the crash is logged as a warning but does not block review.
- **Given** the runner runs in CI on a PR, **when** a domain-layer violation exists, **then** CI fails with the same output agents see.

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| `team/invariants/checks/` | New directory + 2 scripts |
| `projects/botminter/invariants/checks/` | New directory + 2 scripts |
| `team/coding-agent/skills/check-runner/` | New runner script |
| `team/knowledge/check-script-contract.md` | New knowledge doc |
| `dev_code_reviewer` hat instructions (`ralph.yml`) | Add check-running step |
| `qe_verifier` hat instructions (`ralph.yml`) | Add check-running step |
| CLAUDE.md | Reference check runner, key directories |

No changes to: Ralph Orchestrator, existing invariant markdown files, status graph, formation system, existing 11 ADRs.

---

## 6. Security Considerations

Check scripts are read-only file analyzers. They scan code — they do not modify files, make network requests, or alter git state. Scripts are version-controlled in the team repo (profile-generic) or project repo (project-specific). A malicious check script could only read files the agent already has access to. Three consecutive crashes from the same script flag it for human attention via an issue.
