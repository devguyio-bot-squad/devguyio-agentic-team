---
type: design
status: draft
epic: "106"
revision: 1
created: 2026-04-04
updated: 2026-04-04
author: bob (superman)
sub_epics:
  - "114"
  - "116"
  - "117"
  - "118"
  - "119"
  - "120"
---

# Epic #106: Transition BotMinter to Fully Agentic SDLC

## 1. Overview

BotMinter currently operates at Tier 2 (supervised agentic SDLC): the agent wears all hats and self-transitions through the issue lifecycle, but three human gates (`po:design-review`, `po:plan-review`, `po:accept`) block unconditionally until a human responds. Every design, plan, and acceptance requires manual approval regardless of risk, novelty, or track record.

This creates two systemic problems:

1. **Throughput bottleneck.** The agent produces designs in hours; the single human reviews on a different cadence. Five designs (#114-#118) parked at `po:design-review` simultaneously demonstrates the asymmetry — the agent is idle while reviews accumulate.

2. **Missing enforcement infrastructure.** When the agent does work, quality is enforced by prose instructions and judgment. ADR-0007 prohibits `eprintln!` in domain modules; 9 violations exist undetected. Plans fragment across GitHub comments and ephemeral context. No quality metrics are collected. The agent "tries harder" instead of having systematic feedback on what works.

This epic transitions BotMinter from Tier 2 to Tier 3 (fully agentic SDLC) by closing six infrastructure gaps, each addressed by an independently-designed sub-epic.

### Harness Engineering Foundation

> "When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it both legible and enforceable for the agent?'"

The six sub-epics map directly to Harness Engineering principles:

| Gap | Harness Principle | Sub-Epic |
|-----|-------------------|----------|
| Rules enforced by prose only | Mechanical enforcement via custom linters | #114 Executable Invariant Checks |
| Plans lost across context/hats | Structured, inspectable agent output | #116 Plans as First-Class Artifacts |
| No quality data for agents | Automated metrics feeding agent prompts | #117 Metrics and Feedback Loops |
| Codebase entropy accumulates | Background maintenance automation | #118 Automated Codebase Gardening |
| Human gates are unconditional | Earned autonomy through demonstrated reliability | #119 Graduated Autonomy for Human Gates |
| Application opaque to agents | Agent-readable interfaces for every surface | #120 Application Legibility |

### Sub-Epics

| # | Title | Phase | Dependencies | Status |
|---|-------|-------|-------------|--------|
| #114 | Executable Invariant Checks | 1 | None | Design complete |
| #116 | Plans as First-Class Artifacts | 1 | None | Design complete |
| #117 | Metrics and Feedback Loops | 1 | None | Design complete |
| #118 | Automated Codebase Gardening | 2 | #114, #117 | Design complete |
| #119 | Graduated Autonomy for Human Gates | 2 | #114, #117 | Design complete |
| #120 | Application Legibility for Agent Development | 3 | None (benefits from all) | Design complete |

### Scope

This parent epic coordinates the six sub-epics. It defines:
- Phased delivery order with dependency gates
- Cross-cutting integration points between sub-epics
- Overall acceptance criteria for the Tier 2 → Tier 3 transition
- Delivery strategy (each sub-epic is designed, planned, implemented, and verified independently)

This design does NOT duplicate the contents of the sub-epic designs. Each sub-epic design (at `team/projects/botminter/knowledge/designs/epic-{114,116,117,118,119,120}.md`) is the authoritative source for its scope, architecture, components, and acceptance criteria.

### Out of Scope

- Individual sub-epic implementation details (see each sub-epic's design)
- Modifying the status graph or adding new workflow statuses
- Multi-team coordination (BotMinter has one team member)
- External monitoring dashboards or SaaS integrations
- Backward compatibility (pre-alpha — per operator directive)

---

## 2. Architecture

### 2.1 BotMinter System Context

BotMinter is a multi-binary Rust application:
- **CLI** (`bm`) — 22+ operator-facing subcommands
- **Agent CLI** (`bm-agent`) — agent-consumed tools (3 command groups: `inbox`, `claude`, `loop`)
- **HTTP Daemon** (`daemon/`) — Axum background process with JSON API (9 source files)
- **Web Console** (`web/`) — Axum routes + SvelteKit SPA via `rust-embed` (9 source files)
- **16 domain modules** under `crates/bm/src/` following ADR-0006 and ADR-0007
- **11 ADRs**, **11 project invariants**, **4 test tiers** (unit, integration, e2e, exploratory)

The team repo (`team/`) is the coordination control plane — knowledge, invariants, hat configurations, and workflow artifacts. The agent's workspace has the project repo at `./` with team at `team/`.

### 2.2 Transition Architecture

The six sub-epics layer on top of the existing supervised SDLC without replacing it. Each adds a capability; none removes an existing one. The supervised mode remains the default — Tier 3 is earned, not assumed.

```
Phase 1 — Foundation (parallel, no dependencies)
┌────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│ #114 Executable    │  │ #116 Plans as       │  │ #117 Metrics and    │
│ Invariant Checks   │  │ First-Class         │  │ Feedback Loops      │
│                    │  │ Artifacts            │  │                     │
│ Check scripts      │  │ Plan frontmatter    │  │ Metric collectors   │
│ Check runner       │  │ Breakdown files     │  │ JSONL metric store  │
│ Hat integration    │  │ Impl plan files     │  │ Hat feedback loops  │
│ CI gate            │  │ 6 hat updates       │  │ Quality reports     │
└────────┬───────────┘  └─────────────────────┘  └──────────┬──────────┘
         │                                                   │
         │  check runner + structured output                 │  quality data
         │                                                   │
         ▼                                                   ▼
Phase 2 — Automation (parallel, depends on Phase 1)
┌────────────────────┐                          ┌─────────────────────┐
│ #118 Automated     │                          │ #119 Graduated      │
│ Codebase Gardening │                          │ Autonomy for        │
│                    │                          │ Human Gates         │
│ Lint/fmt scanners  │                          │ Trust tiers         │
│ Dep audit scanners │                          │ Risk classifier     │
│ Auto-fix PRs       │                          │ Gate policy engine  │
│ Gardener hat       │                          │ Reversal cascade    │
└────────────────────┘                          └─────────────────────┘

Phase 3 — Capstone (least coupled, benefits from all)
┌────────────────────────────────────────────────────────────────────┐
│ #120 Application Legibility for Agent Development                  │
│                                                                    │
│ bm-agent project describe / env check / test summary               │
│ Structured error context (categories + remediation)                │
│ Dev boot protocol                                                  │
│ CLAUDE.md maintenance convention                                   │
└────────────────────────────────────────────────────────────────────┘
```

### 2.3 Phased Delivery Strategy

**Phase 1 — Foundation** (#114, #116, #117): Three sub-epics with no inter-dependencies, delivering the infrastructure that Phase 2 builds on. Can be developed fully in parallel. Each goes through the full lifecycle independently: design → plan → stories → implement → verify → accept.

**Phase 2 — Automation** (#118, #119): Two sub-epics that require Phase 1 outputs. #118 uses the check runner from #114 and metrics from #117 for gardening scanning. #119 uses check results from #114 as a risk signal and quality data from #117 for trust decisions. Both degrade gracefully if Phase 1 components are partially deployed (documented in each design's error handling).

**Phase 3 — Capstone** (#120): The least-coupled sub-epic. No hard dependencies on Phase 1 or 2 — it extends `bm-agent` with structured output commands, which benefits from but does not require the other sub-epics. Placed last because it modifies the most application code (new Rust modules, new CLI commands, structured error type).

**Within-phase parallelism:** Phase 1's three sub-epics can be implemented by the single agent sequentially (one active story at a time per the board scanner dispatch model). "Parallel" means no dependency ordering — any can go first. The board scanner's priority table determines the actual execution order.

### 2.4 Dependency Graph

```
#114 ────────┐
             ├──► #118 (needs check runner + metrics data)
#117 ────────┤
             ├──► #119 (needs check results + quality signals)
#117 ────────┘

#116 ────────── (independent — consumed by downstream hats after delivery)

#120 ────────── (independent — benefits from all, requires none)
```

Dependency relationships are soft at Phase 2: both #118 and #119 document fallback behavior when #114 or #117 are not yet deployed. This means Phase 2 work could start before Phase 1 is fully complete, but with reduced functionality (no check script integration, no metrics-based risk assessment). The recommended path is to complete Phase 1 before starting Phase 2.

---

## 3. Components and Interfaces

### 3.1 Cross-Cutting Integration Points

The six sub-epics interact through defined interfaces, not ad-hoc coupling:

| Producer | Consumer | Interface | What Flows |
|----------|----------|-----------|------------|
| #114 Check Runner | #118 Gardening | `run-checks.sh` exit code + `VIOLATION` output | Whether invariant checks pass before gardening commits |
| #114 Check Runner | #119 Risk Classifier | `run-checks.sh` exit code | `check_scripts_pass` signal for risk assessment |
| #117 Build-Test Collector | #119 Risk Classifier | `build-test.jsonl` entries | Rejection rate and quality trends for trust decisions |
| #117 Workflow Collector | Gardening Reports | `workflow.jsonl` entries | Cycle time data for quality summaries |
| #116 Plan Artifacts | #119 Risk Classifier | Design doc frontmatter | `revision` count as a risk signal |
| #118 Gardening Scanner | #120 CLAUDE.md Convention | `FINDING` output | Staleness detection for CLAUDE.md sections |
| #120 `bm-agent env check` | #118 Gardening | `dev-boot.yml` tool list | Whether gardening prerequisites are installed |
| #120 `bm-agent project describe` | #116 Plan Grounding | JSON project snapshot | Current-state data for plan artifact validation |

### 3.2 Shared Conventions

Three conventions are shared across sub-epics:

**1. Script location convention:** All agent-facing scripts live under `team/coding-agent/skills/`:
- Check runner: `team/coding-agent/skills/check-runner/`
- Metrics collectors: `team/coding-agent/skills/metrics/`
- Gardening executor/scanners: `team/coding-agent/skills/gardening/`
- Risk classifier: `team/coding-agent/skills/autonomy/`

**2. Structured output conventions:** Two output formats serve different use cases:
- `VIOLATION|RULE|REMEDIATION|REFERENCE` (multi-line) — #114 check scripts, few detailed results
- `FINDING|category|severity|file|description|auto-fixable` (pipe-delimited) — #118 gardening, many machine-parseable results
- JSON — #117 metrics, #119 risk classifier, #120 agent tools

**3. Knowledge artifact location:** All workflow artifacts in `team/projects/<project>/knowledge/`:
- Designs: `designs/epic-<N>.md`
- Plans: `plans/epic-<N>-breakdown.md`, `plans/story-<N>-impl.md`
- Reports: `reports/quality-YYYY-MM-DD.md`
- Metrics: `../metrics/` (sibling to knowledge)
- Autonomy: `../autonomy/trust-state.yml`

### 3.3 Hat Instruction Modifications

Multiple sub-epics modify the same hat instructions. The changes are additive (each sub-epic adds steps, none removes existing ones):

| Hat | #114 | #116 | #117 | #118 | #119 | #120 |
|-----|------|------|------|------|------|------|
| `arch_designer` | — | Add frontmatter to designs | Read metric summary | — | — | — |
| `arch_planner` | — | Write breakdown file | — | — | — | — |
| `arch_breakdown` | — | Update breakdown `stories` field | — | — | — | — |
| `dev_implementer` | — | Write impl plan | Call build-test collector | — | — | Run dev boot |
| `dev_code_reviewer` | Run check runner | Read impl plan | Read build-test metrics | — | — | — |
| `qe_test_designer` | — | Read breakdown file | — | — | — | Run env check |
| `qe_verifier` | Run check runner | Read impl plan | Call build-test collector | — | — | — |
| `po_reviewer` | — | — | — | — | Gate policy engine | — |
| Board scanner | — | — | Quality report trigger | Gardening trigger | — | — |
| (new) `gardener` | — | — | — | Handle `gardening.scan` | — | — |

### 3.4 New Directories and Files

| Location | Sub-Epic | Purpose |
|----------|----------|---------|
| `team/invariants/checks/` | #114 | Profile-generic check scripts |
| `projects/botminter/invariants/checks/` | #114 | Project-specific check scripts |
| `team/coding-agent/skills/check-runner/` | #114 | Check runner script |
| `team/projects/<project>/knowledge/plans/` | #116 | Breakdown and implementation plan files |
| `team/coding-agent/skills/metrics/` | #117 | Metric collector scripts |
| `team/projects/<project>/metrics/` | #117 | JSONL metric store files |
| `team/projects/<project>/knowledge/reports/` | #117 | Quality summary reports |
| `team/coding-agent/skills/gardening/` | #118 | Gardening executor and scanner scripts |
| `team/coding-agent/skills/autonomy/` | #119 | Risk classifier script |
| `team/projects/<project>/autonomy/` | #119 | Trust state file |
| `projects/botminter/knowledge/dev-boot.yml` | #120 | Dev boot configuration |
| `crates/bm/src/legibility.rs` | #120 | New Rust module for agent tools |

### 3.5 New Hat

One new hat is introduced across all sub-epics:

| Hat | Sub-Epic | Triggers | Publishes |
|-----|----------|----------|-----------|
| `gardener` | #118 | `gardening.scan` | `gardening.done`, `gardening.failed` |

No other new hats, statuses, or events are introduced. The existing workflow operates unchanged; the new capabilities are additive.

---

## 4. Acceptance Criteria

### 4.1 Phase Gate Criteria

**Phase 1 complete when:**

- **Given** a code change introduces `println!` in a domain module, **when** the check runner executes, **then** a VIOLATION is reported with file, line, rule reference, and remediation action (#114).
- **Given** `arch_designer` produces a design doc, **when** the design is written, **then** it contains valid YAML frontmatter with type, status, parent, and revision fields (#116).
- **Given** `dev_implementer` runs `cargo test`, **when** the build completes, **then** a JSONL metric entry is appended with test counts, build duration, and branch name (#117).

**Phase 2 complete when:**

- **Given** no actionable board work exists and 7+ days have elapsed since last gardening, **when** the board scanner checks, **then** `gardening.scan` is emitted and the gardener hat auto-fixes lint/format issues, creates a PR, and creates a tracking issue at `dev:code-review` (#118).
- **Given** a project at `monitored` tier with a LOW-risk issue at `po:design-review`, **when** `po_reviewer` activates, **then** it auto-advances to `arch:plan` with a notification comment documenting the risk assessment (#119).

**Phase 3 complete when:**

- **Given** an agent starts work on BotMinter, **when** it runs `bm-agent project describe`, **then** it receives valid JSON listing all domain modules, test tiers, and build commands matching the current filesystem state (#120).
- **Given** `bm-agent` encounters an error, **when** the error is output, **then** it is structured JSON with `error`, `category`, and `remediation` fields (#120).

### 4.2 Overall Epic Acceptance Criteria

- **Given** all six sub-epics are implemented and deployed, **when** the agent operates with `tier: monitored` in trust-state.yml, **then** low-risk designs auto-advance through `po:design-review` without human blocking, the agent receives quality feedback via metrics, check scripts catch invariant violations mechanically, plans are inspectable across hat transitions, codebase gardening runs periodically, and `bm-agent` provides structured project and environment information.

- **Given** a new invariant is defined as a prose rule, **when** the rule is mechanically checkable, **then** it can be implemented as a check script in `invariants/checks/` and enforced automatically by the check runner at `dev:code-review` and `qe:verify` gates and in CI.

- **Given** an auto-advanced gate decision is reversed by the human, **when** the reversal is processed, **then** the system demotes autonomy tier, cascades to downstream work, and the agent returns to supervised mode until trust is re-earned.

- **Given** the agent completes work on a story, **when** the story reaches `done`, **then** build/test metrics, cycle time, and rejection count are recorded and available for quality trend analysis.

---

## 5. Impact on Existing System

### 5.1 What Changes

| Area | Change | Sub-Epics |
|------|--------|-----------|
| Team repo: new directories | `checks/`, `skills/`, `metrics/`, `plans/`, `reports/`, `autonomy/` | All |
| Hat instructions | 10 hats gain new steps (additive, no removal) | #114, #116, #117, #119, #120 |
| ralph.yml | 1 new hat (`gardener`) | #118 |
| Board scanner skill | Gardening trigger + quality report trigger | #117, #118 |
| Project repo: `bm-agent` | 3 new subcommands, structured error output | #120 |
| Project repo: Justfile | 1 new recipe (`test-json`) | #120 |
| Project repo: tests | Exploratory tests gain `report_result()` structured output | #120 |
| Project repo: invariants/checks/ | 2 project-specific check scripts | #114 |
| CLAUDE.md | Updated references + maintenance convention | #114, #120 |

### 5.2 What Does NOT Change

- **Ralph Orchestrator** — no orchestrator-level code changes across any sub-epic
- **Status graph** — no new statuses, no modified transitions
- **Existing test infrastructure** — unit/integration/e2e/exploratory tests are unmodified (except exploratory gains parallel structured output)
- **BotMinter CLI** (`bm`) — operator-facing CLI is unchanged
- **Daemon HTTP API** — already produces structured JSON; no changes
- **Web console** — frontend is unmodified
- **Existing 11 ADRs** — no ADRs are modified or superseded
- **Existing 11 invariants** — prose invariants remain; check scripts are additive enforcement
- **Bridge, formation, git, profile modules** — no domain module changes (except #120's error classification is applied to `bm-agent` command layer, not domain modules)

### 5.3 Delivery Independence

Each sub-epic goes through the full issue lifecycle independently. The epic does NOT require all six sub-epics to be merged simultaneously. Each phase delivers value incrementally:

- After Phase 1: agents have check-enforced invariants, inspectable plans, and quality feedback
- After Phase 2: gardening maintains codebase quality automatically, and low-risk gates auto-advance
- After Phase 3: the entire agent development surface is structured and machine-readable

A sub-epic that encounters blockers does not block its phase peers or subsequent phases (due to graceful degradation documented in each design's error handling).

---

## 6. Security Considerations

### 6.1 Attack Surface Assessment

The six sub-epics add no new network surfaces, no new authentication mechanisms, and no new secret storage. All new capabilities operate within the existing trust boundaries:

| Sub-Epic | New Surface | Trust Model |
|----------|-------------|-------------|
| #114 | Shell scripts reading source files | Same as existing grep/find usage |
| #116 | Markdown files with YAML frontmatter | Same as existing knowledge files |
| #117 | JSONL files with build/test data | Same as existing `history.jsonl` |
| #118 | Auto-fix PRs via `GH_TOKEN` | Same token, same PR workflow |
| #119 | Trust-state YAML file | Team repo write access = trust boundary |
| #120 | `bm-agent` subcommands running version checks | Read-only tool invocations |

### 6.2 Graduated Autonomy Security Model

The most security-sensitive sub-epic is #119 (Graduated Autonomy). Key controls:

- **Promotion is human-only.** The system cannot self-promote to a higher autonomy tier. Demotion IS automated (fail-safe).
- **AI review gate is unaffected.** `lead:design-review` and `lead:plan-review` remain mandatory at all tiers. Graduated autonomy applies only to human gates (`po:*`).
- **Reversals are always possible.** Auto-advanced gates can be reversed within a configurable window (default: until the next human gate). Reversal triggers automatic demotion.
- **Risk assessment is auditable.** Every auto-advance comment includes the full risk classifier output — signals, reasoning, and composite score. Bad assessments are visible in the issue timeline.

### 6.3 Supply Chain Considerations

#118 (Gardening) introduces new tool dependencies: `cargo-audit`, `cargo-machete`, `govulncheck`. These are installed from official registries (crates.io, pkg.go.dev). Scanner scripts are committed to the team repo and reviewed via normal code review. The gardening executor does not download or execute arbitrary code — it runs defined tool commands with hardcoded arguments.

### 6.4 No Secret Exposure

No sub-epic introduces new secrets or exposes existing ones:
- Check scripts analyze source code, not runtime state
- Metric files contain timing data and counts, not credentials
- Plan artifacts describe code structure, not API keys
- Trust-state files contain tier/stats, not tokens
- `bm-agent env check` validates that env vars are SET, not their values
- Error remediation messages reference variable NAMES, not values

### 6.5 Prompt Injection Risk

Plan artifacts (#116) and trust-state (#119) are files in the team repo that agents read. A compromised team repo write could inject instructions. This is the same trust model as existing knowledge files, hat instructions, and invariants — team repo write access is the primary control. JSONL metrics (#117) have lower risk since consumers parse them with `jq`, not as natural language.
