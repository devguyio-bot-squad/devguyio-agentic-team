# Design: Plans as First-Class Artifacts

**Epic:** #111 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's planning artifacts are fragmented across four locations that evolved through different methodology phases:

| Location | Contains |
|---|---|
| `.planning/adrs/` | 11 ADRs (the most structured set) |
| `.planning/codebase/` | 7 architecture description files |
| `.planning/specs/`, `.planning/plans/` | Feature specs and plans from earlier phases |
| `.planning/milestones/` | Milestone plans with phase directories |
| `team/projects/<project>/knowledge/designs/` | Design docs produced by arch_designer |

Story breakdowns exist only in GitHub issue comments. No execution plans track which stories are in progress, which are blocked, or what decisions were made during implementation.

This epic introduces versioned execution plans as living documents that track epic implementation from breakdown through completion.

### Harness Pattern

> "Active plans, completed plans, and known technical debt are all versioned and co-located, allowing agents to operate without relying on external context."

Harness maintains `docs/exec-plans/active/` and `docs/exec-plans/completed/` directories. Plans are first-class versioned artifacts — not ephemeral issue comments that disappear into notification history.

### Scope

- Execution plan template and directory convention
- `arch_planner` integration (plan creation)
- `arch_monitor` integration (plan updates)
- Artifact-home convention documenting where each artifact type lives

### Out of Scope

- Migrating existing `.planning/` artifacts to a new structure (they stay where they are)
- Cleaning up historical planning artifacts (that's gardening, #110)
- Changing ADR format or location (ADRs live with the code per ADR-0001)

---

## 2. Architecture

### Artifact Homes

Each artifact type has a defined home. This convention is documented as team knowledge:

| Artifact | Home | Rationale |
|---|---|---|
| ADRs | Project repo `.planning/adrs/` | Codebase decisions. Live with the code per ADR-0001. |
| Architecture docs | Project repo `.planning/codebase/` | Codebase structure descriptions. |
| Design docs | `team/projects/<project>/knowledge/designs/` | Design context consumed by hats. |
| Execution plans | `team/projects/<project>/plans/` | Living documents tracking epic execution. |
| Knowledge | Team repo knowledge hierarchy | Advisory context loaded on-demand by hats. |
| Invariants | `team/invariants/` (profile) or `projects/<project>/invariants/` (project) | Constraints enforced by hats and check scripts. |

Historical artifacts (`.planning/specs/`, `.planning/plans/`, `.planning/milestones/`) stay in place. The gardener (#110) can flag stale ones over time.

### Plan Lifecycle

```
arch_planner creates breakdown → approved by PO
  → Execution plan created at team/projects/<project>/plans/epic-<N>.md
    → Stories created and tracked in the plan
      → arch_monitor updates plan as stories complete
        → All stories done → plan status = Completed
```

---

## 3. Components and Interfaces

### Execution Plan Template

```markdown
# Execution Plan: Epic #<N> — <title>

## Status: In Progress | Completed

## Stories

| # | Title | Status | Completed |
|---|-------|--------|-----------|
| 42 | Implement check runner | dev:implement | — |
| 43 | Add baseline scripts | po:triage | — |

## Key Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-04 | Use grep over AST | Simpler, covers 90% of cases per ADR-0002 |

## Progress Notes

- 2026-04-04: Stories created, implementation starting
- 2026-04-06: Check runner complete, starting on baseline scripts
```

Plans are markdown — readable by agents and humans, diffable in git, discoverable by the gardener for freshness checks.

### Hat Integration

**`arch_planner`** creates the plan when a story breakdown is approved:
- Creates `team/projects/<project>/plans/epic-<N>.md` with the template
- Populates the Stories table with created story numbers and titles
- Initial status: In Progress

**`arch_monitor`** updates the plan during epic monitoring:
- Updates story statuses from the board
- Logs key decisions made during implementation
- Adds progress notes at milestones
- Sets plan status to Completed when all stories are done

### Artifact-Home Knowledge Doc

A new knowledge file at `team/knowledge/artifact-homes.md` documenting where each artifact type lives and why. This is the progressive disclosure entry point — an agent that encounters a planning artifact knows where to file new ones.

---

## 4. Acceptance Criteria

- **Given** `arch_planner` produces a story breakdown that is approved, **when** stories are created, **then** an execution plan exists at `team/projects/<project>/plans/epic-<N>.md` with all stories listed.
- **Given** a story completes, **when** `arch_monitor` scans the epic, **then** the plan's story table is updated.
- **Given** a key decision is made during implementation, **when** `arch_monitor` runs, **then** the decision is logged in the plan with date and rationale.
- **Given** all stories for an epic complete, **when** the epic is accepted, **then** the plan status is set to Completed.

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| `team/projects/<project>/plans/` | New directory for execution plans |
| `team/knowledge/artifact-homes.md` | New knowledge doc |
| `arch_planner` hat instructions | Add plan creation step after breakdown approval |
| `arch_monitor` hat instructions | Add plan update step during monitoring |

No changes to: existing `.planning/` artifacts, ADR format or location, design doc format, Ralph Orchestrator, status graph.

---

## 6. Security Considerations

Execution plans contain issue numbers, story titles, dates, and decision rationale. No sensitive data (credentials, tokens, PII). Plans are version-controlled in the team repo — changes are auditable via git history. Plans do not influence runtime behavior — they are tracking documents, not configuration.
