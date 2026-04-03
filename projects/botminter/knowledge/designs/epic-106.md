# Design: Transition BotMinter to Fully Agentic SDLC

**Epic:** #106
**Author:** bob (superman)
**Date:** 2026-04-03
**Status:** Draft (Revision 3 — addressing 6-point PR #107 rejection feedback)
**Reference:** [OpenAI Harness Engineering (Feb 2026)](https://openai.com/index/harness-engineering/)

---

## Rejection Feedback Addressed

This revision directly addresses the 6 rejection points from PR #107:

1. **Planning history corrected** — Phase 1 used `ralph plan` with AgentSOP framework, not ad-hoc development. Planning methodology was in place from the start; what's messy is the artifact trail, not the process itself.
2. **Scope explicitly defined** — Changes are BotMinter product features, delivered through the profile system. The current team dogfoods them. No ad-hoc team-repo edits.
3. **Existing ADRs integrated** — All 11 ADRs in `.planning/adrs/` are referenced where relevant. New decisions follow ADR-0001 format.
4. **Planning artifact mess addressed** — Section 5 proposes canonical artifact organization for the profile system.
5. **Knowledge directory purpose clarified** — Knowledge remains on-demand context. Designs, plans, and ADRs get their own profile-level directories.
6. **No upstream changes** — All configuration goes through `botminter.yml` (profile manifest) and profile directory structure. Zero changes to Ralph Orchestrator or `ralph.yml`.

---

## 1. Overview

### What This Epic Is

This is a **BotMinter product epic**. It adds features to BotMinter-the-framework that enable teams to run a fully agentic SDLC inspired by [OpenAI's Harness Engineering](https://openai.com/index/harness-engineering/) methodology. The `devguyio-agentic` team then **dogfoods** these features by adopting them through BotMinter's profile system.

### What This Epic Is NOT

- NOT ad-hoc changes to the current team repo
- NOT a divergence from the scrum-compact profile
- NOT changes to Ralph Orchestrator (upstream project)

### Why

OpenAI's Harness team insight: *"When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it legible and enforceable for the agent?'"*

BotMinter already has ~45% operational realization of Harness patterns (hat-based roles, agent-to-agent review, structured knowledge, rejection loops, board-driven dispatch). Six capability gaps remain. Closing them through the profile system means every BotMinter team benefits, not just ours.

### Delivery Model

```
BotMinter Codebase (projects/botminter/)
  └─ Profile enhancements (profiles/scrum-compact/)
       └─ Profile extraction (bm init / bm hire)
            └─ Team repo gets new capabilities
                 └─ Agents use them immediately
```

Every feature ships in the scrum-compact profile. No separate "agentic-harness" profile is needed initially — the existing profile gains these capabilities as opt-in features. If the feature set diverges enough, a new profile can be forked later using BotMinter's existing profile infrastructure.

---

## 2. Architecture

### 2.1 BotMinter Development History

BotMinter evolved through four methodology phases. Understanding this is essential for honest gap analysis.

#### Phase 1: Ralph-Orchestrated Development (v0.01–v0.05, Feb 2026)

The foundational CLI and workspace model were built using **Ralph Orchestrator with `ralph plan` and the AgentSOP framework**. Planning methodology was in place from the start — `ralph plan` created specs based on AgentSOP, providing structured planning for each development cycle. While not all planning artifacts survived cleanly (some are scattered or in non-standard locations), the development was methodologically sound, not ad-hoc.

**What was built:** Core `bm` CLI, profile system, workspace model, GitHub coordination, two-layer runtime, E2E test harness with `libtest-mimic`.

**Maturity:** High — 471 tests by end of this phase. Core commands battle-tested through real use.

#### Phase 2: GSD Framework (v0.06–v0.07, Mar 2026)

[GSD (Get Shit Done)](https://github.com/gsd-build/get-shit-done) introduced milestone decomposition, `PLAN.md` files, five-step CLI-agent handshake, and verification loops. Note: the retrospective records that *"Phases 2-4 had no GSD plans on disk: These phases were implemented before GSD was initialized"* — meaning GSD was adopted mid-milestone, not from v0.06's start.

**What was built:** Coding-agent-agnostic architecture, composable skills, `bm chat`/`bm minty`, bridge abstraction, profile integration for bridges.

**Maturity:** Medium-High — 576 tests by end of v0.07. Bridge lifecycle validated via e2e and exploratory tests.

#### Phase 3: Agent SOP / Ralph Hat System (evolving)

Ralph's hat definitions were progressively formalized into structured SOPs. Each hat's `instructions` block in the profile's `ralph.yml` functions as a codified SOP. This is when informal practices became machine-readable hat instructions.

**What was built:** Board scanner, 18 hat definitions, event-driven dispatch, status graph (32 statuses), evidence gates, human review gates.

**Maturity:** Medium — functional for weeks, some hats more exercised than others.

#### Phase 4: A-Team / Dogfooding (Late Mar 2026–present)

The `devguyio-agentic` team was created using BotMinter's own `bm init` workflow, running scrum-compact, with superman-bob developing BotMinter itself.

**What it validates:** Full issue lifecycle, hat switching, human gates, board dispatch, knowledge resolution.

**Maturity:** Early — running approximately one week. Design and triage exercised; full TDD story cycle not yet validated end-to-end.

#### Planning Artifacts: Current State

The planning landscape reflects this evolution. Multiple techniques were tried, resulting in artifacts scattered across different structures:

| Location | Contents | Origin |
|----------|----------|--------|
| `projects/botminter/.planning/adrs/` | 11 ADRs (7 accepted, 3 proposed) | AgentSOP/Phase 1-2 |
| `projects/botminter/.planning/phases/` | GSD phase plans (07-10) | GSD/Phase 2 |
| `projects/botminter/.planning/milestones/` | Milestone plans (v0.06) | GSD/Phase 2 |
| `projects/botminter/.planning/specs/` | Formal specifications | AgentSOP/Phase 1-2 |
| `projects/botminter/specs/` | Feature specs (github-app-identity, team-design-skills) | Phase 3 |
| `team/projects/botminter/knowledge/designs/` | Design docs (this file) | Phase 4/A-Team |
| `team/agreements/decisions/` | Empty (scaffolded) | Phase 4/A-Team |

This fragmentation is acknowledged as a problem. Section 5 addresses artifact organization.

### 2.2 Existing ADRs

The 11 existing ADRs (`.planning/adrs/`) inform this design:

| ADR | Title | Relevance to This Epic |
|-----|-------|----------------------|
| 0001 | ADR Format: Spotify-style with Anti-patterns | New decisions in this epic follow this format |
| 0002 | Shell Script Bridge with YAML Manifest | Pattern reference for executable invariant checks (shell scripts + YAML config) |
| 0004 | Scenario-Based E2E Tests | Informs test approach for new features |
| 0005 | E2E Test Environment and Isolation | Informs dev-boot and observability stack isolation |
| 0006 | Directory Modules Only | Architecture layer checks must respect this convention |
| 0007 | Domain Modules and Command Layering | Architecture layer definitions derive from this |
| 0008 | Formation as Deployment Strategy | Dev-boot scripts align with the formation abstraction |
| 0009 | Exploratory Integration Tests | Gardener checks complement (not replace) exploratory tests |

ADRs 0003, 0010, 0011 are not directly affected by this epic.

### 2.3 The Six Gaps (as BotMinter Features)

```
Gap                              BotMinter Feature
---                              -----------------
Prose invariants (honor system)  → Executable invariant checks in profiles
No telemetry / app boot          → Dev environment bootstrapping in profiles
No automated cleanup             → Gardener hat + golden principles in profiles
No execution plans / messy docs  → Canonical artifact directories in profiles
3 hard human gates               → Graduated autonomy config in botminter.yml
No metrics                       → Transition metrics infrastructure in profiles
```

Each gap maps to a BotMinter product feature that ships through the profile system and is dogfooded by this team.

### 2.4 Where Changes Go

| Change Type | Where | Example |
|-------------|-------|---------|
| Profile directory templates | `profiles/scrum-compact/` | New `checks/`, `plans/`, `metrics/` dirs |
| Profile manifest schema | `botminter.yml` + `manifest.rs` | Add `autonomy` field |
| Hat definitions | `profiles/scrum-compact/roles/superman/ralph.yml` | Add gardener hat |
| CLI features (if needed) | `crates/bm/src/` | `bm check` command |
| Team repo (via extraction) | Extracted by `bm init` / `bm hire` | Teams get new dirs automatically |
| ADRs for this epic's decisions | `projects/botminter/.planning/adrs/` | Follow ADR-0001 format |

**Nothing touches Ralph Orchestrator.** Ralph reads what the profile provides.

---

## 3. Components and Interfaces

### 3.1 Feature 1: Executable Invariant Checks

#### Problem
Invariants are markdown documents in `team/invariants/`. Agents are *instructed* to follow them. Nothing prevents violations from reaching code review.

#### Scope: Profile Enhancement
The scrum-compact profile gains an executable invariant check system. Checks are shell scripts in the profile's `invariants/checks/` directory, extracted to the team repo on `bm init`. Hats already in the profile (`dev_code_reviewer`, `qe_verifier`) gain check-running steps in their instructions.

#### Design

**Profile-side (what ships in `profiles/scrum-compact/`):**

```
profiles/scrum-compact/
  invariants/
    checks/                        # Executable checks (NEW)
      check-test-coverage.sh       # Minimum coverage thresholds
      check-naming-conventions.sh  # Validates naming patterns
      README.md                    # How to add project-specific checks
    code-review-required.md        # Existing prose invariant
    test-coverage.md               # Existing prose invariant
```

**Project-side (added by teams to their project config):**

```
team/projects/<project>/invariants/
  architecture-layers.yml          # Project-specific layer definitions
  checks/                          # Project-specific checks
    check-architecture-layers.sh   # Validates import directions
```

Architecture layers follow ADR-0007's domain-command layering. The check script validates that command modules don't import from other command modules, and domain modules respect the dependency hierarchy defined in the project's `architecture-layers.yml`.

**Check script contract:**
- Exit 0 on pass, 1 on failure
- On failure, print agent-readable remediation (following Harness's pattern):
  ```
  VIOLATION: <what happened>
  RULE: <which rule>
  REMEDIATION: <what to do>
  REFERENCE: <path to invariant>
  ```

**Hat integration (profile-side, in role's `ralph.yml`):**
- `dev_code_reviewer` instructions: "Before reviewing, run all scripts in `team/invariants/checks/` and `team/projects/<project>/invariants/checks/`. If any check fails, reject to `dev:implement` with the check output."
- `qe_verifier` instructions: Same check execution as part of verification.

**Relationship to existing invariants:**
- Prose invariants (`*.md`) remain as human-readable reference documentation
- Executable checks (`checks/*.sh`) are the mechanical enforcement layer
- Both co-exist in the same directory; hats read prose for context, run scripts for enforcement

#### Acceptance Criteria

- **Given** a code change violating an architecture layer rule
  **When** `dev_code_reviewer` runs invariant checks
  **Then** the check fails with agent-readable remediation and the story is rejected to `dev:implement`

- **Given** a code change passing all checks
  **When** `dev_code_reviewer` runs invariant checks
  **Then** all checks pass and review proceeds normally

- **Given** a new check script added to `checks/`
  **When** subsequent code reviews run
  **Then** the new check is automatically included (convention-over-configuration via directory scan)

---

### 3.2 Feature 2: Application Legibility (Phased)

#### Problem
QE investigates bugs by reading code. No telemetry, no app boot, no runtime observation.

#### Scope: Profile Enhancement (phased)
Legibility features are introduced in phases of increasing complexity. Phase A is profile-level. Phases B-D are project-specific and optional.

#### Design

**Phase A: Structured Test Output (profile-level)**

The profile defines a test output format invariant:

```yaml
# profiles/scrum-compact/invariants/test-output-format.yml
requirements:
  - format: structured_json
  - fields: [test_name, status, duration_ms, error_message, file_path]
```

Hats (`qe_investigator`, `dev_implementer`) parse structured output to navigate directly to failures. This is a convention the profile establishes — enforcement is via the prose invariant and code reviewer checks.

**Phase B: Dev-Boot Scripts (project-specific, optional)**

Projects that have a runnable app define boot/teardown scripts:

```yaml
# team/projects/<project>/knowledge/dev-environment.yml
boot:
  script: ./scripts/dev-boot.sh
  health_check: http://localhost:${PORT}/health
  teardown: ./scripts/dev-teardown.sh
  isolation: worktree
```

This aligns with ADR-0008 (Formation as Deployment Strategy) — dev-boot uses the formation abstraction for local deployment.

**Phase C: Observability Stack (project-specific, optional)**

Ephemeral per-worktree observability. Deferred until Phase B is validated.

**Phase D: UI Introspection (web projects only, optional)**

Chrome DevTools Protocol integration. Deferred until applicable project exists.

#### Acceptance Criteria

- **Given** a test suite runs during `dev:implement`
  **When** tests complete
  **Then** output is structured JSON that agents can parse for specific failure details

- **Given** a project with `dev-environment.yml` configured
  **When** `dev_implementer` works in a worktree
  **Then** the app boots in isolation and the agent can validate behavior

---

### 3.3 Feature 3: Garbage Collection

#### Problem
No automated cleanup, quality grading, or stale-doc detection.

#### Scope: Profile Enhancement
A new `arch_gardener` hat is added to the superman role definition in the scrum-compact profile.

#### Design

**Gardener Hat (profile-side, in `roles/superman/ralph.yml`):**

```yaml
arch_gardener:
  purpose: "Periodic codebase cleanup and quality assessment"
  triggers: ["gardener.scan"]
  publishes: ["gardener.scan.done"]
  instructions: |
    1. Scan codebase against golden principles (team/projects/<project>/invariants/golden-principles.yml)
    2. Run all invariant checks, note any new violations
    3. Check doc freshness (git log dates vs knowledge file dates)
    4. Update team/projects/<project>/knowledge/QUALITY_SCORE.md
    5. Open targeted refactoring issues for drift items
```

**Golden Principles (profile-side, extracted to team repo):**

```yaml
# profiles/scrum-compact/invariants/golden-principles.yml
principles:
  - name: shared-utilities-over-hand-rolled
    description: "Prefer shared utility packages over hand-rolled helpers"
    detection: "Find functions with >80% similarity across modules"
    remediation: "Extract to shared utility, update all call sites"
  - name: no-dead-code
    description: "Remove unused functions, imports, and variables"
    detection: "Static analysis for unreachable code"
    remediation: "Delete the dead code"
  - name: consistent-error-handling
    description: "Use the project's error handling pattern consistently"
    detection: "Find error handling that doesn't match project pattern"
    remediation: "Refactor to use standard error pattern"
```

**Quality Score (project-level knowledge):**

The gardener maintains `team/projects/<project>/knowledge/QUALITY_SCORE.md` with per-domain grades (A-F), test coverage, invariant compliance, and doc freshness. Updated on each gardener scan.

**Triggering:** The board scanner dispatches `gardener.scan` on a configurable schedule (e.g., after every N scan cycles, or when explicitly invoked). This is profile configuration, not a Ralph Orchestrator change.

#### Acceptance Criteria

- **Given** the gardener hat runs its scan
  **When** it detects duplicated utility code
  **Then** it opens a refactoring issue describing the duplication and remediation

- **Given** a knowledge file references a renamed function
  **When** the doc-gardening scan runs
  **Then** a fix-up issue is opened

- **Given** the gardener completes its scan
  **When** it updates QUALITY_SCORE.md
  **Then** the score reflects current coverage, compliance, and doc freshness

---

### 3.4 Feature 4: Plans as First-Class Artifacts

#### Problem
Design docs exist as files. Story breakdowns exist only in issue comments. No execution plans. Planning artifacts are fragmented across multiple locations and methodologies (AgentSOP specs, GSD plans, project specs, team designs).

#### Scope: Profile Enhancement + Artifact Organization

This feature serves double duty:
1. Add execution plan infrastructure to the profile
2. Establish canonical artifact organization that cleans up the mess

#### Design

**Profile Directory Template (what `bm init` extracts):**

The profile template for the `projects/<project>/` directory gains new subdirectories:

```
team/projects/<project>/
  knowledge/                        # On-demand context extras (EXISTING purpose preserved)
    designs/                        # Design documents for epics
    QUALITY_SCORE.md                # From Feature 3
  plans/                            # Execution tracking (NEW)
    active/                         # In-progress epic execution plans
    completed/                      # Archived after epic completion
  invariants/                       # Hard constraints (EXISTING purpose preserved)
    checks/                         # Executable checks (from Feature 1)
    architecture-layers.yml         # Project-specific layers
    golden-principles.yml           # From Feature 3
```

**Key design decision — What goes where:**

| Artifact Type | Location | Rationale |
|---------------|----------|-----------|
| Knowledge (conventions, protocols, references) | `knowledge/` | On-demand context extras — original purpose preserved |
| Design docs (epic designs) | `knowledge/designs/` | Designs are context for implementation work |
| Execution plans (progress tracking) | `plans/active/` or `plans/completed/` | Plans are living documents that track execution state |
| Invariants (hard constraints) | `invariants/` | Machine-readable and prose constraints |
| ADRs (architecture decisions) | Project repo `.planning/adrs/` | ADRs belong with the codebase they govern (per ADR-0001) |
| Team agreements (decisions, retros, norms) | `agreements/` | Team-level governance (per team-agreements convention) |

**Why knowledge/ is correct for designs:** Designs are reference context that hats load on demand during implementation. They are not governance documents (that's `invariants/`) or execution state (that's `plans/`). The operator's concern that knowledge was meant for "on demand context extras" is exactly what designs are — context loaded by the architect, planner, and implementer hats as needed.

**Why ADRs stay in the project repo:** ADRs document *codebase* decisions. They live with the code in `.planning/adrs/` following the established ADR-0001 format. They don't belong in the team repo because they're project-specific architectural artifacts, not team governance.

**Execution Plan Format:**

```markdown
# Execution Plan: Epic #<number> — <title>

## Status: In Progress | Completed

## Stories
| # | Title | Status | Completed |
|---|-------|--------|-----------|

## Decision Log
| Date | Decision | Rationale |
|------|----------|-----------|

## Progress Notes
- <date>: <event>
```

**Hat Integration (profile-side):**
- `arch_planner` writes execution plans to `team/projects/<project>/plans/active/`
- `arch_monitor` updates plan progress as stories complete
- On epic completion, plan moves to `plans/completed/`

#### Acceptance Criteria

- **Given** `arch_planner` produces a story breakdown
  **When** the breakdown is approved
  **Then** an execution plan exists in `plans/active/` with the story list

- **Given** a story reaches `done`
  **When** `arch_monitor` scans the epic
  **Then** the execution plan's story table is updated

- **Given** all stories in an epic reach `done`
  **When** the epic is accepted
  **Then** the plan moves from `plans/active/` to `plans/completed/`

---

### 3.5 Feature 5: Graduated Autonomy

#### Problem
3 hard human gates. Agent cannot proceed without explicit human approval at design review, plan review, and acceptance.

#### Scope: BotMinter Profile Manifest Enhancement

Autonomy configuration goes in `botminter.yml` — the BotMinter profile manifest. **NOT in `ralph.yml`** (that's Ralph Orchestrator, an upstream project we consume). The profile extraction pipeline reads the autonomy setting from `botminter.yml` and configures the hat behavior accordingly.

#### Design

**Profile Manifest Extension:**

```yaml
# profiles/scrum-compact/botminter.yml (new field)
autonomy:
  default: supervised              # Default for new teams using this profile
  tiers:
    supervised:
      description: "3 human gates: design-review, plan-review, accept"
      human_gates: [po:design-review, po:plan-review, po:accept]
    guided:
      description: "1 human gate: accept only"
      human_gates: [po:accept]
      auto_advance_after: lead_review  # Auto-advance design/plan after lead review
    autonomous:
      description: "0 human gates, async notification"
      human_gates: []
      notification: true           # Post notification comments on auto-advance
```

**Implementation in `manifest.rs`:**

The `ProfileManifest` struct gains an `autonomy` field. During extraction, the autonomy setting is written to a team-repo-level config file that hats can read at runtime (e.g., `team/.botminter-config.yml`).

**Hat Behavior (profile-side, in `roles/superman/ralph.yml`):**

The `po_reviewer` hat instructions check the autonomy tier:
- `supervised`: Current behavior — post review request, wait for human comment
- `guided`: Auto-advance design and plan reviews after lead approval. Wait for human only at `po:accept`. Post notification comment on each auto-advance.
- `autonomous`: Auto-advance all gates. Post notification comments. Human can override by commenting `Rejected: <feedback>` at any time.

**Override Mechanism:**
- Human comments `Rejected: <feedback>` → reverts auto-advance
- Human comments `Hold` → pauses auto-advances for that issue
- Human changes autonomy setting → requires profile re-sync (`just sync` or re-extraction)

**Why botminter.yml, not ralph.yml:** Ralph Orchestrator is an upstream project. Its `ralph.yml` defines the event loop, hats, skills, and iteration config. Autonomy is a BotMinter-level policy that determines how hats behave — it's a profile concern, not an orchestrator concern. The profile's hat instructions read the autonomy setting and adjust their behavior. Ralph just runs whatever instructions the hat provides.

#### Acceptance Criteria

- **Given** a project with `autonomy: guided` in `botminter.yml`
  **When** lead review approves a design doc
  **Then** `po:design-review` auto-advances with a notification comment

- **Given** `autonomy: guided`
  **When** an epic reaches `po:accept`
  **Then** the agent waits for human comment (same as supervised)

- **Given** a human comments `Rejected: <feedback>` on an auto-advanced issue
  **When** the agent scans the issue
  **Then** the status reverts and feedback is processed

---

### 3.6 Feature 6: Metrics and Feedback Loops

#### Problem
No cycle-time tracking, quality metrics, or data-driven retrospectives. `poll-log.txt` exists for audit but provides no analytics.

#### Scope: Profile Enhancement

The profile gains metrics infrastructure — directory templates, transition logging instructions for the board scanner, and a report generation capability.

#### Design

**Profile Directory Template:**

```
team/metrics/                       # NEW directory from profile
  transitions.jsonl                 # Append-only transition log
  reports/                          # Weekly auto-generated reports
```

**Transition Logging:**

The board scanner skill (auto-injected, not a hat) appends a JSONL entry after each status transition:

```jsonl
{"issue":106,"type":"Epic","from":"po:triage","to":"po:backlog","ts":"2026-04-03T15:00:00Z","hat":"po_backlog"}
```

This is an additive change to the board-scanner skill instructions in the profile. The skill already posts comments and logs to `poll-log.txt`; adding JSONL append is minimal.

**Derived Metrics:**

| Metric | Measures | Target |
|--------|----------|--------|
| Design cycle time | `arch:design` → `po:ready` | Trending down |
| Implementation cycle time | `dev:implement` → `qe:verify` | Trending down |
| Human gate wait time | Time in review statuses | < 4 hours |
| Rejection rate per gate | % rejections | < 15% |
| First-pass rate | Stories reaching `done` without rejection | > 70% |
| Throughput | Issues completed per week | Trending up |

**Weekly Report:**

A `cw_writer` hat task (or gardener hat extension) generates a weekly summary from `transitions.jsonl`, stored in `team/metrics/reports/`. The existing `retrospective` skill receives metrics as input for data-driven retros.

#### Acceptance Criteria

- **Given** the board scanner transitions an issue's status
  **When** the transition completes
  **Then** a JSONL entry is appended to `team/metrics/transitions.jsonl`

- **Given** a week of transition data exists
  **When** the weekly report generator runs
  **Then** a report shows cycle times, rejection rates, and throughput

- **Given** the retrospective skill is invoked
  **When** metrics data is available
  **Then** the retro includes data-driven observations

---

## 4. Data Models

### 4.1 Architecture Layers (project-specific YAML)
```yaml
layers:
  - name: types
    allowed_imports: []
  - name: config
    allowed_imports: [types]
  - name: domain            # Per ADR-0007
    allowed_imports: [types, config]
  - name: command            # Per ADR-0007
    allowed_imports: [types, config, domain]
cross_cutting:
  - name: providers
    accessible_from: [domain, command]
```

### 4.2 Golden Principles (profile-level YAML)
```yaml
principles:
  - name: string
    description: string
    detection: string
    remediation: string
```

### 4.3 Autonomy Config (in botminter.yml)
```yaml
autonomy:
  default: supervised | guided | autonomous
  tiers:
    <tier-name>:
      description: string
      human_gates: [status-name, ...]
      auto_advance_after: string  # optional
      notification: boolean       # optional
```

### 4.4 Transition Log Entry
```json
{
  "issue": "integer",
  "type": "Epic | Task | Bug",
  "from": "string (status)",
  "to": "string (status)",
  "ts": "ISO 8601 UTC",
  "hat": "string (hat name)"
}
```

---

## 5. Error Handling

### 5.1 Check Script Failures
- Script crashes (not fails) → logged as warning, review continues with remaining checks
- 3 consecutive crashes → check flagged for human attention
- A crashed check does not block review

### 5.2 Observability Stack Failures
- Stack fails to start → agent proceeds without it (degraded mode)
- Warning comment posted on issue

### 5.3 Auto-Advance Failures (Graduated Autonomy)
- Status transition error during auto-advance → fall back to supervised behavior
- Post comment explaining the fallback, retry on next scan cycle

### 5.4 Gardener Hat Failures
- Scan failure → retry on next cycle, max 3 retries before flagging
- Does not block other work

---

## 6. Impact on Existing System

### 6.1 BotMinter Codebase Changes

| Component | Change | Risk |
|-----------|--------|------|
| `profiles/scrum-compact/invariants/` | Add `checks/` dir and golden-principles.yml | Low — additive |
| `profiles/scrum-compact/botminter.yml` | Add `autonomy` field | Low — new field, defaults to `supervised` |
| `profiles/scrum-compact/roles/superman/ralph.yml` | Add `arch_gardener` hat, update reviewer hat instructions | Medium — hat changes |
| `crates/bm/src/profile/manifest.rs` | Parse `autonomy` field | Low — new optional field |
| `crates/bm/src/profile/extraction.rs` | Extract new directories (`plans/`, `metrics/`, `checks/`) | Low — additive extraction |
| Board scanner skill | Add transition JSONL logging | Low — additive |

### 6.2 New Components

| Component | Ships In | Purpose |
|-----------|----------|---------|
| `checks/` directory template | Profile | Executable invariant checks |
| `golden-principles.yml` | Profile | Mechanical consistency rules |
| `arch_gardener` hat | Profile (role ralph.yml) | Periodic cleanup and quality scoring |
| `plans/` directory template | Profile | Execution plan tracking |
| `metrics/` directory template | Profile | Transition logs and reports |
| `QUALITY_SCORE.md` | Generated by gardener | Per-domain quality grading |
| `autonomy` config | Profile manifest | Graduated autonomy tiers |

### 6.3 Backward Compatibility

- All changes are additive or opt-in
- Default `autonomy: supervised` preserves current behavior
- Existing teams get new directories on next `bm init` / profile re-extraction
- No behavior changes unless explicitly configured
- Existing prose invariants remain alongside executable checks

### 6.4 What Does NOT Change

- Ralph Orchestrator (`ralph.yml` schema, `ralph emit`, `ralph plan`)
- GitHub Projects v2 integration (same statuses, same board structure)
- Human review gate behavior (unless autonomy tier is changed)
- Existing knowledge hierarchy and resolution order
- Existing 11 ADRs (remain in `.planning/adrs/`, referenced not modified)

---

## 7. Security Considerations

### 7.1 Graduated Autonomy
- `autonomous` mode removes all human gates — ensure agent review quality before enabling
- Override mechanism (`Rejected:` comment) provides emergency brake
- Audit trail via notification comments on every auto-advance
- Recommendation: validate `guided` on low-risk work before upgrading to `autonomous`
- Autonomy setting requires profile re-sync to change — cannot be modified by agents at runtime

### 7.2 Executable Invariant Checks
- Check scripts execute in agent context — must not introduce command injection
- Scripts are read-only (analyze, not modify) during the check phase
- Only gardener hat cleanup PRs modify code
- Check scripts are version-controlled in the profile/team repo
- Per ADR-0002's pattern: scripts are declarative with YAML manifests, not arbitrary executables

### 7.3 Metrics Data
- Transition logs contain issue numbers and status names only — no sensitive data
- Stored in `team/` repo with same access control as other team artifacts

### 7.4 Observability Stack (Phase C, deferred)
- Per-worktree, ephemeral, torn down after task
- No production data — only test/dev data
- Local only, not network-exposed

---

## 8. Implementation Phases

| Phase | Scope | BotMinter Changes | Risk | Impact |
|-------|-------|-------------------|------|--------|
| 1 | Executable Invariant Checks | Profile `checks/` dir, hat instruction updates | Low | High |
| 2 | Plans + Artifact Organization | Profile `plans/` dir template, hat instructions | Low | Medium |
| 3 | Garbage Collection | `arch_gardener` hat, golden principles, quality score | Low | High |
| 4 | Metrics Infrastructure | Profile `metrics/` dir, board scanner JSONL | Low | Medium |
| 5 | Graduated Autonomy | `botminter.yml` schema, `manifest.rs`, hat logic | Medium | High |
| 6 | Application Legibility (Phases A-D) | Test output invariant, dev-boot, observability | Medium-High | High |

**Order:** 1 → 2 → 3 → 4 → 5 → 6

Enforcement and artifact structure first (low risk, immediate value). Autonomy only after quality infrastructure is proven. Observability last (highest complexity, requires per-project setup).

Each phase produces an ADR (following ADR-0001 format) documenting the decisions made during implementation.

---

## 9. Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| Invariant violations reaching code review | Untracked | Zero (caught by checks) |
| Human gate wait time | Unknown | < 4 hours median |
| Rejection rate at code review | Unknown | < 15% |
| Stale knowledge docs | Unknown | Detected within 1 week |
| Autonomy tier | `supervised` only | `guided` on this project |
| Cycle time trend | Untracked | Measured and trending down |
| First-pass success rate | Unknown | > 70% |

---

## 10. References

- [OpenAI Harness Engineering (Feb 2026)](https://openai.com/index/harness-engineering/)
- BotMinter ADR-0001: ADR Format (`.planning/adrs/0001-adr-process.md`)
- BotMinter ADR-0002: Shell Script Bridge pattern (`.planning/adrs/0002-bridge-abstraction.md`)
- BotMinter ADR-0007: Domain Modules and Command Layering (`.planning/adrs/0007-domain-command-layering.md`)
- BotMinter ADR-0008: Formation as Deployment Strategy (`.planning/adrs/0008-team-runtime-architecture.md`)
- BotMinter PROCESS.md — current status graph and workflow conventions
- BotMinter `profiles/scrum-compact/botminter.yml` — profile manifest schema
