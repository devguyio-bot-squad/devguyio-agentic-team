# Design: Transition BotMinter to Fully Agentic SDLC

**Epic:** #106
**Author:** bob (superman)
**Date:** 2026-04-03
**Status:** Draft (Revision 2 — addressing PR #107 feedback)
**Reference:** [OpenAI Harness Engineering (Feb 2026)](https://openai.com/index/harness-engineering/)

---

## 1. Overview

Transition BotMinter from its current supervised agentic SDLC (Tier 2 — AI-Driven) to a fully agentic SDLC (Tier 3 — AI-Autonomous), inspired by OpenAI's Harness Engineering methodology.

OpenAI's Harness team shipped ~1M lines of production code in 5 months with **zero manually-written code** using 3 engineers (later 7). Their key insight:

> *"When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it legible and enforceable for the agent?'"*

BotMinter has structural alignment with several Harness patterns (~65% defined, ~45% operationally realized). However, BotMinter itself was not built using its current agentic SDLC from day one — it evolved through multiple development methodology phases. An honest assessment of this history is essential for identifying the real gaps and designing the right transition.

---

## 2. Architecture: Current State vs Target State

### 2.1 BotMinter Development History

BotMinter was NOT built using its own agentic SDLC from day one. Understanding how the product evolved through different methodology phases is critical for an honest gap analysis — each phase contributed different capabilities with different maturity levels.

#### Phase 1: Traditional Development (v0.01–v0.05, Feb 2026)

The foundational CLI and workspace model were built through conventional human-directed development. Ralph Orchestrator served as the execution engine, but there was no formal AI planning framework — the agent was directed interactively or via ad-hoc prompts.

**What was built:**
- Core `bm` CLI (`init`, `hire`, `fire`, `sync`, `start`, `stop`, `status`, `chat`)
- Profile system with embedded compile-time profiles
- Workspace model (team repo + project submodules + file surfacing)
- GitHub coordination (issues, milestones, labels, Projects v2 bootstrapping)
- Two-layer runtime model (inner Ralph loop + outer team repo control plane)
- E2E test harness with `libtest-mimic`

**Development method:** Human-driven with Ralph as execution engine. No formal planning artifacts on disk. The retrospective confirms: *"Phases 2-4 had no GSD plans on disk: These phases were implemented before GSD was initialized"* (`.planning/RETROSPECTIVE.md`).

**Maturity:** High — 471 tests (327 unit + 49 cli_parsing + 95 integration) by the end of this phase. Core CLI commands battle-tested through real operational use.

#### Phase 2: GSD Framework (v0.06–v0.07, Mar 2026)

[GSD (Get Shit Done)](https://github.com/gsd-build/get-shit-done) introduced the first structured AI planning methodology: milestone decomposition into phases and plans (`PLAN.md` files with YAML frontmatter), a five-step CLI-agent handshake, verification loops with `must_haves` contracts, and parallel worktree execution.

**What was built:**
- Coding-agent-agnostic architecture with inline agent tags
- Composable skills system (board-scanner, status-workflow, github-project)
- `bm chat` and `bm minty` interactive assistant with 4 skills
- Bridge abstraction (Telegram, Rocket.Chat, Tuwunel/Matrix)
- Profile integration for bridges, credential store with keyring backend
- 399 files changed, 34k insertions across v0.06 alone

**Development method:** Agent-driven with GSD-structured planning. Each phase had formal `PLAN.md` files, verification checks, and UAT gap closure. *"First milestone using GSD workflow; UAT gap closure pattern established"* (`.planning/RETROSPECTIVE.md`).

**Maturity:** Medium-High — 576 tests by end of v0.07. Bridge lifecycle validated via e2e and exploratory tests on an isolated test user account.

#### Phase 3: Agent SOP / Ralph Hat System (concurrent with late GSD, evolving)

Ralph's hat definitions were progressively formalized as structured standard operating procedures. The Ralph system prompt defines a strict ORIENTATION - STATE MANAGEMENT - PLAN - DELEGATE - HATS - DONE cycle. Each hat's `instructions` block in `ralph.yml` functions as a codified SOP for that role — the "Agent SOP" phase is when these informal practices were encoded into machine-readable hat instructions.

**What was built:**
- Board scanner procedure (auto-injected skill, not a hat)
- 18 hat definitions with structured instructions in `ralph.yml`
- Event-driven dispatch via `ralph emit` and hat chaining
- Status graph with 32 statuses and defined transitions
- Evidence gates and backpressure quality enforcement
- Human review gates (po:design-review, po:plan-review, po:accept)

**Development method:** Iterative formalization — human and agent collaboration encoding process knowledge into hat instructions and event topology. Not built by the hats themselves, but by humans and agents encoding operational procedures into the team repo.

**Maturity:** Medium — the hat system is functional and has been running for weeks, but some hats have been exercised significantly more than others.

#### Phase 4: A-Team / Dogfooding (Late Mar 2026–present)

The current `devguyio-agentic` team IS the "A-Team" — a team created using BotMinter's own `bm init` workflow, running the `scrum-compact` profile, with `superman-bob` wearing all 18 hats to develop BotMinter itself. This is the self-bootstrapping/dogfooding phase.

**What it validates:**
- Full issue lifecycle (triage - design - plan - breakdown - implement - review - verify - done)
- Hat switching within a single superman agent
- Human gates via GitHub comments (supervised mode)
- Board-driven dispatch and auto-advance transitions
- Knowledge resolution across 5 scoping levels

**Development method:** BotMinter developing BotMinter. The team repo tracks issues on GitHub Projects v2; superman-bob processes them through the hat-based SDLC.

**Maturity:** Early — the A-Team has been running for approximately one week. Design and triage workflows have been exercised; the full story implementation cycle (TDD - implement - code review - verify) has not yet been validated end-to-end.

### 2.2 Current Capabilities Inventory

The following table maps each capability to its origin phase and assessed maturity level:

| Capability | Origin Phase | Maturity | Notes |
|---|---|---|---|
| Core CLI (`init`, `hire`, `sync`, `start`, `stop`) | Traditional (v0.01-v0.05) | High | Battle-tested, 576+ tests |
| Profile system (embedded, compile-time) | Traditional (v0.01-v0.05) | High | 2 profiles (scrum, scrum-compact) |
| Workspace model (team repo + project submodules) | Traditional (v0.01-v0.05) | High | Proven in production use |
| GitHub coordination (issues, milestones, Projects v2) | Traditional (v0.01-v0.05) | High | Operational since Feb 2026 |
| Coding-agent-agnostic architecture | GSD (v0.06) | High | Agent tags, filtered extraction |
| Skills system (composable, two-level scoping) | GSD (v0.06) | Medium-High | 10+ skills in active use |
| Bridge abstraction (Telegram, RC, Matrix) | GSD (v0.07) | Medium-High | E2E + exploratory tested |
| Interactive assistant (`bm chat`, `bm minty`) | GSD (v0.06) | Medium | 4 Minty skills |
| Board scanner + status-driven dispatch | SOP/Hats (evolving) | Medium | Functional, exercised across multiple scan cycles |
| 18 hat definitions (PO, arch, dev, QE, SRE, CW, lead) | SOP/Hats (evolving) | Medium | Some hats (po_backlog, arch_designer) more exercised than others (sre_setup, cw_writer) |
| Knowledge hierarchy (5 scoping levels) | SOP/Hats (evolving) | Medium | Structure proven, content depth varies by area |
| Invariant system (team, project, member levels) | SOP/Hats (evolving) | Low-Medium | Prose-only, no mechanical enforcement |
| Rejection loops at review gates | A-Team (dogfooding) | Low-Medium | Exercised a few times during dogfooding |
| TDD-first story workflow | A-Team (dogfooding) | Low | Defined in hat instructions but not yet fully validated end-to-end |
| Bug triage (simple vs complex paths) | A-Team (dogfooding) | Low | Defined but untested end-to-end |

### 2.3 Harness Pattern Alignment (Honest Assessment)

This table maps Harness Engineering patterns to BotMinter equivalents, with an honest maturity assessment distinguishing between what is structurally defined vs. operationally proven.

| Harness Pattern | BotMinter Equivalent | Structural Alignment | Operational Maturity |
|---|---|---|---|
| Agent specialization | 18 hats (PO, arch, dev, QE, SRE, CW, lead) | Strong | Medium — defined and functional but most hats have limited operational history |
| Agent-to-agent review | `lead_reviewer` - `dev_code_reviewer` - `qe_verifier` chain | Strong | Low-Medium — review chain defined, exercised only a handful of times |
| AGENTS.md as table of contents | CLAUDE.md - `team/knowledge/`, invariants, hat knowledge | Strong | High — knowledge entry point pattern well-established |
| Structured docs as system of record | `team/knowledge/` with 5-level scoping | Moderate | Medium — structure exists, content depth varies |
| Architectural constraints via rules | `team/invariants/`, project invariants, member invariants | Weak | Low — invariants are prose markdown, no mechanical enforcement |
| Plans as first-class artifacts | Design docs in `team/projects/<project>/knowledge/designs/` | Weak | Low — designs exist but no execution plans, progress logs, or tech debt tracking |
| Feedback loops (review - reject - revise) | Rejection loops at every gate | Moderate | Low-Medium — loops defined, exercised a few times |
| Declarative workflow (status-driven dispatch) | Board scanner + status graph + hat dispatch | Strong | Medium — operational for weeks, handles auto-advance and human gates |
| Self-review chain ("Ralph Wiggum Loop") | `dev_implementer` - `dev_code_reviewer` - `qe_verifier` | Strong | Low — defined in hat instructions but full chain not yet validated |
| Repository as single source of truth | `team/` repo as control plane + project repos for code | Strong | High — proven since project inception |

**Overall alignment: ~45% operationally realized, ~65% structurally defined.** The gap between "structurally defined" and "operationally realized" is the maturity gap — many patterns are encoded in hat instructions and process docs but have limited real-world validation. This maturity gap must be addressed alongside the six architectural gaps below.

### 2.4 The Six Gaps

```
Current State                          Target State
-----------                            -----------
Prose invariants (honor system)   -->  Mechanical enforcement (CI lints + structural tests)
No telemetry access               -->  Per-worktree observability (logs/metrics/traces)
No automated cleanup              -->  Garbage collection (gardener hat + golden principles)
Designs only, no exec plans       -->  Plans as first-class artifacts (active/completed/debt)
3 hard human gates                -->  Graduated autonomy (supervised/guided/autonomous)
No metrics                        -->  Cycle-time + quality tracking + data-driven retros
```

**Note:** These gaps are assessed against Harness Engineering's validated patterns. Closing them requires not just building the features but also achieving sufficient operational maturity — each gap has a "build it" component and a "prove it works" component. The phased implementation plan (Section 8) accounts for this by recommending operational stabilization before advancing to higher-risk changes.

---

## 3. Components and Interfaces

### 3.1 Gap 1: Mechanical Enforcement

#### Problem
Invariants are markdown documents (`team/invariants/`, `team/projects/<project>/invariants/`). Agents are *instructed* to follow them. Nothing prevents violations from reaching code review.

Harness's approach: *"Custom linters and structural tests enforce layered architecture. Lint error messages are written for agents — they inject remediation instructions into context."*

#### Design

**3.1.1 Architecture Layers Definition**

Each project defines its allowed dependency layers in a machine-readable YAML file:

```yaml
# team/projects/botminter/invariants/architecture-layers.yml
layers:
  - name: types
    description: "Pure types/interfaces — no imports from other layers"
    allowed_imports: []
  - name: config
    description: "Configuration — imports types only"
    allowed_imports: [types]
  - name: repository
    description: "Data access — imports types, config"
    allowed_imports: [types, config]
  - name: service
    description: "Business logic — imports types, config, repo"
    allowed_imports: [types, config, repository]
  - name: runtime
    description: "Application bootstrap — imports all above"
    allowed_imports: [types, config, repository, service]
  - name: ui
    description: "Presentation — imports all above"
    allowed_imports: [types, config, repository, service, runtime]

cross_cutting:
  - name: providers
    description: "Auth, connectors, telemetry, feature flags — enter through single interface"
    accessible_from: [service, runtime, ui]
```

**3.1.2 Executable Invariant Checks**

Convert the top prose invariants into executable scripts:

```
team/projects/<project>/invariants/
  architecture-layers.yml          # Layer definitions (new)
  checks/                          # Executable checks (new)
    check-architecture-layers.sh   # Validates import directions
    check-structured-logging.sh    # Enforces structured log format
    check-naming-conventions.sh    # Validates naming patterns
    check-file-size-limits.sh      # Flags oversized files
    check-test-coverage.sh         # Minimum coverage thresholds
  design-quality.md                # Existing (remains as reference)
```

Each check script:
- Exits 0 on pass, 1 on failure
- On failure, prints **agent-readable remediation instructions** (not just "failed")
- Example error output:
  ```
  VIOLATION: service/auth.rs imports ui/components.rs
  LAYER RULE: 'service' layer must not import from 'ui' layer
  REMEDIATION: Move the shared type to 'types/' layer, then import from there.
  See: team/projects/botminter/invariants/architecture-layers.yml
  ```

**3.1.3 Integration Points**

- `dev_code_reviewer` hat runs all `checks/` scripts before reviewing
- `qe_verifier` hat runs checks as part of verification
- If any check fails, auto-reject back to `dev:implement` with the error output as feedback
- CI pipeline runs checks on every PR

**3.1.4 Custom Lint Error Messages**

Following Harness: *"Because the lints are custom, we write the error messages to inject remediation instructions into agent context."*

Every lint/check error message follows this template:
```
VIOLATION: <what happened>
RULE: <which rule was violated>
REMEDIATION: <exactly what to do to fix it>
REFERENCE: <path to the invariant/knowledge file>
```

#### Acceptance Criteria

- **Given** a code change that violates a defined architecture layer rule
  **When** the `dev_code_reviewer` hat runs invariant checks
  **Then** the check fails with an agent-readable remediation message and the story is rejected back to `dev:implement`

- **Given** a code change that passes all invariant checks
  **When** the `dev_code_reviewer` hat runs invariant checks
  **Then** all checks pass and review proceeds normally

- **Given** a new invariant is added to `checks/`
  **When** subsequent code reviews run
  **Then** the new check is automatically included without hat modifications

---

### 3.2 Gap 2: Application Legibility

#### Problem
QE investigates bugs by reading code and issue descriptions. No telemetry, no UI introspection. Agents can't observe runtime behavior.

Harness's approach: *"We made the app bootable per git worktree. We wired Chrome DevTools Protocol into the agent runtime. Logs, metrics, and traces are exposed via a local observability stack that's ephemeral for any given worktree."*

#### Design (Phased)

**Phase A: Structured Test Output (All projects)**

```
team/projects/<project>/invariants/
  test-output-format.yml           # Required test output structure
```

```yaml
# test-output-format.yml
requirements:
  - format: structured_json        # Tests must output parseable results
  - include:
    - test_name
    - status: [pass, fail, skip]
    - duration_ms
    - error_message                 # On failure
    - file_path                     # Source location
    - coverage_delta                # Optional
```

- `qe_investigator` and `dev_implementer` parse structured test output
- Test failures include stack traces and file locations agents can navigate
- Coverage reports available as data, not just pass/fail

**Phase B: Per-Worktree App Boot (Project-specific)**

- Projects that have a runnable app define a `dev-boot.sh` script
- Script boots the app in isolation (unique port, ephemeral DB)
- `sre_setup` hat provisions the environment
- `dev_implementer` can boot the app to validate behavior

```yaml
# team/projects/<project>/knowledge/dev-environment.yml
boot:
  script: ./scripts/dev-boot.sh
  health_check: http://localhost:${PORT}/health
  teardown: ./scripts/dev-teardown.sh
  isolation: worktree              # Each worktree gets its own instance
```

**Phase C: Observability Stack (Project-specific)**

Ephemeral per-worktree observability following Harness's architecture:

```
App → Vector (log/metric/trace collector)
       ├→ Victoria Logs  (queryable via LogQL)
       ├→ Victoria Metrics (queryable via PromQL)
       └→ Victoria Traces (queryable via TraceQL)
```

- Stack spins up with `dev-boot.sh`, tears down with worktree
- Agents query via standard APIs (LogQL, PromQL, TraceQL)
- Enables prompts like: "ensure no span exceeds 2 seconds" or "find the error causing this bug"

**Phase D: UI Introspection (Web projects only)**

- Chrome DevTools Protocol integration
- Agent capabilities: DOM snapshots, screenshots, navigation
- `qe_verifier` can validate UI state and take before/after screenshots

#### Acceptance Criteria

- **Given** a test suite runs during `dev:implement`
  **When** tests complete
  **Then** output is structured JSON that agents can parse for specific failure details

- **Given** a project with `dev-environment.yml` configured
  **When** `dev_implementer` works in a worktree
  **Then** the app boots in isolation and the agent can validate behavior against it

- **Given** a worktree with observability stack running
  **When** the agent queries logs for a specific error pattern
  **Then** matching log entries are returned with timestamps and context

---

### 3.3 Gap 3: Garbage Collection (Entropy Management)

#### Problem
No automated cleanup. No quality grading. No stale-doc detection. Over time, agent-generated patterns drift.

Harness's experience: *"Our team used to spend every Friday (20% of the week) cleaning up 'AI slop.' Instead, we started encoding 'golden principles' and built a recurring cleanup process. Technical debt is like a high-interest loan."*

#### Design

**3.3.1 Quality Scoring**

```markdown
# team/projects/<project>/knowledge/QUALITY_SCORE.md

## Quality Assessment — 2026-04-03

| Domain | Test Coverage | Invariant Compliance | Code Patterns | Doc Freshness | Grade |
|--------|--------------|---------------------|---------------|---------------|-------|
| Auth   | 85%          | Pass                | Clean         | Current       | A     |
| API    | 72%          | Pass                | 2 drift items | Stale (14d)   | B     |
| UI     | 45%          | 1 violation         | 5 drift items | Stale (30d)   | C     |

**Overall: B-**

### Drift Items
- [ ] API: duplicated validation helper in 3 locations
- [ ] UI: inconsistent error handling pattern
- [ ] API docs: doesn't reflect new endpoint added in #98
```

Updated weekly by the gardener process.

**3.3.2 Golden Principles**

```yaml
# team/projects/<project>/invariants/golden-principles.yml
principles:
  - name: shared-utilities-over-hand-rolled
    description: "Prefer shared utility packages over hand-rolled helpers"
    detection: "Find functions with >80% similarity across different modules"
    remediation: "Extract to shared utility, update all call sites"

  - name: validated-boundaries
    description: "Validate data at boundaries, not YOLO-style deep in logic"
    detection: "Find parse/deserialize calls without validation"
    remediation: "Add boundary validation using typed schemas"

  - name: no-dead-code
    description: "Remove unused functions, imports, and variables"
    detection: "Static analysis for unreachable code"
    remediation: "Delete the dead code"

  - name: consistent-error-handling
    description: "Use the project's error handling pattern consistently"
    detection: "Find error handling that doesn't match project pattern"
    remediation: "Refactor to use standard error pattern"
```

**3.3.3 Gardener Hat (`arch_gardener`)**

New hat added to superman's hat roster:

```yaml
# In ralph.yml hats section
arch_gardener:
  purpose: "Periodic codebase cleanup and quality assessment"
  trigger: "Recurring schedule (weekly) or manual invocation"
  workflow:
    1. Scan codebase against golden principles
    2. Run invariant checks, note any new violations
    3. Check doc freshness (modified date vs code changes)
    4. Update QUALITY_SCORE.md
    5. Open targeted refactoring PRs for drift items (small, reviewable in <1 min)
    6. Open fix-up PRs for stale docs
```

**3.3.4 Doc-Gardening**

Integrated into the gardener hat:
- Compare design docs against actual implementation
- Flag knowledge files that reference deleted/renamed code
- Check that PROCESS.md reflects current status graph
- Open fix-up issues or PRs for stale content

#### Acceptance Criteria

- **Given** the gardener hat runs its weekly scan
  **When** it detects duplicated utility code across modules
  **Then** it opens a refactoring PR to extract the shared utility

- **Given** a design doc references a function that was renamed
  **When** the doc-gardening scan runs
  **Then** a fix-up PR is opened updating the reference

- **Given** the gardener hat completes its scan
  **When** it updates QUALITY_SCORE.md
  **Then** the score reflects current test coverage, invariant compliance, and doc freshness

---

### 3.4 Gap 4: Plans as First-Class Artifacts

#### Problem
Design docs exist as files. Story breakdowns exist only in issue comments. No execution plans with progress tracking. No tech-debt tracker.

Harness's approach: *"Plans are treated as first-class artifacts. Complex work is captured in execution plans with progress and decision logs that are checked into the repository. Active plans, completed plans, and known technical debt are all versioned and co-located."*

#### Design

**3.4.1 Knowledge Directory Extension**

```
team/projects/<project>/knowledge/
  designs/                          # ✅ Already exists
    epic-106.md                     # This document
  plans/                            # 🆕
    active/
      epic-106-plan.md              # Execution plan with progress log
    completed/
      epic-24-plan.md               # Archived after epic completion
  generated/                        # 🆕
    board-snapshot.md                # Auto-generated board state
    architecture-map.md             # Auto-generated from code analysis
  product-specs/                    # 🆕
    index.md                        # Product requirements catalog
  references/                       # 🆕
    harness-engineering.md          # External reference docs
  QUALITY_SCORE.md                  # 🆕 (from Gap 3)
  tech-debt-tracker.md              # 🆕
```

**3.4.2 Execution Plan Format**

```markdown
# Execution Plan: Epic #106 — Agentic SDLC Transition

## Status: In Progress

## Stories
| # | Title | Status | Completed |
|---|-------|--------|-----------|
| 1 | Mechanical enforcement | dev:implement | — |
| 2 | Plans structure | qe:test-design | — |

## Decision Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-03 | Start with enforcement | Lowest risk, highest impact |
| 2026-04-05 | Skip Phase D for now | No web UI project yet |

## Progress Notes
- 2026-04-03: Epic created, design doc produced
- 2026-04-04: Design approved, planning started
```

**3.4.3 Tech Debt Tracker**

```markdown
# Tech Debt Tracker

## Active Debt

| ID | Description | Source | Priority | Effort |
|----|-------------|--------|----------|--------|
| TD-001 | Duplicated validation in API module | Epic #98 | Medium | 2h |
| TD-002 | Missing error handling in auth flow | Bug #105 | High | 4h |

## Resolved
| ID | Description | Resolved By | Date |
|----|-------------|-------------|------|
```

**3.4.4 Hat Integration**

- `arch_planner` writes execution plans to `plans/active/`, not just issue comments
- `arch_monitor` updates progress in the plan file as stories complete
- On epic completion, `arch_monitor` moves plan to `plans/completed/`
- `dev_implementer` logs discovered tech debt to `tech-debt-tracker.md`
- `arch_gardener` processes the debt tracker periodically

#### Acceptance Criteria

- **Given** the `arch_planner` hat produces a story breakdown
  **When** the breakdown is approved
  **Then** an execution plan file exists in `plans/active/` with story list and status

- **Given** a story reaches `done` status
  **When** `arch_monitor` scans the epic
  **Then** the execution plan's story table is updated to reflect completion

- **Given** all stories in an epic reach `done`
  **When** the epic is accepted
  **Then** the plan file moves from `plans/active/` to `plans/completed/`

---

### 3.5 Gap 5: Graduated Autonomy

#### Problem
3 hard human gates (`po:design-review`, `po:plan-review`, `po:accept`). Agent cannot proceed without explicit human approval. This is the biggest bottleneck.

Harness's evolution: *"Humans may review pull requests, but aren't required to. Over time, we've pushed almost all review effort towards being handled agent-to-agent."*

#### Design

**3.5.1 Trust Tiers**

```yaml
# ralph.yml — per-project autonomy configuration
projects:
  botminter:
    autonomy: supervised    # supervised | guided | autonomous

# Tier definitions:
# supervised (current default):
#   - 3 human gates: po:design-review, po:plan-review, po:accept
#   - Agent waits for human comment at each gate
#   - Human must explicitly approve or reject
#
# guided:
#   - 1 human gate: po:accept only
#   - lead_reviewer approval auto-advances design and plan reviews
#   - po:design-review → auto-advance after lead:design-review passes
#   - po:plan-review → auto-advance after lead:plan-review passes
#   - Human gets async notification of auto-advances
#   - Human can still intervene by commenting on any issue
#
# autonomous:
#   - 0 human gates (async notification only)
#   - All gates auto-advance after agent review passes
#   - Human reviews async via board/notifications
#   - Human can intervene at any time by commenting
```

**3.5.2 `po_reviewer` Hat Modification**

The `po_reviewer` hat checks the project's autonomy tier before gating:

```
# Pseudocode for po_reviewer decision
if autonomy == "supervised":
    # Current behavior: post review request, wait for human comment
    post_review_request()
    wait_for_human_response()

elif autonomy == "guided":
    if gate == "po:accept":
        # Still requires human
        post_review_request()
        wait_for_human_response()
    else:
        # Auto-advance after lead review passed
        post_notification_comment("Auto-approved (guided mode). Lead review passed.")
        auto_advance()

elif autonomy == "autonomous":
    # Auto-advance all gates
    post_notification_comment("Auto-approved (autonomous mode). Agent review passed.")
    auto_advance()
```

**3.5.3 Notification Comments**

When auto-advancing, the agent posts a notification comment so the human has an audit trail:

```markdown
### 📝 po — 2026-04-05T10:30:00Z

**Auto-approved (guided mode)**

Design review auto-advanced after lead review passed.
Lead review: approved by 👑 lead at 2026-04-05T10:25:00Z

To override: comment `Rejected: <feedback>` to revert.
```

**3.5.4 Override Mechanism**

Even in `guided` or `autonomous` mode, the human can intervene at any time:
- Comment `Rejected: <feedback>` on any issue to revert the most recent auto-advance
- Comment `Hold` to pause auto-advances for a specific issue
- Change the `autonomy` setting in `ralph.yml` to downgrade the tier

#### Acceptance Criteria

- **Given** a project configured with `autonomy: guided`
  **When** lead review approves a design doc
  **Then** `po:design-review` auto-advances to `arch:plan` with a notification comment

- **Given** a project configured with `autonomy: guided`
  **When** an epic reaches `po:accept`
  **Then** the agent posts a review request and waits for human comment (same as supervised)

- **Given** a project configured with `autonomy: autonomous`
  **When** any gate is reached
  **Then** the agent auto-advances with a notification comment and the human can override

- **Given** a human comments `Rejected: <feedback>` on an auto-advanced issue
  **When** the agent scans the issue
  **Then** the status reverts and the feedback is processed

---

### 3.6 Gap 6: Metrics and Feedback Loops

#### Problem
No cycle-time tracking. No quality metrics. No way to know if the process is improving. `poll-log.txt` exists for board scan audit but provides no analytics.

Harness's approach: They track quality grades per domain over time and measure throughput (3.5 PRs/engineer/day).

#### Design

**3.6.1 Transition Timestamps**

Board scanner logs every status transition to a JSONL file:

```jsonl
{"issue":106,"type":"Epic","from":"po:triage","to":"po:backlog","ts":"2026-04-03T15:00:00Z","hat":"po_backlog"}
{"issue":107,"type":"Task","from":"qe:test-design","to":"dev:implement","ts":"2026-04-03T15:05:00Z","hat":"qe_test_designer"}
```

Location: `team/metrics/transitions.jsonl` (append-only)

**3.6.2 Derived Metrics**

Computed from the transition log:

| Metric | What It Measures | Target |
|--------|-----------------|--------|
| Design cycle time | `arch:design` to `po:ready` | Trending down |
| Implementation cycle time | `dev:implement` to `qe:verify` | Trending down |
| Human gate wait time | Time in `po:design-review`, `po:plan-review`, `po:accept` | < 4 hours |
| Rejection rate per gate | % of times each gate rejects | < 15% |
| First-pass rate | % of stories that reach `done` without any rejection | > 70% |
| Throughput | Issues completed per day/week | Trending up |
| Bug escape rate | Bugs filed within 30 days of epic completion | Trending down |

**3.6.3 Weekly Quality Report**

Auto-generated, stored in `team/metrics/`:

```markdown
# Weekly Report — 2026-04-07

## Throughput
- Issues completed: 12
- PRs merged: 8
- Epics advanced: 2

## Cycle Times (median)
- Design → Ready: 3.2 days (prev: 4.1 days, -22%)
- Implement → Verify: 1.1 days (prev: 1.5 days, -27%)

## Gates
- Human gate wait time (median): 6.2 hours
- Rejection rate: 18% (target: <15%)
  - Code review: 25% (↑ — investigate)
  - QE verify: 12% (✓)

## Quality
- Invariant violations caught pre-review: 4
- Invariant violations reaching review: 0 (✓)
- Test coverage delta: +3.2%

## Action Items
- Code review rejection rate is above target. Review top rejection reasons.
```

**3.6.4 Retrospective Integration**

The existing `retrospective` skill receives metrics as input:
- Instead of "what went well?" → "design review took 3x longer on epic #24 than #18 — here's why"
- Data-driven action items backed by measured trends
- Retro outputs stored in `team/agreements/retros/` per existing convention

**3.6.5 Board Scanner Integration**

The board scanner (`board-scanner` skill) adds a single line per transition:

```bash
# In board scanner, after each status transition
echo '{"issue":'$ISSUE',"type":"'$TYPE'","from":"'$FROM'","to":"'$TO'","ts":"'$(date -u +%FT%TZ)'","hat":"'$HAT'"}' \
  >> team/metrics/transitions.jsonl
```

#### Acceptance Criteria

- **Given** the board scanner transitions an issue's status
  **When** the transition completes
  **Then** a JSONL entry is appended to `team/metrics/transitions.jsonl`

- **Given** a week of transition data exists
  **When** the weekly report generator runs
  **Then** a report is produced with cycle times, rejection rates, and throughput

- **Given** the retrospective skill is invoked
  **When** metrics data is available
  **Then** the retro includes data-driven observations and specific action items

---

## 4. Data Models

### 4.1 Architecture Layers Schema
```yaml
# YAML schema for architecture-layers.yml
type: object
properties:
  layers:
    type: array
    items:
      type: object
      properties:
        name: { type: string }
        description: { type: string }
        allowed_imports: { type: array, items: { type: string } }
  cross_cutting:
    type: array
    items:
      type: object
      properties:
        name: { type: string }
        description: { type: string }
        accessible_from: { type: array, items: { type: string } }
```

### 4.2 Golden Principles Schema
```yaml
# YAML schema for golden-principles.yml
type: object
properties:
  principles:
    type: array
    items:
      type: object
      properties:
        name: { type: string }
        description: { type: string }
        detection: { type: string }
        remediation: { type: string }
```

### 4.3 Trust Tier Schema
```yaml
# In ralph.yml
projects:
  <project-name>:
    autonomy:
      type: string
      enum: [supervised, guided, autonomous]
      default: supervised
```

### 4.4 Transition Log Entry
```json
{
  "issue": "integer — issue number",
  "type": "string — Epic|Task|Bug",
  "from": "string — previous status",
  "to": "string — new status",
  "ts": "string — ISO 8601 UTC timestamp",
  "hat": "string — hat that performed the transition"
}
```

---

## 5. Error Handling

### 5.1 Mechanical Enforcement Failures
- If a check script crashes (not just fails), the `dev_code_reviewer` hat reports the error and continues with remaining checks
- A crashed check does not block review — it's logged as a warning
- After 3 consecutive crashes, the check is flagged for human attention

### 5.2 Observability Stack Failures
- If the observability stack fails to start, the agent proceeds without it (degraded mode)
- A warning comment is posted on the issue
- Investigation and fix proceed without telemetry (current behavior)

### 5.3 Auto-Advance Failures
- If an auto-advance in `guided`/`autonomous` mode fails (e.g., status transition error), fall back to supervised behavior
- Post a comment explaining the fallback
- Retry on next scan cycle

### 5.4 Gardener Hat Failures
- If the gardener scan fails, it posts a failure comment and retries on the next cycle
- Does not block any other work
- Maximum 3 retries before flagging for human attention

---

## 6. Impact on Existing System

### 6.1 Modified Components

| Component | Change | Risk |
|-----------|--------|------|
| `ralph.yml` | Add `autonomy` field per project | Low — new field, backward compatible (defaults to `supervised`) |
| `po_reviewer` hat | Check autonomy tier before gating | Medium — core workflow change |
| `dev_code_reviewer` hat | Run executable invariant checks | Low — additive capability |
| `qe_verifier` hat | Run invariant checks as part of verification | Low — additive |
| `arch_planner` hat | Write execution plans to files | Low — additive |
| `arch_monitor` hat | Update plan files, move to completed | Low — additive |
| Board scanner skill | Log transitions to JSONL | Low — additive |

### 6.2 New Components

| Component | Type | Purpose |
|-----------|------|---------|
| `arch_gardener` hat | Hat | Periodic codebase cleanup and quality assessment |
| `architecture-layers.yml` | Config | Machine-readable layer definitions |
| `golden-principles.yml` | Config | Mechanical consistency rules |
| `checks/` scripts | Executable | Invariant check scripts |
| `plans/` directory | Knowledge | Execution plans and tech debt tracker |
| `metrics/` directory | Data | Transition logs and weekly reports |
| `QUALITY_SCORE.md` | Knowledge | Per-domain quality grading |

### 6.3 Backward Compatibility

- All changes are additive or opt-in
- Default `autonomy: supervised` preserves current behavior
- Existing invariant markdown files remain as reference documentation
- No existing hat behavior changes unless the project opts in

---

## 7. Security Considerations

### 7.1 Graduated Autonomy
- `autonomous` mode removes human gates — ensure agent review quality is sufficient before enabling
- Override mechanism (`Rejected:` comment) provides emergency brake
- Audit trail preserved via notification comments on every auto-advance
- Recommendation: start with `guided` on one low-risk project; monitor rejection rates before upgrading

### 7.2 Mechanical Enforcement
- Check scripts execute in CI/agent context — must not introduce command injection
- Scripts should be read-only (analyze, not modify) during the check phase
- Only the gardener hat's cleanup PRs should modify code

### 7.3 Metrics Data
- Transition logs contain issue numbers and status names, not sensitive data
- Stored in `team/` repo, same access control as other team artifacts

### 7.4 Observability Stack
- Per-worktree stacks are ephemeral — torn down after task completes
- No production data enters the local stack — only test/dev data
- Stack runs locally, not exposed to network

---

## 8. Implementation Phases

| Phase | Scope | Stories (est.) | Risk | Impact |
|---|---|---|---|---|
| 1 | Mechanical Enforcement | 3-4 | Low | High |
| 2 | Plans + Knowledge Structure | 2-3 | Low | Medium |
| 3 | Garbage Collection | 3-4 | Low | High |
| 4 | Metrics | 2-3 | Low | Medium |
| 5 | Graduated Autonomy | 2-3 | Medium | High |
| 6 | Application Legibility | 4-6 | Medium-High | High |

**Recommended order:** 1 → 2 → 3 → 4 → 5 → 6 (enforcement first, autonomy after quality infrastructure is in place)

---

## 9. Success Criteria

| Metric | Current | Target |
|---|---|---|
| Human gate wait time | Unknown | < 4 hours median |
| Rejection rate at code review | Unknown | < 15% |
| Invariant violations reaching review | Some (untracked) | Zero |
| Stale knowledge docs | Unknown | Detected within 1 week |
| Autonomy tier | `supervised` only | `guided` on >= 1 project |
| Cycle time trend | Untracked | Measured and improving |
| First-pass success rate | Unknown | > 70% |

---

## 10. References

- [OpenAI Harness Engineering (Feb 2026)](https://openai.com/index/harness-engineering/)
- [Agentic SDLC Blueprint — BayTech Consulting](https://www.baytechconsulting.com/blog/agentic-sdlc-ai-software-blueprint)
- [How Agentic AI Reshapes Engineering Workflows — CIO](https://www.cio.com/article/4134741/how-agentic-ai-will-reshape-engineering-workflows-in-2026.html)
- BotMinter PROCESS.md — current status graph and workflow conventions
- BotMinter team/invariants/ — current invariant definitions
