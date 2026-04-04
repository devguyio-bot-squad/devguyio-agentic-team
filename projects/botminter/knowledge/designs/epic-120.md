---
type: design
status: draft
parent: "106"
epic: "120"
revision: 1
created: 2026-04-04
updated: 2026-04-04
author: bob (superman)
depends_on: []
---

# Epic #120: Application Legibility for Agent Development

## 1. Overview

### Problem

BotMinter is a 37,681-line Rust application (112 source files, 16 domain modules, 2 binaries, HTTP daemon, SvelteKit web console) where agents do the majority of development work. Today, the application is legible to humans but opaque to agents in five concrete ways:

**1. No programmatic project discovery.** An agent starting work on BotMinter must parse a 24KB CLAUDE.md to learn what modules exist, what commands to run, and what conventions to follow. There is no tool that produces structured, current-state project metadata. When the codebase evolves (new modules, renamed directories, changed build commands), CLAUDE.md drifts and agents work with stale context.

**2. Test output is human-readable, not machine-parseable.** `cargo test` produces free-text output. `libtest-mimic` (E2E harness) writes pass/fail to stdout with no structured format. Exploratory tests (`crates/bm/tests/exploratory/`) are shell scripts producing ad-hoc output. When a test fails, the agent must parse prose to find the failing test name, file location, and error message. This wastes context window and produces unreliable failure classification.

**3. Error messages lack remediation context.** The codebase uses `anyhow::Result` throughout (80+ `.context()` calls, 60+ `anyhow::anyhow!()` calls). Error strings describe WHAT failed ("No App client_id for member", "Not in a BotMinter workspace") but not WHY or HOW TO FIX IT. `bm-agent` exits with `eprintln!("Error: {e}")` — a single freeform string. Agents cannot classify errors (configuration vs environment vs permission vs transient) or determine the correct remediation without heuristic text matching.

**4. Environment setup is trial-and-error.** A new agent session has no way to verify its development environment before starting work. Required tools (`cargo`, `clippy`, `rustfmt`, `just`, `gh`, `npm`, `node`), environment variables (`TESTS_GH_TOKEN`, `TESTS_GH_ORG`, `GH_TOKEN`), and connectivity (daemon reachable, GitHub API accessible) are discovered by hitting errors during builds or tests. Each missing prerequisite costs a failed attempt and wasted context.

**5. CLAUDE.md has no maintenance convention.** The 24KB CLAUDE.md is a monolithic manual artifact. No convention defines which sections are static vs evolving, who updates what, or how staleness is detected. As the codebase changes, sections become inaccurate — the module list may not match reality, the test commands may have changed, ADR references may be outdated. Agents reading stale CLAUDE.md produce code that violates current conventions.

### Solution

Five features that make BotMinter's application layer legible to agent development:

| # | Feature | What It Produces | Agent Impact |
|---|---------|-----------------|--------------|
| 1 | Agent Tools Expansion (`bm-agent`) | `project describe`, `env check`, `test summary` commands | Agents get structured project context and environment validation in seconds |
| 2 | Structured Error Context | Error categories + remediation hints in `bm-agent` and daemon API | Agents classify errors programmatically and apply the correct fix |
| 3 | Structured Test Output | JSON test results with failure classification | Agents jump to failures without parsing prose |
| 4 | Dev Boot Protocol | Automated environment validation at session start | Agents detect missing prerequisites before starting work |
| 5 | CLAUDE.md Maintenance Convention | Section ownership, staleness detection, auto-generated sections | CLAUDE.md stays current as the codebase evolves |

### Harness Pattern

> "When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it both legible and enforceable for the agent?'"

> "Because the lints are custom, we write the error messages to inject remediation instructions into agent context."

Harness Engineering's layered architecture uses custom linters with agent-readable remediation messages. BotMinter's #114 brings this to invariant enforcement. This epic extends the principle to the APPLICATION itself: every interface an agent touches — project structure, test results, error messages, environment state — should produce structured, actionable output. The agent should never need to parse prose to decide its next action.

### Scope

- `bm-agent` new subcommands: `project describe`, `env check`, `test summary`
- Error type with categories and remediation hints for `bm-agent` errors
- Structured test output recipe (`just test-json`) and exploratory test structured output
- Dev boot script for environment validation
- CLAUDE.md maintenance convention and section ownership model
- Hat instruction updates for `dev_implementer` (dev boot on session start)

### Out of Scope

- Modifying the status graph or adding new statuses
- Refactoring all domain-module error handling to use typed errors (incremental; this design defines the contract and applies it to `bm-agent` first)
- Rewriting CLAUDE.md content (this design defines maintenance conventions, not content rewrites)
- AST-level code analysis or language server integration
- Ralph Orchestrator changes
- Changes to the web console frontend or daemon HTTP API contract (the daemon API is already structured with JSON; this design focuses on the agent CLI)

---

## 2. Architecture

### 2.1 BotMinter Architecture Context

BotMinter is a multi-binary Rust application:
- **CLI** (`bm`) — 22+ subcommands for operators managing agentic teams
- **Agent CLI** (`bm-agent`) — agent-consumed tools binary (ADR-0010). Currently 3 command groups: `inbox` (write/read/peek), `claude` (PostToolUse hook), `loop` (start via daemon)
- **HTTP Daemon** (`daemon/`) — Axum-based background process with JSON API (9 source files). Already produces structured JSON responses with `ok`/`error` envelope.
- **Web Console** (`web/`) — 9 Rust API files + SvelteKit SPA in `console/`

The codebase follows ADR-0006 (directory modules) and ADR-0007 (domain-command layering):
- 16 directory modules under `crates/bm/src/`
- 15 domain modules (everything except `commands/`)
- Command layer: `commands/`, `main.rs`, `cli.rs`, `agent_main.rs`, `agent_cli.rs`

Error handling uses `anyhow::Result` throughout. The daemon API has structured JSON error responses (`ErrorResponse { ok: false, error: String }`). The agent CLI outputs `eprintln!("Error: {e}")` and exits 1.

### 2.2 Feature Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   bm-agent CLI (expanded)                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Existing                  New (this epic)                   │
│  ┌──────────┐             ┌──────────────────┐              │
│  │  inbox    │             │ project describe │ → JSON       │
│  │  claude   │             │ env check        │ → JSON       │
│  │  loop     │             │ test summary     │ → JSON       │
│  └──────────┘             └──────────────────┘              │
│                                                              │
│  Error Output (all commands):                                │
│  ┌──────────────────────────────────────────────────────────┐│
│  │ {"error": "...", "category": "...", "remediation": "..."}││
│  └──────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Test Infrastructure                        │
├─────────────────────────────────────────────────────────────┤
│  just test-json ──► cargo test --format json (unstable)      │
│                 └─► fallback: regex post-processor on stable │
│                                                              │
│  Exploratory tests ──► RESULT|phase|scenario|PASS/FAIL|msg  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Dev Boot Protocol                         │
├─────────────────────────────────────────────────────────────┤
│  bm-agent env check  ──► JSON readiness report              │
│                                                              │
│  Checks: toolchain, tools, env vars, connectivity, build    │
│  Invoked by: dev_implementer hat (first step of impl)       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                 CLAUDE.md Convention                          │
├─────────────────────────────────────────────────────────────┤
│  Sections: static (owner: manual) │ evolving (owner: hat)   │
│  Staleness: gardening scanner checks section timestamps     │
│  Auto-gen: bm-agent project describe piped to section       │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Design Principles

1. **Agent CLI is the legibility surface.** All agent-facing structured output goes through `bm-agent`. Operators use `bm`. This maintains ADR-0010's separation.

2. **JSON everywhere for agents.** Every `bm-agent` command that produces output uses JSON. Text output (existing `bm-agent inbox peek`) is preserved for backward compatibility; new commands default to JSON.

3. **Errors are first-class data.** Agent-facing error output is structured JSON with category, message, and remediation. The agent can programmatically decide whether to retry, fix configuration, or escalate.

4. **Incremental adoption.** Structured errors are applied to `bm-agent` first. Domain module error refactoring happens incrementally in future stories. The error categorization model is defined once and used everywhere.

---

## 3. Components and Interfaces

### 3.1 Feature 1: Agent Tools Expansion

Three new subcommands added to `bm-agent`:

#### `bm-agent project describe`

Produces a structured JSON snapshot of the project for agent context injection.

**Output schema:**

```json
{
  "name": "botminter",
  "version": "0.2.0-pre-alpha",
  "language": "rust",
  "modules": [
    {"name": "bridge", "path": "crates/bm/src/bridge", "files": 6, "lines": 4200},
    {"name": "daemon", "path": "crates/bm/src/daemon", "files": 9, "lines": 2800}
  ],
  "binaries": [
    {"name": "bm", "entry": "crates/bm/src/main.rs"},
    {"name": "bm-agent", "entry": "crates/bm/src/agent_main.rs"}
  ],
  "test_tiers": [
    {"name": "unit", "command": "just unit", "location": "inline (#[cfg(test)])"},
    {"name": "integration", "command": "just conformance", "location": "crates/bm/tests/"},
    {"name": "e2e", "command": "just e2e", "location": "crates/bm/tests/e2e/"},
    {"name": "exploratory", "command": "just exploratory-test", "location": "crates/bm/tests/exploratory/"}
  ],
  "build_commands": {
    "build": "just build",
    "test": "just test",
    "lint": "just clippy",
    "format": "cargo fmt"
  },
  "adrs": ["0001-adr-process", "0002-bridge-abstraction", "..."],
  "invariants": ["cli-idempotency", "e2e-scenario-coverage", "..."],
  "features": {
    "console": "Web console (rust-embed SPA)",
    "e2e": "E2E test gate"
  }
}
```

**Implementation:** Reads `Cargo.toml` for version/features, walks `crates/bm/src/` for module discovery, reads `Justfile` for build commands, lists `.planning/adrs/` and `invariants/` directories. All data is derived from the current filesystem state — no caching, no stale data.

**Working directory:** Must be run from the project root (same as `bm-agent inbox`).

#### `bm-agent env check`

Validates development environment readiness and produces a structured JSON report.

**Output schema:**

```json
{
  "ready": false,
  "checks": [
    {"name": "rust_toolchain", "status": "pass", "detail": "1.82.0 (stable)"},
    {"name": "clippy", "status": "pass", "detail": "0.1.82"},
    {"name": "rustfmt", "status": "pass", "detail": "1.7.1"},
    {"name": "just", "status": "pass", "detail": "1.36.0"},
    {"name": "gh_cli", "status": "pass", "detail": "2.62.0"},
    {"name": "gh_token", "status": "fail", "detail": "TESTS_GH_TOKEN not set", "remediation": "export TESTS_GH_TOKEN=<token> — needed for E2E tests"},
    {"name": "node", "status": "pass", "detail": "v22.0.0"},
    {"name": "npm", "status": "pass", "detail": "10.9.0"},
    {"name": "cargo_build", "status": "pass", "detail": "compiled in 2.3s"},
    {"name": "daemon_reachable", "status": "skip", "detail": "daemon not running (OK for development)"}
  ],
  "missing_tools": ["cargo-audit"],
  "summary": "9/10 checks passed. 1 failed: TESTS_GH_TOKEN not set."
}
```

**Checks performed:**

| Check | How | Required? |
|-------|-----|-----------|
| `rust_toolchain` | `rustc --version` | Yes |
| `clippy` | `cargo clippy --version` | Yes |
| `rustfmt` | `rustfmt --version` | Yes |
| `just` | `just --version` | Yes |
| `gh_cli` | `gh --version` | Yes |
| `gh_token` | Check `$TESTS_GH_TOKEN` env var | For E2E tests |
| `gh_org` | Check `$TESTS_GH_ORG` env var | For E2E tests |
| `node` | `node --version` | For console dev |
| `npm` | `npm --version` | For console dev |
| `cargo_build` | `cargo check -p bm --features console` | Yes |
| `daemon_reachable` | HTTP GET to daemon health endpoint | Optional |
| `cargo_audit` | `cargo audit --version` | Optional (for #118 gardening) |

**Exit codes:** 0 = all required checks pass, 1 = one or more required checks fail.

#### `bm-agent test summary`

Wraps test execution and produces a structured JSON summary of results.

**Arguments:** `bm-agent test summary [--tier unit|e2e|all] [--json]`

**Output schema:**

```json
{
  "tier": "unit",
  "command": "just unit",
  "exit_code": 1,
  "duration_secs": 12.4,
  "total": 145,
  "passed": 143,
  "failed": 2,
  "ignored": 5,
  "failures": [
    {
      "test": "daemon::api::tests::health_response_serialize",
      "file": "crates/bm/src/daemon/api.rs",
      "line": 879,
      "message": "assertion failed: `(left == right)`\n  left: `\"0.2.0\"`,\n right: `\"0.1.0\"`",
      "category": "assertion_failure"
    }
  ]
}
```

**Implementation:** Runs `cargo test` with `--format json` on nightly, or parses the stable text output with regex patterns (Rust test output format is well-defined: `test <name> ... ok/FAILED`, summary line `test result: <status>. <pass> passed; <fail> failed; <ignored> ignored`). Failure details are extracted from the `---- <test_name> stdout ----` blocks.

**Failure categories:**
- `assertion_failure` — `assert!` / `assert_eq!` / `assert_ne!`
- `panic` — `panic!()` or unwrap failure
- `compilation_error` — `cargo test` fails at compile stage (exit 101)
- `timeout` — test exceeded time limit
- `infrastructure` — test environment issue (network, missing fixture)

### 3.2 Feature 2: Structured Error Context

#### Error Category Type

Define error categories for agent-facing errors:

```rust
/// Error categories for agent-consumable error output.
/// Agents use the category to decide their next action.
pub enum ErrorCategory {
    /// Configuration file missing, malformed, or has invalid values.
    /// Remediation: check/fix the config file.
    Configuration,
    /// Required tool, env var, or system dependency missing.
    /// Remediation: install the tool or set the variable.
    Environment,
    /// Network request failed (GitHub API, daemon HTTP, etc).
    /// Remediation: retry, check connectivity, verify token.
    Network,
    /// Git operation failed (clone, push, fetch, submodule).
    /// Remediation: check remote, credentials, branch state.
    Git,
    /// Runtime state inconsistency (stale PID, missing workspace).
    /// Remediation: re-sync state or restart the affected component.
    State,
    /// Permission denied (filesystem, keyring, GitHub scope).
    /// Remediation: check file permissions, token scopes.
    Permission,
    /// Internal bug — should not happen in normal operation.
    /// Remediation: report the issue.
    Internal,
}
```

#### Structured Error Output

`bm-agent` error output changes from:

```
Error: No App client_id for member
```

To:

```json
{"error": "No App client_id for member 'superman'", "category": "state", "remediation": "Run 'bm teams sync' to provision App credentials, or check that the member's GitHub App is installed."}
```

**Implementation approach:**

1. Define `AgentError` struct with `message`, `category`, and `remediation` fields.
2. `agent_main.rs` catches `anyhow::Error` at the top level and classifies it by inspecting the error chain for known patterns:
   - "not found" / "No such file" → `Configuration`
   - "not set" / "env var" → `Environment`
   - "connect" / "request" / "HTTP" / "API" → `Network`
   - "git" / "clone" / "push" / "remote" → `Git`
   - "PID" / "state" / "workspace" / "alive" → `State`
   - "permission" / "denied" / "scope" → `Permission`
   - Default → `Internal`

3. Known error sites in `bm-agent` gain explicit remediation messages:

| Error | Category | Remediation |
|-------|----------|-------------|
| "Not in a BotMinter workspace" | `Configuration` | "Run this command from a BotMinter member workspace (directory containing .botminter.workspace)" |
| "No App client_id for member" | `State` | "Run 'bm teams sync' to provision App credentials" |
| "BM_TEAM_NAME not set" | `Environment` | "Set BM_TEAM_NAME or run from a started member workspace" |
| "Failed to start loop" | `State` | "Check daemon is running ('bm status') and member exists" |
| "No members found in team" | `Configuration` | "Run 'bm hire <role>' to add a member to the team" |

This is incremental — `bm-agent` commands get explicit remediation first. Domain module errors fall back to category-by-pattern classification. Future stories can add explicit remediation to domain errors.

### 3.3 Feature 3: Structured Test Output

#### `just test-json` Recipe

New Justfile recipe that produces structured JSON test results:

```just
# Run tests with JSON output for agent consumption
test-json tier="all":
    #!/usr/bin/env bash
    set -euo pipefail
    bm-agent test summary --tier {{tier}} --json
```

This delegates to `bm-agent test summary` (Feature 1) so there's a single implementation.

#### Exploratory Test Structured Output

The exploratory test scripts (`crates/bm/tests/exploratory/phases/`) currently produce free-form output. Each phase script gains structured result lines alongside existing output:

```
RESULT|phase-b|bootstrap-init|PASS|team created successfully
RESULT|phase-b|bootstrap-hire|PASS|member hired as superman
RESULT|phase-c|workspace-sync|FAIL|submodule clone failed: timeout after 60s
```

Format: `RESULT|<phase>|<scenario>|PASS|FAIL|SKIP|<message>`

The existing `lib.sh` helper gains a `report_result()` function:

```bash
report_result() {
    local phase="$1" scenario="$2" status="$3" message="$4"
    echo "RESULT|${phase}|${scenario}|${status}|${message}"
}
```

`REPORT.md` generation (already exists in `crates/bm/tests/exploratory/`) is unchanged — it continues to produce human-readable output. The `RESULT` lines are a parallel machine-readable channel.

### 3.4 Feature 4: Dev Boot Protocol

#### `bm-agent env check` as Dev Boot

The `bm-agent env check` command (Feature 1) IS the dev boot protocol. No separate script needed — the command validates everything an agent needs before starting development.

#### Hat Integration

The `dev_implementer` hat gains a dev-boot step as the first action when starting implementation:

> Before writing code, run: `bm-agent env check`. If any required check fails, address the failure before proceeding. If the check produces remediation instructions, follow them.

This front-loads environment validation. An agent discovers it's missing `cargo-audit` or `TESTS_GH_TOKEN` BEFORE writing code, not after a test failure 20 minutes into the session.

The `qe_test_designer` hat also gains the check:

> Before writing test plans, run: `bm-agent env check --tier tests`. Verify that the test infrastructure (E2E harness, exploratory SSH access) is available.

#### Dev Boot Configuration

Project-specific dev-boot configuration lives at `projects/botminter/knowledge/dev-boot.yml`:

```yaml
# Dev boot configuration for botminter
required_tools:
  - name: rustc
    check: "rustc --version"
    install_hint: "Install via rustup: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  - name: clippy
    check: "cargo clippy --version"
    install_hint: "rustup component add clippy"
  - name: rustfmt
    check: "rustfmt --version"
    install_hint: "rustup component add rustfmt"
  - name: just
    check: "just --version"
    install_hint: "cargo install just"
  - name: gh
    check: "gh --version"
    install_hint: "See https://cli.github.com/"

optional_tools:
  - name: cargo-audit
    check: "cargo audit --version"
    install_hint: "cargo install cargo-audit"
    reason: "Needed for dependency security scanning (#118)"
  - name: cargo-machete
    check: "cargo machete --version"
    install_hint: "cargo install cargo-machete"
    reason: "Needed for unused dependency detection (#118)"
  - name: node
    check: "node --version"
    install_hint: "Install Node.js 20+ via nvm or system package manager"
    reason: "Needed for console/ SvelteKit development"

required_env_vars:
  - name: TESTS_GH_TOKEN
    reason: "GitHub token for E2E tests"
  - name: TESTS_GH_ORG
    reason: "GitHub org for E2E test repos"

build_check: "cargo check -p bm --features console"
```

`bm-agent env check` reads this file to know what to validate. This makes dev-boot project-specific — hypershift would have a different `dev-boot.yml` checking Go toolchain, `golangci-lint`, etc.

### 3.5 Feature 5: CLAUDE.md Maintenance Convention

#### Section Classification

The project CLAUDE.md is classified into static and evolving sections:

| Section | Type | Owner | Update Trigger |
|---------|------|-------|----------------|
| "CRITICAL — E2E AND EXPLORATORY TESTS" | Static | Operator | Only on policy change |
| "Project Overview" | Static | Operator | Only on major milestones |
| "Commands" (bm CLI, bm-agent CLI) | Evolving | `dev_implementer` | When adding/changing CLI commands |
| "Development (Justfile)" | Evolving | `dev_implementer` | When adding/changing Justfile recipes |
| "Architecture" | Evolving | `arch_designer` | When structural changes occur |
| "Testing" sections | Evolving | `qe_test_designer` | When test infrastructure changes |
| "Naming Conventions" | Static | Operator | Only on convention change |
| "ADR References" | Evolving | `arch_designer` | When ADRs are added |

#### Ownership Convention

A knowledge document at `projects/botminter/knowledge/claude-md-convention.md` defines:

1. **Section ownership table** — which hat is responsible for each section.
2. **Update rule** — "If you modify code that changes the accuracy of a CLAUDE.md section you own, update the section in the same PR."
3. **No aspirational content** — CLAUDE.md describes the codebase AS IT IS, not as it should be. Planned features go in design docs, not CLAUDE.md.

#### Staleness Detection

If #118 (gardening) is deployed, a gardening scanner can check CLAUDE.md staleness:

- Compare CLAUDE.md's `## Commands` section against `bm --help` output. Flag if a documented command doesn't exist or an undocumented command does.
- Compare module list against `crates/bm/src/` directory listing.
- This scanner is low-priority (informational, not blocking) and emits `FINDING|documentation|low|CLAUDE.md|Module list outdated: found 17 modules, CLAUDE.md lists 16|false`.

If #118 is not deployed, staleness detection relies on the ownership convention (hat checks its sections during its work).

#### Auto-Generated Sections

`bm-agent project describe` output can be used to generate or validate CLAUDE.md sections. This is not automated in this design — it's a tool available to hats. Example workflow:

1. `arch_designer` finishes a design that adds a new module.
2. Before committing, runs `bm-agent project describe` and checks whether CLAUDE.md's module list matches.
3. If not, updates the section.

Fully automated CLAUDE.md regeneration is explicitly deferred — the risk of overwriting operator-authored nuance (like the "CRITICAL" section) outweighs the convenience.

---

## 4. Data Models

### 4.1 Agent Error Output

```rust
/// Structured error output for agent consumption.
#[derive(Debug, Serialize)]
pub struct AgentError {
    /// Human-readable error message.
    pub error: String,
    /// Error category for programmatic classification.
    pub category: String,
    /// Suggested fix for the agent to attempt.
    pub remediation: String,
}
```

Output to stderr as JSON when `bm-agent` encounters an error:

```json
{"error": "TESTS_GH_TOKEN not set", "category": "environment", "remediation": "export TESTS_GH_TOKEN=<github-token> — needed for E2E tests. Generate at https://github.com/settings/tokens with 'repo' scope."}
```

### 4.2 Project Description

```rust
#[derive(Debug, Serialize)]
pub struct ProjectDescription {
    pub name: String,
    pub version: String,
    pub language: String,
    pub modules: Vec<ModuleInfo>,
    pub binaries: Vec<BinaryInfo>,
    pub test_tiers: Vec<TestTierInfo>,
    pub build_commands: HashMap<String, String>,
    pub adrs: Vec<String>,
    pub invariants: Vec<String>,
    pub features: HashMap<String, String>,
}

#[derive(Debug, Serialize)]
pub struct ModuleInfo {
    pub name: String,
    pub path: String,
    pub files: usize,
    pub lines: usize,
}
```

### 4.3 Environment Check Report

```rust
#[derive(Debug, Serialize)]
pub struct EnvCheckReport {
    pub ready: bool,
    pub checks: Vec<CheckResult>,
    pub missing_tools: Vec<String>,
    pub summary: String,
}

#[derive(Debug, Serialize)]
pub struct CheckResult {
    pub name: String,
    pub status: String,  // "pass", "fail", "skip"
    pub detail: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub remediation: Option<String>,
}
```

### 4.4 Test Summary

```rust
#[derive(Debug, Serialize)]
pub struct TestSummary {
    pub tier: String,
    pub command: String,
    pub exit_code: i32,
    pub duration_secs: f64,
    pub total: usize,
    pub passed: usize,
    pub failed: usize,
    pub ignored: usize,
    pub failures: Vec<TestFailure>,
}

#[derive(Debug, Serialize)]
pub struct TestFailure {
    pub test: String,
    pub file: Option<String>,
    pub line: Option<usize>,
    pub message: String,
    pub category: String,
}
```

### 4.5 Dev Boot Configuration

```yaml
# projects/<project>/knowledge/dev-boot.yml
required_tools:
  - name: string
    check: string      # shell command to verify presence
    install_hint: string  # how to install

optional_tools:
  - name: string
    check: string
    install_hint: string
    reason: string      # why this tool is useful

required_env_vars:
  - name: string
    reason: string

build_check: string     # command to verify project builds
```

---

## 5. Error Handling

| Scenario | Behavior |
|----------|----------|
| `bm-agent project describe` run outside project root | Structured error: `{"error": "Not in a BotMinter project (no Cargo.toml found)", "category": "configuration", "remediation": "Run from the project root directory (e.g., projects/botminter/)"}` |
| `bm-agent env check` with missing dev-boot.yml | Falls back to hardcoded defaults (Rust toolchain, clippy, rustfmt, just, gh). Logs warning: "No dev-boot.yml found, using defaults." |
| `bm-agent test summary` with compilation failure | Reports `exit_code: 101`, `failures: [{"category": "compilation_error", ...}]`. No pass/fail counts (compilation prevented test execution). |
| Test output parsing fails (unexpected format) | Returns raw output in a `raw_output` field alongside empty structured fields. Agent can still read the output. |
| `dev-boot.yml` has invalid YAML | Structured error with remediation: "Fix YAML syntax in dev-boot.yml at line N". Falls back to hardcoded defaults. |
| `bm-agent env check` tool command hangs | 10-second timeout per check. Status: `fail`, detail: "timed out after 10s". |
| Exploratory test `report_result` called with wrong format | Validation in `lib.sh`: status must be PASS, FAIL, or SKIP. Wrong values produce a warning line and fall through. |

---

## 6. Acceptance Criteria

- **Given** an agent starts work on the BotMinter project, **when** it runs `bm-agent project describe`, **then** it receives valid JSON listing all 16 domain modules with correct names, paths, and file counts matching the current filesystem state.

- **Given** the BotMinter project has 4 test tiers (unit, integration, e2e, exploratory), **when** `bm-agent project describe` is run, **then** the `test_tiers` array contains all 4 with their `just` commands and file locations.

- **Given** `TESTS_GH_TOKEN` is not set in the environment, **when** `bm-agent env check` is run, **then** the output JSON contains a check with `"status": "fail"` and a remediation string explaining how to set the variable.

- **Given** all required tools are installed and env vars are set, **when** `bm-agent env check` is run, **then** `"ready": true` and exit code 0.

- **Given** a unit test fails with an assertion error, **when** `bm-agent test summary --tier unit` is run, **then** the output JSON contains the failure with `"category": "assertion_failure"`, the test name, and the assertion message.

- **Given** `cargo test` fails at compilation, **when** `bm-agent test summary` is run, **then** `exit_code` is 101 and the failure category is `"compilation_error"` with the compiler error message.

- **Given** `bm-agent inbox read` encounters "Not in a BotMinter workspace", **when** the error is output, **then** it is JSON with `"category": "configuration"` and `"remediation"` containing the fix.

- **Given** the `dev_implementer` hat starts work on a story, **when** it runs `bm-agent env check`, **then** it detects any missing prerequisites before writing code.

- **Given** an exploratory test scenario passes, **when** the phase script executes, **then** it outputs `RESULT|<phase>|<scenario>|PASS|<message>` alongside its existing human-readable output.

- **Given** a new CLI command is added to `bm`, **when** `dev_implementer` commits the change, **then** the CLAUDE.md "Commands" section is updated in the same PR (enforced by ownership convention, not automated).

---

## 7. Impact on Existing System

### New Files (Project Repo — `projects/botminter/`)

| File | Purpose |
|------|---------|
| `crates/bm/src/agent_cli.rs` | Extended with `Project`, `Env`, `Test` subcommands |
| `crates/bm/src/agent_main.rs` | Extended with handlers for new subcommands |
| `crates/bm/src/legibility.rs` | New module: `ProjectDescription`, `EnvCheckReport`, `TestSummary` types and logic |
| `knowledge/dev-boot.yml` | Dev boot configuration |
| `knowledge/claude-md-convention.md` | CLAUDE.md maintenance convention |
| `crates/bm/tests/exploratory/lib.sh` | Extended with `report_result()` function |

### Modified Files (Project Repo)

| File | Change |
|------|--------|
| `crates/bm/src/agent_cli.rs` | Add `Project`, `Env`, `Test` command enums |
| `crates/bm/src/agent_main.rs` | Add handlers, structured error output |
| `Justfile` | Add `test-json` recipe |
| `crates/bm/tests/exploratory/phases/*.sh` | Add `report_result` calls alongside existing output |

### Modified Files (Team Repo)

| File | Change |
|------|--------|
| `dev_implementer` hat instructions | Add dev-boot step (run `bm-agent env check` first) |
| `qe_test_designer` hat instructions | Add env check for test infrastructure |

### No Changes To

- Ralph Orchestrator codebase
- Daemon HTTP API contract (already structured)
- Web console frontend
- Existing `bm` CLI commands or output
- Status graph or review workflow
- Existing invariants or ADRs
- Bridge, formation, git, or workspace modules (internal implementation)
- Existing test code (only exploratory test shell scripts gain `report_result` calls)

### Interaction with Other Sub-Epics

| Sub-Epic | Interaction |
|----------|-------------|
| #114 (Invariant Checks) | `bm-agent env check` can verify check runner prerequisites. Independent — works without #114. |
| #116 (Plans) | Plan artifacts could reference `bm-agent project describe` output for grounding. Independent. |
| #117 (Metrics) | Test summary output could feed into metrics collection. Independent. |
| #118 (Gardening) | CLAUDE.md staleness scanner is a gardening scanner. Degrades gracefully — works without #118. Dev-boot config lists gardening tools as optional. |
| #119 (Autonomy) | Structured error output makes auto-advance risk assessment more reliable (errors are classifiable). Independent. |

---

## 8. Security Considerations

### Agent CLI Tool Safety

`bm-agent project describe` is read-only — it walks directories and reads `Cargo.toml`. No file modifications, no network requests, no shell execution beyond `wc -l` for line counts.

`bm-agent env check` executes tool version commands (`rustc --version`, `gh --version`) with no arguments beyond `--version`. It does not pass user input to shell commands. The `cargo check` build verification uses hardcoded arguments, not user-supplied input.

`bm-agent test summary` delegates to `just test` or `cargo test` with hardcoded arguments. No user-controlled input reaches command construction.

### Error Output and Information Leakage

Structured error output includes file paths, tool versions, and environment variable names (not values). `TESTS_GH_TOKEN` appears as a variable name in remediation messages, never its value. Error messages reference the workspace path, which is an internal detail but not sensitive.

### Dev Boot Configuration

`dev-boot.yml` contains shell commands in the `check` field (e.g., `rustc --version`). These commands are executed by `bm-agent env check`. The file is version-controlled in the project repo — modifications go through the normal PR/review workflow. An attacker with write access to `dev-boot.yml` could inject arbitrary shell commands. This is the same trust model as `Justfile`, `Makefile`, and CI workflow files — all of which execute arbitrary commands. The mitigation is repository access control.

### No New Secrets

No new credentials, tokens, or secrets are introduced. All tools use existing authentication (`GH_TOKEN`, system keyring). `bm-agent env check` validates that required env vars are SET, not their values.
