# Design: Executable Invariant Checks

**Epic:** #114 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's codebase has 11 ADRs in `.planning/adrs/` and 11 project invariants in `invariants/`. All are enforced by prose and agent judgment. ADR-0007 (domain-command layering) prohibits domain modules from using `println!`, `eprintln!`, or referencing CLI libraries (`clap`, `comfy_table`, `dialoguer`, `cliclack`). Today, 9 `eprintln!` calls across 4 domain modules violate this — undetected by the current workflow.

This epic adds executable check scripts with structured, agent-readable output. A check runner integrates these into the `dev_code_reviewer` and `qe_verifier` hats and runs in CI.

The check script contract and runner are team-level infrastructure (`team/coding-agent/skills/`). All 4 initial check scripts are project-specific (`projects/botminter/invariants/checks/`) because they enforce Rust-specific and BotMinter-specific rules. Profile-generic checks (in `team/invariants/checks/`) are deferred until genuinely language-agnostic checks are needed.

### Harness Pattern

> "Because the lints are custom, we write the error messages to inject remediation instructions into agent context."

> "In a human-first workflow, these rules might feel pedantic or constraining. With agents, they become multipliers: once encoded, they apply everywhere at once."

Harness enforces a layered domain architecture (Types -> Config -> Repo -> Service -> Runtime -> UI) with custom linters that validate dependency directions mechanically. BotMinter's ADR-0007 defines a simpler two-layer model (command -> domain) with the same principle: mechanical enforcement over prose instructions.

### Scope

- Check script contract (output format, exit codes, working directory)
- Check runner script
- 4 project-specific check scripts (all in `projects/botminter/invariants/checks/`)
- Hat instruction updates (`dev_code_reviewer`, `qe_verifier`)
- CLAUDE.md update (reference check runner and key directories)

**Deferred:** CI integration is deferred to a follow-up story (see §3.6 for rationale).

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

The codebase follows ADR-0006 (directory modules — structural requirement for `foo/mod.rs` layout) and ADR-0007 (domain-command layering — behavioral separation with ~300 line sub-file limit):
- **16 directory modules** under `crates/bm/src/`
- **15 domain modules** (everything except `commands/`)
- **Command layer** = `commands/`, `main.rs`, `cli.rs`, `agent_main.rs`, `agent_cli.rs`

Check scripts operate on the project repo source tree. They analyze static code properties — they are not runtime tests.

### 2.2 Check Scope: Project-Specific

All 4 check scripts live in `projects/botminter/invariants/checks/`. They enforce BotMinter-specific ADRs and invariants using Rust-aware patterns (`grep` on `.rs` files, BotMinter-specific paths). None of the checks have `#[cfg(test)]` block awareness — grep-based scripts cannot distinguish test code from production code within the same file (see §3.3 Known Limitations).

**Why not profile-generic?** The scrum-compact profile is a process profile, not a language profile. All 4 initial checks are Rust-specific (grep `.rs` files, reference `crates/bm/src/`, check for `dirs::home_dir()`). Placing them in `team/invariants/checks/` would claim language-agnostic applicability they don't have. Profile-generic checks are appropriate when genuinely language-agnostic checks exist (e.g., "no files over N lines regardless of extension", "no secrets in committed files"). That boundary is deferred until such a check is needed.

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

Check scripts are a **pre-test static analysis gate** — they scan source files with `grep`/`find` without executing any code. They are not a test tier; they are a separate category from the runtime test infrastructure. Static analysis catches structural violations early, before agents start coding or testing. It complements, not replaces, the existing test strategy.

The check runner runs before `cargo test` and E2E tests, catching invariant violations before compilation and testing even begin.

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

All scripts live in `projects/botminter/invariants/checks/`:

| Script | Invariant | What It Checks |
|---|---|---|
| `file-size-limit.sh` | ADR-0007 (domain-command layering, line 143: "No sub-file exceeds ~300 lines") | `wc -l` on `.rs` files under `crates/bm/src/`. Warn if >300 total lines (soft threshold per ADR-0007's "~300" qualifier). Counts all lines — no `#[cfg(test)]` block exclusion, since `wc -l` cannot distinguish test code from production code and ADR-0007 states the ~300 limit without a test-exclusion caveat. Excludes `target/`, test fixtures. Scans **all** `.rs` files including `commands/` — ADR-0007 applies the ~300 line rule to domain sub-files and a stricter ~100 line rule to command files ("Exceed ~100 lines of non-test code — thickness signals domain logic that has not been extracted"), so the 300-line threshold is a lenient heuristic for both layers. Note: ADR-0007 applies the ~300 line rule to sub-files within directory modules, not to all `.rs` files — the check uses this as a project-wide heuristic. |
| `test-path-isolation.sh` | `test-path-isolation` (project invariant) | Greps for `dirs::home_dir()` and `std::env::home_dir()` in `.rs` files under `crates/bm/tests/` **only**. Flags any usage in test code — test files should use `tempdir()` or equivalent isolation, never the real home directory. Production code (`crates/bm/src/`) is **excluded**: `dirs::home_dir()` is used legitimately there (e.g., `config/mod.rs` for config resolution, `formation/lima.rs` for VM paths). The check does not attempt semantic tempdir-pairing analysis — it simply reports `home_dir` calls in test files as violations. This check is BotMinter-specific: the invariant references `~/.botminter` paths and `bm_cmd()` APIs. **Known false positive:** `integration.rs:6` contains `//! config via dirs::home_dir() are invoked...` — a doc comment (`//!`), not a function call. Grep cannot distinguish doc comments from actual code. This will be reported as a violation on first run. Mitigation: add `// check:ignore` (or accept as a known false positive and suppress in the baseline). **Known invariant gap:** The `test-path-isolation` invariant also covers `#[cfg(test)]` modules in `crates/bm/src/` (unit tests), but this check does not scan `src/` — doing so would require distinguishing `#[cfg(test)]` blocks from production code, which grep cannot do. Legitimate production `dirs::home_dir()` calls: config/mod.rs:95,179,188; formation/lima.rs:286; commands/debug.rs:268. Note: formation/lima.rs:462 is **test code** — it is inside `#[cfg(test)] mod tests` (starting at line 457), not production code. Currently 1 violation exists in this gap (formation/lima.rs:462). |
| `domain-layer-imports.sh` | ADR-0007 | Greps for `println!`, `eprintln!`, `use clap`, `use comfy_table`, `use dialoguer`, `use cliclack` in all modules under `crates/bm/src/` except the command layer (`commands/`, `main.rs`, `cli.rs`, `agent_main.rs`, `agent_cli.rs`). Scans both directory modules (`$DOMAIN_ROOT/*/`) and standalone domain `.rs` files (`$DOMAIN_ROOT/*.rs`, excluding command-layer files). New domain modules — whether directories or standalone files — are scanned automatically. |
| `no-hardcoded-profiles.sh` | `no-hardcoded-profiles` (partial) | Scans for lines containing profile name strings (`scrum-compact`, `scrum`) in `.rs` files under `crates/bm/src/`. Excludes `commands/` only. Matches include string literals (`"scrum"`), path references (`profiles/scrum/`), function names (`fn rh_scrum_has_views`), and assertion messages — any line containing the profile name is a hardcoded reference. **Baseline:** 74 existing occurrences — all in `#[cfg(test)]` blocks (web/files.rs:15, profile/mod.rs:14, profile/agent.rs:12, profile/extraction.rs:11, config/mod.rs:7, web/teams.rs:4, web/members.rs:3, git/manifest_flow.rs:3, team.rs:1, profile/member.rs:1, formation/init.rs:1, bridge/manifest.rs:1, agent_tags/mod.rs:1). These are test fixtures, function names, and path strings that hardcode profile names, violating the invariant's intent. **`#[cfg(test)]` exclusion policy:** grep cannot distinguish `#[cfg(test)]` blocks from production code, so all 74 will be reported as violations on first run. Like `domain-layer-imports.sh`, the `// check:ignore` suppression mechanism applies, but the right fix is to make these tests use dynamic profile discovery per the invariant. **Caveat:** This check enforces the profile-name subset of the `no-hardcoded-profiles` invariant. The full invariant also prohibits hardcoded role names, status values, label names, and other profile-derived data — those remain enforced by agent judgment during code review, as they require semantic understanding of what constitutes "profile-derived data." |

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

# Pass 1: Directory modules
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

# Pass 2: Standalone domain .rs files (excluding command-layer files)
for file in "$DOMAIN_ROOT"/*.rs; do
    [[ ! -f "$file" ]] && continue
    fname=$(basename "$file")
    [[ "$fname" =~ ^(main|cli|agent_main|agent_cli)\.rs$ ]] && continue

    matches=$(grep -n -E "$PATTERNS" "$file" 2>/dev/null)
    if [[ -n "$matches" ]]; then
        while IFS= read -r match; do
            line=$(echo "$match" | cut -d: -f1)
            content=$(echo "$match" | cut -d: -f2-)
            echo "VIOLATION: Domain file $file uses prohibited import/call (line $line): $content"
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

**Known limitations and false positives:**
- `eprintln!` in `#[cfg(test)]` blocks: test code may legitimately use `eprintln!` for debugging. The flat `grep -rn` implementation has **no `#[cfg(test)]` block awareness** — it cannot distinguish test code from production code within the same file. Excluding test blocks from grep-based shell scripts is non-trivial (requires multi-pass processing to identify block line ranges). **Mitigation:** A `// check:ignore` inline comment (Rust line comment syntax) suppresses the violation for that line. The implementation story should document the suppression syntax and add it to the check script contract.
- String literals containing pattern words (e.g., `"eprintln! is prohibited"`): unlikely in domain modules; low false positive risk.

### 3.4 Known First-Run Violations

`file-size-limit.sh` will flag 47 existing files exceeding 300 lines (40 domain + 7 command-layer):

| Layer | File | Lines |
|---|---|---|
| domain | `profile/extraction.rs` | 1508 |
| domain | `workspace/repo.rs` | 1287 |
| domain | `web/files.rs` | 1102 |
| domain | `profile/mod.rs` | 1003 |
| domain | `daemon/api.rs` | 997 |
| domain | `brain/bridge_adapter.rs` | 985 |
| command | `commands/init.rs` | 939 |
| command | `cli.rs` | 786 |
| domain | `formation/mod.rs` | 729 |
| domain | `brain/event_watcher.rs` | 696 |
| domain | `chat/mod.rs` | 685 |
| domain | `formation/lima.rs` | 675 |
| domain | `profile/team_repo.rs` | 670 |
| domain | `agent_tags/mod.rs` | 670 |
| domain | `git/github.rs` | 656 |
| domain | `git/manifest_flow.rs` | 646 |
| domain | `workspace/util.rs` | 582 |
| command | `commands/completions.rs` | 575 |
| domain | `web/members.rs` | 563 |
| domain | `workspace/sync.rs` | 557 |
| domain | `web/overview.rs` | 548 |
| domain | `formation/start_members.rs` | 547 |
| domain | `bridge/manifest.rs` | 542 |
| domain | `acp/client.rs` | 522 |
| domain | `formation/local/linux/mod.rs` | 507 |
| domain | `formation/local/linux/credential.rs` | 490 |
| domain | `config/mod.rs` | 482 |
| domain | `bridge/credential.rs` | 477 |
| domain | `bridge/mod.rs` | 475 |
| domain | `brain/inbox.rs` | 435 |
| domain | `profile/agent.rs` | 429 |
| domain | `workspace/team_sync.rs` | 417 |
| command | `commands/debug.rs` | 412 |
| domain | `brain/multiplexer.rs` | 405 |
| domain | `daemon/client.rs` | 403 |
| domain | `profile/embedded.rs` | 389 |
| domain | `brain/heartbeat.rs` | 386 |
| domain | `daemon/run.rs` | 384 |
| domain | `web/process.rs` | 379 |
| domain | `state/mod.rs` | 375 |
| domain | `profile/member.rs` | 364 |
| command | `commands/brain_run.rs` | 338 |
| domain | `team.rs` | 335 |
| command | `commands/profiles_init.rs` | 331 |
| domain | `formation/stop_members.rs` | 312 |
| command | `main.rs` | 307 |
| domain | `daemon/process.rs` | 301 |

All paths relative to `crates/bm/src/`. Largest: `profile/extraction.rs` (1508 lines, 5x the threshold). `wc -l` counts all lines including `#[cfg(test)]` blocks — many of these files have substantial test code that inflates the count. Per ADR-0007, the ~300 line limit is a soft threshold ("~300" qualifier), so these are reported as violations but represent existing technical debt, not regressions. The check's value is preventing new files from exceeding the threshold and detecting growth in existing files.

`test-path-isolation.sh` will flag 1 false positive in `crates/bm/tests/`:

| File | Line | What |
|---|---|---|
| `integration.rs` | 6 | `//! config via dirs::home_dir() are invoked...` — doc comment (`//!`), not a function call |

This is a grep limitation: the pattern `dirs::home_dir()` matches inside doc comments. No actual `dirs::home_dir()` calls exist in test files under `crates/bm/tests/`.

`domain-layer-imports.sh` will flag 9 existing `eprintln!` violations:

| Module | File | Lines | What |
|---|---|---|---|
| bridge | `bridge/provisioning.rs` | 81, 183 | Progress/warning during provisioning |
| formation | `formation/start_members.rs` | 167 | Status during member start |
| formation | `formation/local/linux/mod.rs` | 209 | Status during daemon start |
| git | `git/manifest_flow.rs` | 244, 249, 252 | Progress during App installation check |
| profile | `profile/agent.rs` | 151, 159 | Status messages during Minty config init |

Per ADR-0007: replace with `tracing::warn!`/`tracing::info!` or return structured `Result` types to the command layer. Fixing these is the first concrete deliverable after checks are in place.

`no-hardcoded-profiles.sh` will flag 74 existing violations (all in `#[cfg(test)]` blocks):

| Module | File | Count | What |
|---|---|---|---|
| web | `web/files.rs` | 15 | Test fixtures with profile name strings |
| profile | `profile/mod.rs` | 14 | Test calls, function names (`rh_scrum_has_views`, `scrum_compact_has_views`) |
| profile | `profile/agent.rs` | 12 | Test calls, assertion messages (`"scrum profile should have..."`) |
| profile | `profile/extraction.rs` | 11 | Test fixtures, function name (`extract_profile_scrum_compact_...`) |
| config | `config/mod.rs` | 7 | Test fixtures with `profile: "scrum"` |
| web | `web/teams.rs` | 4 | Test fixtures with profile name strings |
| web | `web/members.rs` | 3 | Test fixtures with profile name strings |
| git | `git/manifest_flow.rs` | 3 | Test fixtures with `profile: "scrum"` |
| (standalone) | `team.rs` | 1 | Test fixture with profile name |
| profile | `profile/member.rs` | 1 | Test fixture with profile name |
| formation | `formation/init.rs` | 1 | Test fixture with `profile: "scrum"` |
| bridge | `bridge/manifest.rs` | 1 | Test fixture with `"profile: scrum\n"` |
| agent_tags | `agent_tags/mod.rs` | 1 | Test path string `"profiles/scrum/context.md"` |

Per the `no-hardcoded-profiles` invariant: tests should use dynamic profile discovery (`list_profiles`, `read_manifest`) instead of hardcoded profile name strings. Fixing these is lower priority than the ADR-0007 `eprintln!` violations.

### 3.5 Hat Integration

**`dev_code_reviewer`** gains in hat instructions:
> Before reviewing, run: `bash team/coding-agent/skills/check-runner/run-checks.sh <project>`. If any VIOLATION is reported, reject to `dev:implement` with the VIOLATION/REMEDIATION output as feedback.

**`qe_verifier`** gains:
> As part of verification, run the check runner. Violations block verification.

### 3.6 CI Integration (Deferred)

CI integration is **explicitly deferred** to a follow-up story. The workspace dependency creates an architectural gap that must be resolved first:

- The check runner lives at `team/coding-agent/skills/check-runner/run-checks.sh` (team repo)
- CI runs against the project repo — the `team/` directory is a workspace artifact, not committed to the project repo
- Making `team/` available in CI requires either: (a) a checkout step for the team repo, (b) a git submodule, or (c) relocating the runner and check scripts into the project repo

For this epic, checks run **agent-side only** — triggered by `dev_code_reviewer` and `qe_verifier` hats, which always have the full workspace available. This is sufficient to catch violations before merge. CI integration adds a safety net for direct pushes or manual PRs, but is not required for the core value proposition.

The e2e test harness (`crates/bm/tests/e2e/`, `libtest-mimic`, `--features e2e`) validates runtime behavior; check scripts validate static properties. They complement each other. Exploratory tests remain agent-driven.

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
- **Given** a `// check:ignore` comment is placed on a line with `eprintln!` in a domain module, **when** `domain-layer-imports.sh` runs, **then** that line is excluded from violations.

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| `projects/botminter/invariants/checks/` | New directory + 4 project-specific scripts |
| `team/coding-agent/skills/check-runner/` | New runner script |
| `team/knowledge/check-script-contract.md` | New knowledge doc defining the contract |
| `dev_code_reviewer` hat instructions | Add check-running step before review |
| `qe_verifier` hat instructions | Add check-running step during verification |
| `projects/botminter/CLAUDE.md` | Reference check runner and invariant checks |

**No changes to:** Ralph Orchestrator, `team/invariants/` directory (no profile-generic checks — deferred), existing invariant markdown files, status graph, formation system, bridge system, daemon/web console, existing 11 ADRs, existing test infrastructure.

---

## 6. Security Considerations

Check scripts are read-only file analyzers. They scan code with `grep`/`find` — they do not modify files, make network requests, or alter git state. Scripts are version-controlled in the project repo (`projects/botminter/invariants/checks/`). The runner is version-controlled in the team repo (`team/coding-agent/skills/check-runner/`).

**Attack surface:** A malicious check script could only read files the agent already has access to. The runner does not execute arbitrary user input — it discovers and runs `.sh` files from known directories.

**Crash isolation:** The runner is stateless — each invocation is a single run with no cross-run state. A crashed script (exit 1 without VIOLATION output, or exit >1) is logged as a warning and skipped. The runner does not retry crashed scripts within a run — it reports the crash and continues with the remaining checks. No crash-count tracking across invocations is performed.

**No secret exposure:** Check scripts operate on source code files only. They do not access `.env`, credentials, or runtime secrets.
