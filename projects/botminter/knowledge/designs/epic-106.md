# Design: Transition BotMinter to Fully Agentic SDLC

**Epic:** #106
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's scrum-compact profile ships a complete agentic SDLC: 18 specialized hats, board-driven dispatch across a 34-status workflow graph, a four-level knowledge hierarchy, and rejection loops at every review gate. The machinery exists. The problem is that it runs on trust.

Invariants are prose markdown that instruct agents what to do — but nothing mechanically prevents violations. ADR-0007 establishes domain-command layering: domain modules must not use `println!` or reference CLI libraries. Today the codebase is clean — `println!` calls exist only in the command layer where they belong, and `clap` imports are confined to `main.rs`, `cli.rs`, and `commands/`. But nothing *enforces* this. If a developer (human or agent) adds a `println!` to `crates/bm/src/formation/mod.rs` tomorrow, the `dev_code_reviewer` hat has no tool to catch it. The hat reads the prose invariant, applies judgment, and hopes for the best. Sometimes it catches violations. Sometimes it doesn't.

The same gap applies to other mechanically-checkable rules: `test-path-isolation` (tests must use temp directories for `$HOME` — a grep for `home_dir()` outside test setup would catch violations, but no grep runs), `no-hardcoded-profiles` (no hardcoded profile/role names in code — also greppable, also unchecked), and `file-size-limit` per ADR-0006 (a `wc -l` check, also not automated).

This matters because the enforcement gap compounds across the pipeline. Design reviews that should interrogate content instead check a process list. Code reviews that should validate architectural rules instead trust that the implementer read the ADRs. Verification that should confirm structured test output instead parses raw console text by pattern-matching.

OpenAI's Harness Engineering team built a production product — ~1M lines of code, five months, three engineers, zero manually-written code. The core lesson from their experience is not about scale or speed. It's about where engineering effort goes:

> *"When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it both legible and enforceable for the agent?'"*

Their engineers stopped writing code and started building environments where agents produce correct code by construction. Custom linters catch architecture violations with error messages written *for agents*, including remediation instructions. A structured knowledge base replaces the monolithic instruction file. Golden principles are encoded once and enforced on every line of code, automatically. Quality is maintained by a garbage-collection process that detects and fixes drift daily, not by humans spending Fridays cleaning up.

This design proposes six features that close the gap between BotMinter's existing process structure and mechanical enforcement. Each feature is a scrum-compact profile enhancement. No changes to the Ralph Orchestrator product (ralph.yml schema, event loop, hat dispatch engine). Three features modify profile-level orchestration artifacts — board-scanner skill instructions, hat definitions, and the `botminter.yml` manifest schema. Section 2.3 maps each change to its product layer.

### Scope

All changes are delivered as profile enhancements (invariant checks, hat definitions, knowledge conventions, directory templates, manifest schema additions) with supporting CLI changes for new manifest fields. Every feature is additive or opt-in. Default behavior is preserved.

This design does not modify the Ralph Orchestrator product, the formation system, or the bridge system. It does not create a new profile. It does not change the status graph or add new GitHub Projects statuses.

Three features do modify profile-level orchestration artifacts:
- **Feature 3 (Garbage Collection)** adds a `gardener.scan` event and an `arch_gardener` hat to the board-scanner dispatch table and role definition — a new hat trigger and scheduling mechanism within the profile's scanner skill.
- **Feature 5 (Graduated Autonomy)** changes the `po_reviewer` hat's behavior based on a runtime config value read from `botminter.yml`.
- **Feature 6 (Metrics)** adds a JSONL write step to the board-scanner skill's transition logging.

These are profile-level changes (hat definitions, skill instructions, manifest schema), not changes to Ralph's core engine.

---

## 2. Architecture

### 2.1 Mapping Harness Techniques to BotMinter

Harness's techniques evolved over five months of building with agents. Some of their patterns are structural matches for what BotMinter already does. Others expose genuine gaps.

| Harness Technique | What BotMinter Has | What's Missing |
|---|---|---|
| Agent specialization — different agents for different tasks | 18 hats: PO, architect, dev, QE, SRE, content writer, lead, with distinct instructions and backpressure rules | None. Structural match. |
| Agent-to-agent review chain ("Ralph Wiggum Loop") | `lead_reviewer` → `dev_code_reviewer` → `qe_verifier` pipeline | Reviews apply process checklists, not adversarial technical interrogation. No inline PR comments. |
| AGENTS.md as table of contents — short map, not encyclopedia | CLAUDE.md → `knowledge/` hierarchy → hat knowledge. Progressive disclosure by specificity. | Match in structure. Knowledge isn't always *consulted* effectively, but the mechanism works. |
| Structured `docs/` as system of record — indexed, versioned, cross-linked | Knowledge hierarchy (team, project, member, hat). Design docs in project knowledge. | Planning artifacts fragmented across four methodology phases. No execution plans. No tech-debt tracker. |
| Custom linters with agent-readable error messages | 11 prose invariants in the BotMinter project repo (`projects/botminter/invariants/`). 10 ADRs with accepted conventions. 2 profile-generic invariants extracted to `team/invariants/`. | **Zero mechanical enforcement.** No check runs. No structured error output. This is the biggest gap. |
| Per-worktree app boot + Chrome DevTools Protocol for UI validation | Formation abstraction (ADR-0008) handles deployment lifecycle. Local and K8s formations exist. | No per-worktree boot for agent use. No structured test output. BotMinter is a CLI, not a web app — Chrome DevTools doesn't apply. Structured test output and formation-aligned dev-boot are the right adaptations. |
| Golden principles + doc-gardening agent — automated entropy management | Nothing. | No quality scoring, no stale-doc detection, no automated cleanup. |
| Plans as first-class artifacts — active, completed, tech-debt, all versioned | Design docs exist. Story breakdowns exist in issue comments. | No execution plans. No progress tracking as living documents. |
| Graduated autonomy — agents merge own PRs, humans optional | Three fixed human gates: design-review, plan-review, accept. | No progression path. No way to reduce gates as trust is established. |
| Transition logging and cycle-time metrics | `poll-log.txt` audit log. | No structured metrics. No analytics. Cannot answer "what's the rejection rate at code review?" |

### 2.2 The Enforcement Gap

This is the deepest problem and the one Harness solved first.

BotMinter has 11 project-specific invariants (in the project repo at `projects/botminter/invariants/`) and 2 profile-generic invariants (extracted to `team/invariants/`). Three project invariants illustrate what "prose-only enforcement" means in practice:

**`test-path-isolation`** requires that tests set `$HOME` to a temporary directory, never using the real user's home. A check script could grep for `dirs::home_dir()` or `env::home_dir()` outside of test setup code and flag violations. No such script exists. A violation would pass code review undetected because the reviewer hat is applying judgment, not running a tool.

**`no-hardcoded-profiles`** requires that code and tests never hardcode profile names, role names, or status values. A check script could grep for string literals matching known profile/role/status names in non-test source files. No such script exists.

**ADR-0007 (domain-command layering)** requires domain modules to not import CLI libraries. The codebase is currently clean — `clap` imports are confined to `main.rs`, `cli.rs`, `agent_main.rs`, `agent_cli.rs`, and `commands/`. But compliance is accidental, not enforced. A check script could scan import statements in domain module directories (formation/, bridge/, profile/, config/, workspace/, topology/, state/, session/) and flag any `clap` or `println!` usage. No such script exists.

Harness built custom linters specifically because the error messages could be written *for agents*:

> *"Because the lints are custom, we write the error messages to inject remediation instructions into agent context."*

The error message isn't "check failed" — it's structured data: what rule was violated, where, and exactly what to do about it. This is the multiplier: once encoded, it applies everywhere, every time, without judgment variance.

### 2.3 Where Changes Land

Every change in this design maps to a specific BotMinter product layer. The workspace model places the team repo at `team/` and project repos at `projects/<project>/` relative to the agent's working directory (the workspace root).

| Change | Product Layer | Location (relative to workspace root) |
|---|---|---|
| Profile-generic check scripts | Profile: invariant checks (extracted to team repo) | `team/invariants/checks/` |
| Project-specific check scripts | Project repo: invariant checks | `projects/<project>/invariants/checks/` |
| Check runner script | Profile: skill | `team/coding-agent/skills/check-runner/run-checks.sh` |
| Check script contract doc | Profile: knowledge | `team/knowledge/check-script-contract.md` |
| Gardener hat definition | Profile: role definition (in ralph.yml hats section) | `ralph.yml` hats entry + board-scanner dispatch table |
| Reviewer hat updates (check-running) | Profile: hat instructions | `ralph.yml` hat instructions for `dev_code_reviewer`, `qe_verifier` |
| Golden principles config | Project repo: invariants | `projects/<project>/invariants/golden-principles.yml` |
| Plan directory template | Team repo: project plans | `team/projects/<project>/plans/` |
| Structured test output convention | Profile: knowledge | `team/knowledge/structured-test-output.md` |
| Dev-boot configuration | Team repo: project knowledge | `team/projects/<project>/knowledge/dev-boot.yml` |
| Autonomy manifest field | Manifest schema in team repo | `team/botminter.yml` (`autonomy` field) |
| Autonomy CLI parsing | CLI source | `crates/bm/src/profile/manifest.rs` (`ProfileManifest` struct) |
| Transition JSONL logging | Profile: skill instructions | Board-scanner skill instructions (additive line) |
| Metrics JSONL file | Workspace artifact | `metrics/transitions.jsonl` (workspace root) |

---

## 3. Components and Interfaces

### 3.1 Feature 1: Executable Invariant Checks

#### Problem

The `dev_code_reviewer` hat is instructed to "verify compliance with project invariants." It reads the prose files and attempts to check them. Without tooling, the hat applies inconsistent judgment. Some violations are caught. Others aren't. The outcome depends on what the agent notices, not on what the rules require.

Harness's insight: encode rules as executable checks with structured, agent-readable output. The check's error message becomes the agent's remediation instruction.

#### Design

**Check script contract.** Each check is a shell script. Interface:

- **Working directory:** The check runner invokes each script with `cwd` set to the project repository root (`projects/<project>/` relative to the workspace root). All relative paths in scripts resolve against the project repo. For example, a script grepping `crates/bm/src/` works because `cwd` is `projects/botminter/`.
- **Exit codes:** Exit 0 = pass. Exit 1 with VIOLATION output on stdout = violation found. Exit 1 without VIOLATION output, or exit > 1 = script crash (logged as warning, does not block review).
- **Output format on violation (exit 1):**

```
VIOLATION: Domain module crates/bm/src/formation/mod.rs imports clap::Args (line 14)
RULE: ADR-0007 domain-command layering — domain modules must not reference CLI libraries
REMEDIATION: Move the CLI argument struct to the command layer. The domain module should accept typed parameters, not parse arguments.
REFERENCE: .planning/adrs/0007-domain-command-layering.md
```

The `REMEDIATION` line is the key — it gives the agent its next action. The `REFERENCE` line points to the governing rule for context. This follows ADR-0002's design principle: structured output from shell scripts, not arbitrary text.

**Two check script scopes.** Check scripts live in two locations, reflecting BotMinter's invariant hierarchy:

| Scope | Location (from workspace root) | Contains | Example |
|---|---|---|---|
| Profile-generic | `team/invariants/checks/` | Checks applicable to any project using scrum-compact | `file-size-limit.sh` (ADR-0006), `test-path-isolation.sh` |
| Project-specific | `projects/<project>/invariants/checks/` | Checks specific to this project's ADRs and invariants | `domain-layer-imports.sh` (ADR-0007), `no-hardcoded-profiles.sh` |

Profile-generic checks are extracted from the profile into the team repo during `bm init`, alongside the existing profile invariant markdown files. Project-specific checks are authored by the team in the project repo, alongside the 11 existing prose invariants.

**Check runner.** A runner script at `team/coding-agent/skills/check-runner/run-checks.sh` handles discovery and execution:

1. Accepts a project name argument (e.g., `botminter`)
2. Discovers all `.sh` files in `team/invariants/checks/` and `projects/<project>/invariants/checks/`
3. Executes each with `cwd = projects/<project>/`
4. Distinguishes violations (exit 1 + VIOLATION output) from crashes (exit 1 without VIOLATION, or exit > 1)
5. Aggregates results: all violations reported, crashes logged as warnings
6. Exits 0 if all checks pass, exits 1 if any violations found

**Baseline checks.** The scrum-compact profile ships these profile-generic checks (extracted to `team/invariants/checks/`):

| Script | What It Validates | Enforcement Method |
|---|---|---|
| `file-size-limit.sh` | No source file exceeds 300 lines (ADR-0006) | `wc -l` on source files |
| `test-path-isolation.sh` | Tests don't use real HOME paths | Grep for `home_dir()` outside test setup |

The BotMinter project adds these project-specific checks (in `projects/botminter/invariants/checks/`):

| Script | What It Validates | Enforcement Method |
|---|---|---|
| `domain-layer-imports.sh` | Domain modules don't import CLI libs (ADR-0007) | Grep for `clap` and `println!` imports in domain module directories |
| `no-hardcoded-profiles.sh` | No hardcoded profile/status/role strings | Grep for known names in non-test source |

**Hat integration.** Two hats gain check-running steps in their instructions:
- `dev_code_reviewer`: runs the check runner before reviewing. If any violations are found, rejects to `dev:implement` with the VIOLATION/REMEDIATION output as the feedback comment.
- `qe_verifier`: runs the check runner as part of verification. Violations block verification.

Hat instructions specify: `bash team/coding-agent/skills/check-runner/run-checks.sh botminter`. The runner handles cwd, discovery, and error classification.

**Prose invariants remain.** Not every rule can be mechanically checked. `cli-idempotency` requires behavioral testing — you'd have to run each command twice and compare state, which is an E2E test, not a lint. Prose invariants stay as reference docs for rules that require judgment. Executable checks handle what can be automated.

#### Acceptance Criteria

- **Given** a code change introduces `println!` in a domain module, **when** `dev_code_reviewer` runs invariant checks, **then** the check fails with a structured VIOLATION/REMEDIATION message, and the story returns to `dev:implement`.
- **Given** all checks pass, **when** `dev_code_reviewer` runs checks, **then** review proceeds normally.
- **Given** a new `.sh` script is added to either checks directory, **when** subsequent reviews run the check runner, **then** the new check is discovered and executed.
- **Given** a check script has a syntax error, **when** the runner executes it, **then** the crash is logged as a warning but does not block the review. Only explicit violations (exit 1 + VIOLATION output) block.

---

### 3.2 Feature 2: Application Legibility

#### Problem

When `qe_investigator` investigates a bug, it reads source code. It has no running application to probe, no structured test output to parse, no logs to query. Harness addressed this by making the application itself legible to agents:

> *"We made the app bootable per git worktree, so Codex could launch and drive one instance per change. [...] We regularly see single Codex runs work on a single task for upwards of six hours."*

BotMinter is a CLI tool, not a web app. Chrome DevTools Protocol doesn't apply. But the principle does: agents need structured, parseable feedback from the system they're building.

#### Design

**Phase A: Structured test output.**

`cargo test` produces raw console text. Agents pattern-match against this to find failures — fragile, loses detail, misses context. The profile adds a knowledge convention defining structured JSON output for test results:

```json
{"test": "formation::local::test_start_members", "status": "FAIL", "duration_ms": 1204, "error": "assertion failed: member.is_healthy()", "file": "crates/bm/src/formation/local/mod.rs", "line": 245}
```

Implementation: a wrapper script (shipped with the profile, extracted to `team/coding-agent/skills/`) runs `cargo test` and post-processes output into JSON. Hats (`qe_investigator`, `dev_implementer`, `qe_verifier`) use this to navigate directly to failures.

Enforcement: the `dev_code_reviewer` hat and a check script (Feature 1) verify that test commands use the structured output wrapper.

**Phase B: Dev-environment bootstrapping.**

Projects with a runnable application define boot/teardown configuration in `team/projects/<project>/knowledge/dev-boot.yml`:

```yaml
dev_boot:
  command: "just dev-start"
  health_check: "just dev-health"
  teardown: "just dev-stop"
  isolation: worktree
```

This file lives in the team repo's project knowledge directory because it's project-specific (different projects have different boot commands) and consumed by hats at runtime (hats read `team/projects/<project>/knowledge/` as part of knowledge resolution). It is not in `botminter.yml` because dev-boot is a project concern, not a team-level manifest field.

This aligns with ADR-0008's formation abstraction. The `dev_implementer` and `qe_verifier` hats check for `dev-boot.yml` in the project knowledge directory. If present, they boot the app with `cwd = projects/<project>/`, validate behavior at runtime, and tear down when done. Each worktree gets an isolated instance.

**Phases C-D deferred.** Ephemeral observability (C) and UI introspection (D) are deferred until Phase B proves useful. BotMinter's console UI (`rust-embed` feature) could eventually use browser automation, but the CLI testing foundation must be solid first.

#### Acceptance Criteria

- **Given** tests run during implementation, **when** they complete, **then** structured JSON output is available with test name, status, duration, error, file, and line.
- **Given** a project with `dev-boot.yml` in its knowledge directory, **when** `dev_implementer` works on a story, **then** the application boots in isolation and the agent validates behavior at runtime.

---

### 3.3 Feature 3: Garbage Collection

#### Problem

Harness found that agents replicate whatever patterns exist in the repo — even bad ones. Without active cleanup, entropy compounds:

> *"Our team used to spend every Friday (20% of the week) cleaning up 'AI slop.' Unsurprisingly, that didn't scale. Instead, we started encoding what we call 'golden principles' directly into the repository and built a recurring cleanup process."*

BotMinter's codebase has evolved through four methodology phases. Planning artifacts exist across `.planning/`, `specs/`, `docs/`, and knowledge directories. No process detects stale documentation that references renamed functions, duplicated utility code, or quality drift.

#### Design

**Gardener hat.** A new hat (`arch_gardener`) added to the superman role definition in `ralph.yml`. Triggered by `gardener.scan` events.

**Scheduling.** The board-scanner skill's dispatch table gains a new entry: `gardener.scan`, dispatched on a cadence. This is a profile-level orchestration change — it modifies the scanner skill's instructions and adds a new event type to the dispatch table. The scanner tracks a cycle counter in its scratchpad (`.ralph/agent/scratchpad.md`). A knowledge file (`team/knowledge/gardener-config.md`) specifies the interval (e.g., "run gardener every 10 scan cycles"). When the counter reaches the interval, the scanner emits `gardener.scan` instead of (or after) processing the highest-priority issue. The counter resets.

The gardener hat:

1. Runs the check runner (Feature 1) and logs aggregate results
2. Scans code against golden principles (below) — detects pattern violations
3. Checks documentation freshness: do referenced functions, files, and paths still exist?
4. Produces a quality score per domain area (coverage, invariant compliance, doc freshness)
5. Opens targeted issues for violations — specific files, specific fixes, specific rationale
6. If more than 7 days have elapsed since the last metrics report (checked via file timestamp of the latest report in `team/projects/<project>/knowledge/reports/`), creates a `cw:write` issue for the weekly summary (see Feature 6, Reporting)

**Golden principles.** A YAML file in the project repo's invariants directory (`projects/<project>/invariants/golden-principles.yml`), encoding recurring quality rules. Golden principles are split into two categories based on how they're enforced:

**Mechanically checkable principles** — these become check scripts (Feature 1) that the gardener also runs. Each principle that can be detected by grep, AST scanning, or file system inspection gets a corresponding script in `projects/<project>/invariants/checks/`:

```yaml
principles:
  mechanically_checkable:
    - name: consistent-error-handling
      description: "Use anyhow for application errors, thiserror for library errors"
      check_script: "consistent-error-handling.sh"
      remediation: "Standardize on the crate's chosen error strategy"
```

**Judgment-based principles** — these remain as structured guidance for the gardener hat. The gardener applies LLM judgment to detect these during its scan. This is honest: these principles are trust-based, same as current prose invariants, but centralized in one file and applied on a recurring schedule rather than ad-hoc during code review:

```yaml
principles:
  judgment_based:
    - name: shared-utilities-over-duplicated
      description: "Prefer shared utility modules over copy-pasted helpers"
      detection_hint: "Look for functions with similar names and signatures across different modules"
      remediation: "Extract to shared module, update call sites"

    - name: typed-boundaries
      description: "Parse and validate at system boundaries, not inline"
      detection_hint: "Look for raw string parsing or deserialization outside config/input modules"
      remediation: "Move parsing to boundary layer, pass typed data internally"
```

The `detection_hint` field tells the gardener *what to look for*, not *how to find it mechanically*. The distinction from prose invariants: golden principles are centralized, versioned, and applied on schedule by a dedicated hat — not scattered across files and applied ad-hoc.

#### Acceptance Criteria

- **Given** the gardener scans, **when** it finds duplicated utility code matching a judgment-based principle, **then** it opens an issue naming the specific files and a remediation plan.
- **Given** a knowledge file references a renamed function, **when** the freshness check runs, **then** a fix-up issue is opened.
- **Given** the gardener completes, **when** it writes the quality score, **then** it reflects current coverage, compliance, and doc freshness.
- **Given** more than 7 days since the last metrics report, **when** the gardener scans, **then** it creates a `cw:write` issue for the weekly summary.

---

### 3.4 Feature 4: Plans as First-Class Artifacts

#### Problem

Harness treats plans as versioned, in-repo artifacts:

> *"Active plans, completed plans, and known technical debt are all versioned and co-located, allowing agents to operate without relying on external context."*

BotMinter's planning artifacts are scattered. The BotMinter project repo alone contains: 10 ADRs in `.planning/adrs/`, feature specs in `specs/`, documentation in `docs/`, knowledge in `knowledge/`, design docs in the team repo. Story breakdowns exist only in GitHub issue comments — the `arch_monitor` hat must query GitHub to check progress rather than consulting a local document.

#### Design

**Execution plans.** When `arch_planner` produces a story breakdown, it creates an execution plan — a living document that tracks the epic through implementation:

```markdown
# Execution Plan: Epic #106 — Transition BotMinter to Fully Agentic SDLC

## Status: In Progress

## Stories
| # | Title | Status | Completed |
|---|-------|--------|-----------|

## Key Decisions
| Date | Decision | Rationale |
|------|----------|-----------|

## Progress Notes
- 2026-04-04: Stories created, implementation starting
```

Plans live in the team repo at `team/projects/<project>/plans/`. This location is consistent with the knowledge hierarchy — plans are project-specific team artifacts consumed by hats during execution.

**Hat integration:**
- `arch_planner`: creates the plan when a breakdown is approved
- `arch_monitor`: updates the plan as stories complete, logs key decisions
- On epic completion: plan status → Completed

**Artifact home convention.** The profile establishes where each artifact type belongs:

| Artifact | Home | Rationale |
|----------|------|-----------|
| ADRs | Project repo (`.planning/adrs/`) | Codebase decisions. Live with the code per ADR-0001. |
| Design docs | Team repo project knowledge (`team/projects/<project>/knowledge/designs/`) | Design context consumed by hats during planning and implementation. |
| Execution plans | Team repo project plans (`team/projects/<project>/plans/`) | Living documents tracking execution. Updated by `arch_monitor`. |
| Knowledge | Team repo knowledge hierarchy | Advisory context loaded on-demand by hats. |
| Invariants | Profile (team repo) or project repo | Constraints enforced by hats and check scripts. |

This doesn't invalidate existing artifacts. Old plans stay where they are. New work follows the convention.

#### Acceptance Criteria

- **Given** `arch_planner` produces a breakdown, **when** it's approved, **then** an execution plan exists at `team/projects/<project>/plans/` with the story list.
- **Given** a story completes, **when** `arch_monitor` scans, **then** the plan's story table is updated.
- **Given** all stories complete, **when** the epic is accepted, **then** the plan is marked completed.

---

### 3.5 Feature 5: Graduated Autonomy

#### Problem

The scrum-compact profile hard-codes three human gates: `po:design-review`, `po:plan-review`, `po:accept`. Every epic hits all three regardless of the team's confidence in agent output quality.

Harness progressively reduced human involvement as their enforcement infrastructure matured:

> *"Humans may review pull requests, but aren't required to. Over time, we've pushed almost all review effort towards being handled agent-to-agent."*

The critical sequencing: Harness built mechanical enforcement *first*, then graduated to reduced human oversight. They earned autonomy by proving quality, not by assuming it.

#### Design

**Manifest extension.** The `team/botminter.yml` manifest gains an `autonomy` field:

```yaml
autonomy:
  tier: supervised    # supervised | guided | autonomous
```

| Tier | Human Gates | Prerequisite |
|------|-------------|--------------|
| `supervised` (default) | design-review, plan-review, accept | None — current behavior |
| `guided` | accept only | Executable checks passing consistently. Rejection rate < 15% at lead review (measured by Feature 6). |
| `autonomous` | none — async notification only | Quality metrics sustained at `guided` tier for at least one full epic cycle. |

**CLI implementation.** The `ProfileManifest` struct in `crates/bm/src/profile/manifest.rs` gains an optional `autonomy` field. Defaults to `supervised`. The field is written to `team/botminter.yml` during extraction and persists there as the runtime source of truth.

**Manifest-to-runtime flow.** The `botminter.yml` file in the team repo IS the runtime config. It is not an extraction-time-only artifact — the codebase already reads it at runtime via `read_team_repo_manifest()` (in `profile/team_repo.rs`). Hats access the team repo at `team/` as part of the workspace layout. The flow:

1. **Extraction time:** `bm init` writes the `autonomy` field to `team/botminter.yml` (default: `supervised`)
2. **Configuration change:** Operator runs `bm teams sync` to update the field (e.g., from `supervised` to `guided`). Agents cannot change this field — it requires a CLI command.
3. **Runtime:** The `po_reviewer` hat instructions include a step: "Read `team/botminter.yml` and check the `autonomy.tier` field." The hat instructions parse the YAML directly (hats already read YAML knowledge files as part of normal operation).

**Hat behavior.** The `po_reviewer` hat checks the autonomy tier:
- `supervised`: current behavior — post review request, wait for human comment
- `guided`: auto-advance `po:design-review` and `po:plan-review` after lead approval. Wait for human only at `po:accept`. Post notification comment on each auto-advance.
- `autonomous`: auto-advance all gates. Post notification comments. Human retains override.

**Override mechanism.** At any tier:
- `Rejected: <feedback>` on any issue reverts an auto-advance
- `Hold` pauses auto-advance for that specific issue
- Tier changes require `bm teams sync` — agents cannot escalate their own autonomy

**Dependency on Features 1 and 6.** Autonomy is only safe when enforcement is mechanical (Feature 1) and quality is measurable (Feature 6). Implementation order (Section 8) reflects this.

#### Acceptance Criteria

- **Given** `autonomy: guided` in `team/botminter.yml`, **when** lead review approves a design, **then** `po:design-review` auto-advances with a notification comment.
- **Given** `autonomy: guided` and an epic at `po:accept`, **when** the scanner dispatches, **then** the agent waits for human comment.
- **Given** a human comments `Rejected: <feedback>` on an auto-advanced issue, **when** the agent scans, **then** the status reverts and feedback is processed.

---

### 3.6 Feature 6: Metrics and Feedback Loops

#### Problem

BotMinter's `poll-log.txt` provides an audit trail but no analytics. Right now, nobody can answer: what's the rejection rate at code review? How long do issues spend waiting for human approval? Is cycle time improving or degrading?

Without metrics, the progression from `supervised` to `guided` autonomy is a guess. With metrics, it's evidence.

#### Design

**Transition logging.** The board-scanner skill's instructions gain an additive step: after each status transition, append a JSONL entry to `metrics/transitions.jsonl` (relative to workspace root):

```json
{"issue": 106, "type": "Epic", "from": "arch:design", "to": "lead:design-review", "ts": "2026-04-04T01:10:00Z", "hat": "arch_designer"}
```

This is a profile-level orchestration change — one line added to the scanner skill's instructions. The skill already logs to `poll-log.txt` and posts comments; this is additive.

**Derived metrics:**

| Metric | Measures | Use |
|--------|----------|-----|
| Design cycle time | `arch:design` → `po:ready` | Identify bottlenecks in the design pipeline |
| Implementation cycle time | `dev:implement` → `qe:verify` | Track velocity |
| Human gate wait time | Duration in `po:*-review` statuses | Justify `guided` autonomy |
| Rejection rate per gate | Percentage of rejections at each status | Quality signal. < 15% qualifies for `guided`. |
| First-pass rate | Stories reaching `done` without rejection | Quality indicator |

**Reporting.** The gardener hat (Feature 3) checks whether a weekly metrics report is due during each scan. If more than 7 days have passed since the last report (determined by file timestamp in `team/projects/<project>/knowledge/reports/`), the gardener creates a GitHub issue at `cw:write` status with the report task. This issue flows through normal board dispatch to the `cw_writer` hat, which reads the JSONL log and generates a summary. The existing `retrospective` skill receives metrics as input for data-driven retros.

This uses the existing issue lifecycle — no new scheduling mechanism beyond the gardener's cadence (Feature 3).

#### Acceptance Criteria

- **Given** the scanner transitions an issue, **when** the transition completes, **then** a JSONL entry is appended to `metrics/transitions.jsonl`.
- **Given** more than 7 days since the last report and the gardener runs, **when** it creates a `cw:write` issue, **then** the `cw_writer` generates a weekly summary with cycle times, rejection rates, and throughput.
- **Given** the retro skill runs, **when** metrics data exists, **then** data-driven observations are included.

---

## 4. Data Models

### Check Script Output (stdout on failure)
```
VIOLATION: <what was detected>
RULE: <which invariant or ADR>
REMEDIATION: <what the agent should do>
REFERENCE: <path to governing document>
```

### Golden Principles (YAML — in project repo)
```yaml
principles:
  mechanically_checkable:
    - name: string
      description: string
      check_script: string    # filename in invariants/checks/
      remediation: string
  judgment_based:
    - name: string
      description: string
      detection_hint: string  # what the gardener looks for (LLM judgment)
      remediation: string
```

### Dev-Boot Configuration (YAML — in team project knowledge)
```yaml
# team/projects/<project>/knowledge/dev-boot.yml
dev_boot:
  command: string       # boot command, run with cwd = projects/<project>/
  health_check: string  # health check command
  teardown: string      # teardown command
  isolation: worktree   # each worktree gets its own instance
```

### Autonomy Configuration (in `team/botminter.yml`)
```yaml
autonomy:
  tier: supervised | guided | autonomous
```

### Transition Log Entry (JSONL — in workspace root)
```json
{"issue": 0, "type": "Epic|Task|Bug", "from": "status", "to": "status", "ts": "ISO 8601", "hat": "hat_name"}
```

### Execution Plan (Markdown — in team project plans)
```markdown
# Execution Plan: Epic #<n> — <title>
## Status: In Progress | Completed
## Stories
| # | Title | Status | Completed |
## Key Decisions
| Date | Decision | Rationale |
## Progress Notes
- <date>: <event>
```

---

## 5. Error Handling

**Check script crashes vs. violations.** A script that errors unexpectedly (syntax error, runtime crash) produces exit 1 without VIOLATION output, or exit > 1. The check runner logs this as a warning and skips the script. Only explicit violations (exit 1 with VIOLATION output on stdout) block review. Three consecutive crashes from the same script flag it for human attention via an issue. This distinction applies uniformly: the `dev_code_reviewer`, `qe_verifier`, and gardener hats all use the check runner, which handles classification.

**Dev-boot failures.** Boot failure or health-check timeout: agent proceeds without the running application (degraded mode). Warning comment posted on the issue.

**Auto-advance failures.** Status transition error during auto-advance: fall back to supervised behavior for that gate. Retry on next scan cycle.

**Gardener failures.** Scan failure: retry on next cycle, maximum 3 retries before flagging for human attention. Gardener failures never block other work — gardening is background maintenance.

**Metrics write failures.** JSONL write failure is logged but does not block the status transition. Metrics are observational, not transactional.

---

## 6. Impact on Existing System

### Profile-Level Changes

| Component | Change | Risk |
|---|---|---|
| `team/invariants/checks/` | New directory + 2 profile-generic baseline scripts | Low — additive |
| `ralph.yml` hats | New `arch_gardener` hat definition | Medium — new hat, tested in isolation |
| `ralph.yml` hats | Updated `dev_code_reviewer` and `qe_verifier` instructions (add check-running step) | Medium — additive instruction change |
| Board-scanner skill | Add `gardener.scan` dispatch entry + cycle counter | Medium — new event type in dispatch table |
| Board-scanner skill | Add JSONL transition logging instruction | Low — additive |
| `team/knowledge/` | Two new docs: structured test output convention, check script contract | Low — additive |
| `team/coding-agent/skills/check-runner/` | New check runner script | Low — new skill |
| `team/projects/<project>/plans/` | New directory for execution plans | Low — empty initially |

### Project Repo Changes

| Component | Change | Risk |
|---|---|---|
| `projects/<project>/invariants/checks/` | New directory + project-specific check scripts | Low — additive |
| `projects/<project>/invariants/golden-principles.yml` | New config file | Low — additive |

### Manifest / CLI Changes

| Component | Change | Risk |
|---|---|---|
| `team/botminter.yml` | `autonomy` field (optional, defaults to `supervised`) | Low — backward compatible |
| `crates/bm/src/profile/manifest.rs` | Parse optional `autonomy` field in `ProfileManifest` | Low — new optional field |
| Extraction logic | Extract `invariants/checks/` directory | Low — additive |

### What Does NOT Change

- Ralph Orchestrator product (`ralph.yml` schema definition, event loop engine, hat dispatch engine)
- Formation system and credential management (ADR-0002, ADR-0008)
- Bridge system
- GitHub Projects integration (same statuses, same board structure, no new statuses)
- Existing invariant and ADR markdown files (these remain; executable checks are additive)
- The `bm init`, `bm hire`, `bm start` command interfaces
- Human gate behavior by default (unless the operator explicitly changes the autonomy tier via `bm teams sync`)

---

## 7. Security Considerations

**Check scripts execute in the agent's context.** Scripts are read-only analyzers — they scan code, they do not modify it. They are version-controlled in the team repo or project repo, not arbitrary uploads. Following ADR-0002's pattern: declarative scripts with structured output, not unconstrained executables. A check script must not write files, make network requests, or modify git state.

**Autonomy escalation prevention.** The `autonomous` tier removes all human gates. The setting lives in `team/botminter.yml` and requires `bm teams sync` to change — agents cannot modify this file through the normal workflow (it's in the team repo, not a hat output). The `Rejected:` comment provides an emergency brake at any tier. Recommendation: sustain `guided` tier for at least one full epic cycle with acceptable metrics before considering `autonomous`.

**Gardener changes go through normal review.** The gardener opens issues and (potentially) PRs for cleanup work. These flow through the standard `dev:implement` → `dev:code-review` → `qe:verify` pipeline. The gardener does not merge its own changes.

**Metrics contain no sensitive data.** Transition logs record issue numbers, status names, timestamps, and hat names. No PII, credentials, or application data.

---

## 8. Implementation Order

| Phase | Feature | Depends On | Risk | Rationale |
|---|---|---|---|---|
| 1 | Executable Invariant Checks | — | Low | Foundation. Quality enforcement must exist before anything else. |
| 2 | Plans as First-Class Artifacts | — | Low | Low-risk, resolves artifact fragmentation immediately. |
| 3 | Garbage Collection | Phase 1 | Low | Gardener runs the checks from Phase 1 plus golden principles. Includes board-scanner dispatch table change. |
| 4 | Metrics and Feedback Loops | — | Low | Produces the data needed to justify Phase 5. Includes board-scanner logging change. |
| 5 | Graduated Autonomy | Phases 1, 4 | Medium | Requires proven enforcement + quality evidence. Includes `po_reviewer` hat behavior change and `botminter.yml` manifest extension. |
| 6 | Application Legibility | — | Medium-High | Most complex. Structured test output is standalone; dev-boot requires formation alignment (ADR-0008). |

Enforcement first. Autonomy only after quality infrastructure is proven. Legibility last because it's the most complex and least coupled to the other features.

---

## 9. References

- OpenAI Harness Engineering (Feb 2026) — primary reference for enforcement-first agentic development
- ADR-0001: ADR Process — governs where ADRs live (project repo)
- ADR-0002: Shell Script Bridge — design pattern for check script contract (structured output from shell scripts)
- ADR-0006: Directory Modules — convention that `file-size-limit` check enforces
- ADR-0007: Domain-Command Layering — primary target for mechanical enforcement (`domain-layer-imports` check)
- ADR-0008: Formation as Deployment Strategy — alignment point for dev-boot feature
- `team/botminter.yml` — manifest being extended with `autonomy` field
- `crates/bm/src/profile/manifest.rs` — `ProfileManifest` struct gaining `autonomy` field
- `profile/team_repo.rs` (`read_team_repo_manifest()`) — runtime manifest read path
- BotMinter project invariants (11 files in `projects/botminter/invariants/`) — existing prose invariants that gain an executable layer
