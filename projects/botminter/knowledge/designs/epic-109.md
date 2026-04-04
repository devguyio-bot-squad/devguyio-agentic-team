# Design: Application Legibility for Agent Development

**Epic:** #109 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter has four runtime components — CLI (`bm`), agent CLI (`bm-agent`), HTTP daemon (axum, 9 files in `daemon/`), and embedded web console (axum Router, 9 files in `web/`). Agents currently interact only with CLI commands and raw `cargo test` text output. The daemon's REST API (`/api/teams/`, member management, webhook handling), polling mode, and web console are invisible to the agent development loop.

Test output from `cargo test` is unstructured — agents pattern-match against console text to find failures. The e2e test harness (`tests/e2e/`, `libtest-mimic`, `--features e2e`) and 78 inline unit test modules produce raw text.

This epic makes BotMinter's runtime behavior visible to agents through three phases: structured test output, dev-environment bootstrapping, and daemon/API integration testing.

### Harness Pattern

> "We made the app bootable per git worktree, so Codex could launch and drive one instance per change."

Harness wired Chrome DevTools Protocol for DOM snapshots, local observability per worktree (logs via LogQL, metrics via PromQL, traces via TraceQL), and structured test output. Their agents run single tasks for 6+ hours using this infrastructure.

BotMinter's daemon + API + web console is analogous — the runtime exists but agents can't see it. The web console runs behind the `console` Cargo feature flag using `rust-embed` for embedded assets.

### Scope

- Structured test output wrapper (JSON format)
- Dev-boot configuration for daemon + API + web console
- Integration test support for HTTP API validation

### Out of Scope

- Browser automation for the web console (deferred until phases A-C prove useful)
- Chrome DevTools Protocol integration (BotMinter's console is simpler than a full SPA)
- Observability stack (LogQL/PromQL) — overkill for current stage

---

## 2. Architecture

### BotMinter Runtime Components

| Component | Module | Key Types | Agent Interaction Today |
|---|---|---|---|
| CLI (`bm`) | `commands/`, `cli.rs`, `main.rs` | Clap commands | Full — agents run CLI commands |
| Agent CLI (`bm-agent`) | `agent_cli.rs`, `agent_main.rs` | Agent-specific commands | Full — agents use bm-agent directly |
| HTTP Daemon | `daemon/` | `StartLoopRequest`, `StartLoopResponse`, `HealthResponse`, `GitHubEvent` | None — invisible to agents |
| Web Console | `web/` | Axum Router, `/api/teams/`, `/api/teams/{team}/overview` | None — invisible to agents |

The daemon starts via `bm daemon start --team <team>` (or `cargo run -- daemon start`). It exposes REST endpoints for loop management, member management, and GitHub webhook handling. The web module serves team overview, member status, file browsing, and sync endpoints. When built with `--features console`, it includes embedded SPA assets via `rust-embed`.

### Three-Phase Design

```
Phase A: Structured Test Output ──→ All hats benefit immediately
Phase B: Dev-Boot Config         ──→ dev_implementer, qe_verifier boot the app
Phase C: Daemon API Testing      ──→ e2e tests exercise HTTP endpoints
```

---

## 3. Components and Interfaces

### Phase A: Structured Test Output

A wrapper script (profile-level, extracted to `team/coding-agent/skills/`) runs `cargo test` and post-processes output into JSON:

```json
{"test": "formation::local::test_start_members", "status": "FAIL", "duration_ms": 1204, "error": "assertion failed: member.is_healthy()", "file": "crates/bm/src/formation/local/mod.rs", "line": 245}
```

Fields: `test` (full path), `status` (PASS/FAIL/SKIP), `duration_ms`, `error` (on failure), `file`, `line`.

The wrapper supports:
- Unit tests: `cargo test`
- E2e tests: `cargo test --features e2e`
- Integration tests: `cargo test --test <name>`

Implementation: parse `cargo test` output with `--format json` (unstable but available via `CARGO_TERM_VERBOSE=true` or `cargo test -- --format json` on nightly). Fallback: regex parsing of standard output for stable toolchain.

Hats (`qe_investigator`, `dev_implementer`, `qe_verifier`) use the wrapper to navigate directly to failures by file and line.

### Phase B: Dev-Boot Configuration

Projects with a runnable application define boot/teardown in `team/projects/<project>/knowledge/dev-boot.yml`:

```yaml
dev_boot:
  steps:
    - name: "Build"
      command: "cargo build --features console"
    - name: "Start daemon"
      command: "cargo run --features console -- daemon start --team test-team"
      health_check: "curl -sf http://localhost:8080/health"
      teardown: "cargo run --features console -- daemon stop --team test-team"
    - name: "Verify API"
      command: "curl -sf http://localhost:8080/api/teams/"
    - name: "Verify console"
      command: "curl -sf http://localhost:8080/"
  isolation: worktree
```

This file lives in team repo project knowledge — project-specific, consumed by hats via knowledge resolution. Not in `botminter.yml` because dev-boot is a project concern, not a team manifest field.

`dev_implementer` and `qe_verifier` check for `dev-boot.yml`. If present:
1. Build with features
2. Start daemon
3. Wait for health check
4. Run tests and validations
5. Tear down

Each worktree gets its own daemon instance (per ADR-0008 formation abstraction). Port allocation uses the daemon's existing port selection.

### Phase C: Daemon API Testing

The daemon exposes REST endpoints defined in `daemon/api.rs`:
- `StartLoopRequest`/`StartLoopResponse` — loop management
- `StartMembersRequest`/`StopMembersRequest`/`MemberStatusInfo` — member management
- `HealthResponse` — health check
- `GitHubEvent` with `validate_webhook_signature` — webhook handling

The web module (`web/mod.rs`) exposes:
- `GET /api/teams/` — list teams
- `GET /api/teams/{team}/overview` — team overview
- `GET /api/teams/{team}/members` — member list
- `GET/PUT /api/teams/{team}/files/{*path}` — file access
- `POST /api/teams/{team}/sync` — trigger sync

The structured test output wrapper (Phase A) covers integration tests exercising these endpoints. When dev-boot is active (Phase B), `qe_verifier` can validate endpoint responses directly.

---

## 4. Acceptance Criteria

- **Given** tests run during implementation, **when** they complete, **then** structured JSON output is available with test name, status, duration, error, file, and line.
- **Given** a project with `dev-boot.yml`, **when** `dev_implementer` works on a story, **then** the daemon boots, health check passes, and the agent validates API behavior at runtime.
- **Given** an e2e test exercises the daemon API, **when** it completes, **then** structured output includes the endpoint, response status, and failure detail.
- **Given** a daemon boot fails or health check times out, **when** `dev_implementer` proceeds, **then** it runs in degraded mode (unit tests + static checks only) with a warning comment on the issue.
- **Given** the web console is built with `--features console`, **when** dev-boot runs, **then** the console URL is verified accessible.

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| `team/coding-agent/skills/` | New structured test output wrapper script |
| `team/projects/botminter/knowledge/dev-boot.yml` | New dev-boot config |
| `team/knowledge/structured-test-output.md` | New knowledge doc defining JSON format |
| `dev_implementer` hat instructions | Add dev-boot check and structured test usage |
| `qe_verifier` hat instructions | Add dev-boot check and structured test usage |
| `qe_investigator` hat instructions | Use structured test output for failure navigation |
| CLAUDE.md | Reference structured test output, dev-boot |

No changes to: daemon source code, web module source code, e2e test harness, existing test suites.

---

## 6. Security Considerations

Dev-boot starts a local daemon bound to localhost. No external network exposure. Each worktree gets an isolated instance — no shared state between concurrent agent runs. The daemon's webhook signature validation (`validate_webhook_signature` in `daemon/event.rs`) applies regardless of how the daemon is started. Dev-boot config is version-controlled in the team repo — agents cannot modify the boot sequence without a reviewed commit.
