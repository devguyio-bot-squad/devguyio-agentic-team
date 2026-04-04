# Design: Plans as First-Class Artifacts

**Epic:** #116 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's SDLC workflow produces three categories of plans: design documents, story breakdowns, and implementation plans. Today these fragment across locations and formats:

- **Design docs** — Files at `team/projects/<project>/knowledge/designs/epic-<N>.md`, but with no structured metadata (no frontmatter, no status tracking, no revision field). The `arch_designer` hat writes plain markdown.
- **Story breakdowns** — Posted by `arch_planner` as GitHub issue comments only. No file-system presence. Once posted, they're accessible only via the GitHub API. Agents that need to reference a breakdown must re-parse the comment from the issue timeline.
- **Implementation plans** — Exist only in the agent's context window during `dev_implementer` execution. Lost entirely on context refresh. No downstream hat can inspect what approach the implementer intended.

There is no plan registry. Plans are discovered by path convention (`designs/epic-<N>.md`), not by structured index. Story breakdowns and implementation plans have no file presence at all.

This sub-epic introduces a plan artifact convention: structured, git-tracked files with YAML frontmatter, consistent locations, and integration into 6 hats. Agent-produced plans become inspectable, auditable, and consumable across iterations and hat transitions.

### Harness Pattern

> "When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it both legible and enforceable for the agent?'"

Plan legibility is the missing capability. When agents produce plans as unstructured comments or ephemeral context, those plans can't be:
- **Referenced** — downstream hats can't look up what the planner decided
- **Validated** — reviewers can't verify implementation matches the plan
- **Audited** — no revision history, no status tracking, no traceability

This mirrors the Harness principle of structured logging vs `println!` — make the output parseable and inspectable. Plans are the agent's "structured log" of decisions.

### Scope

- Plan artifact convention (format, frontmatter schema, file locations)
- Design doc frontmatter enhancement (backward-compatible)
- Breakdown artifact files alongside GitHub comments
- Implementation plan artifacts before coding starts
- Plan registry (index file)
- Hat instruction updates (6 hats: `arch_designer`, `arch_planner`, `dev_implementer`, `dev_code_reviewer`, `qe_test_designer`, `qe_verifier`)
- Profile-level convention documentation

### Out of Scope

- Changing the status graph or adding new statuses
- Modifying the board scanner or coordinator logic
- Automated plan validation (executable checks) — that's #114's domain
- Existing `.planning/` directory in the project repo (pre-existing GSD workflow, separate concern)
- Existing `specs/` directory (spec-driven workflow, separate concern)
- Ralph Orchestrator changes
- BotMinter CLI or daemon/web console changes

---

## 2. Architecture

### 2.1 BotMinter Architecture Context

BotMinter is a multi-binary Rust application with CLI (`bm`), agent CLI (`bm-agent`), HTTP daemon (`daemon/`), and web console (`web/`). The team repo is the coordination control plane — it contains knowledge, invariants, hat configurations, and project-specific artifacts.

Plans live in the **team repo**, not the project repo. The team repo is where workflow artifacts (designs, breakdowns) already live. This keeps plan artifacts close to the coordination fabric.

The project repo has its own planning infrastructure (`.planning/` with ADRs, specs, phases; `.agents/planning/` with agent-authored sessions; `specs/` with sprint-based plans), but these serve the _project-level_ GSD workflow, not the _team-level_ hat-driven SDLC. This design addresses the team-level planning gap.

### 2.2 Plan Artifact Convention

All plan artifacts share a common format:

```markdown
---
type: design | breakdown | implementation
status: draft | in-review | approved | in-progress | complete
parent: 106          # parent epic/story issue number
revision: 1
created: 2026-04-04
updated: 2026-04-04
---

# Plan Title

[Plan content...]
```

**Location:** `team/projects/<project>/knowledge/`

| Type | Location | Produced by | Consumed by |
|------|----------|-------------|-------------|
| Design | `designs/epic-<N>.md` | `arch_designer` | `arch_planner`, `lead_reviewer`, `po_reviewer` |
| Breakdown | `plans/epic-<N>-breakdown.md` | `arch_planner` | `arch_breakdown`, `lead_reviewer`, `po_reviewer`, `qe_test_designer` |
| Implementation | `plans/story-<N>-impl.md` | `dev_implementer` | `dev_code_reviewer`, `qe_verifier` |

### 2.3 Plan Lifecycle

Plan status maps to the existing SDLC workflow:

```
              arch_designer writes
                    │
                    ▼
               ┌─────────┐
               │  draft   │
               └────┬─────┘
                    │  hat transitions to review
                    ▼
               ┌─────────┐
               │in-review │  ◄── lead_reviewer / po_reviewer evaluating
               └────┬─────┘
                    │  approved (or rejected → back to draft)
                    ▼
               ┌─────────┐
               │ approved │
               └────┬─────┘
                    │  downstream hat starts work based on this plan
                    ▼
               ┌──────────────┐
               │ in-progress  │  ◄── arch_planner using design, dev_implementer coding
               └──────┬───────┘
                      │  work finished
                      ▼
               ┌──────────┐
               │ complete  │
               └───────────┘
```

Status transitions in plan frontmatter mirror the issue status transitions. The hat that produces the plan sets `draft`. When the plan's review status is reached (e.g., `lead:design-review` for designs), the plan status becomes `in-review`. On approval, `approved`. When the next phase starts consuming the plan, `in-progress`. When all downstream work is done, `complete`.

### 2.4 Relationship to Existing Planning Artifacts

The project repo has three pre-existing planning systems:

| System | Location | Purpose | Unchanged by this design |
|--------|----------|---------|--------------------------|
| GSD workflow | `.planning/` | Project-level milestone planning, ADRs, phases | Yes |
| Agent planning | `.agents/planning/` | Agent-authored design sessions | Yes |
| Spec workflow | `specs/` | Sprint-based implementation specs with `.code-task.md` | Yes |

These systems serve the _project-level_ development workflow when building BotMinter itself. This design addresses the _team-level_ SDLC workflow — the hat-driven process that runs on the team repo. The two systems coexist without interference.

### 2.5 Plan Discovery

Plans are discovered by directory convention. No dynamic registry is needed at this stage — the directory structure IS the registry:

```
team/projects/<project>/knowledge/
  designs/
    epic-114.md
    epic-116.md
  plans/
    epic-114-breakdown.md
    story-42-impl.md
    story-43-impl.md
```

A hat looking for a design reads `designs/epic-<N>.md`. A hat looking for a breakdown reads `plans/epic-<N>-breakdown.md`. A hat looking for an implementation plan reads `plans/story-<N>-impl.md`. The naming convention is deterministic — no index file needed.

---

## 3. Components and Interfaces

### 3.1 Plan Frontmatter Schema

```yaml
---
type: design | breakdown | implementation
status: draft | in-review | approved | in-progress | complete
parent: 116          # issue number this plan belongs to
revision: 1          # incremented on each revision
created: 2026-04-04  # ISO date of first version
updated: 2026-04-04  # ISO date of latest revision
stories: []          # breakdown only: list of story issue numbers
depends_on: []       # implementation only: list of blocking story numbers
---
```

Fields by plan type:

| Field | Design | Breakdown | Implementation |
|-------|--------|-----------|----------------|
| type | required | required | required |
| status | required | required | required |
| parent | epic number | epic number | story number |
| revision | required | required | required |
| created | required | required | required |
| updated | required | required | required |
| stories | — | required | — |
| depends_on | — | — | optional |

### 3.2 Design Doc Enhancement

Existing design docs (e.g., `epic-114.md`) gain YAML frontmatter. The existing content remains unchanged. This is backward-compatible — files without frontmatter still work; hats treat missing frontmatter as `status: draft, revision: 1`.

Example transformation for the existing `epic-114.md`:

```markdown
---
type: design
status: in-review
parent: 106
revision: 1
created: 2026-04-04
updated: 2026-04-04
---

# Design: Executable Invariant Checks
[existing content unchanged]
```

### 3.3 Breakdown Artifact

`arch_planner` currently posts story breakdowns as GitHub issue comments only. This design adds a parallel file write.

**New workflow for `arch_planner`:**
1. Read the design doc from `designs/epic-<N>.md`
2. Decompose into stories (existing behavior)
3. **Write breakdown file** to `plans/epic-<N>-breakdown.md` with frontmatter
4. Post the breakdown as a GitHub comment (existing behavior)
5. Transition to `lead:plan-review` (existing behavior)

The breakdown file contains the same content as the comment, plus the frontmatter header. The comment provides visibility in the issue timeline. The file provides persistence and machine-readability.

**Breakdown file structure:**

```markdown
---
type: breakdown
status: draft
parent: 116
revision: 1
created: 2026-04-04
updated: 2026-04-04
stories: []
---

# Story Breakdown: Plans as First-Class Artifacts

## Story 1: Plan Artifact Convention
**Title:** Define plan artifact convention
**Description:** [...]
**Acceptance Criteria:**
- Given [...]

## Story 2: ...
```

The `stories` field starts empty and is populated by `arch_breakdown` when it creates the actual story issues (it writes back the issue numbers).

### 3.4 Implementation Plan Artifact

`dev_implementer` currently starts coding immediately. This design adds a plan-before-code step.

**New workflow for `dev_implementer`:**
1. Read the story issue and its parent epic's breakdown
2. **Write implementation plan** to `plans/story-<N>-impl.md` with frontmatter
3. Proceed with implementation (existing behavior)

**Implementation plan structure:**

```markdown
---
type: implementation
status: in-progress
parent: 42
revision: 1
created: 2026-04-04
updated: 2026-04-04
depends_on: []
---

# Implementation Plan: Story #42 — Define Plan Artifact Convention

## Approach
[High-level approach and key design decisions]

## Affected Files
- `team/members/superman-bob/ralph.yml` — hat instruction updates
- `team/projects/botminter/knowledge/plan-artifact-convention.md` — new convention doc

## Test Strategy
[What tests validate this implementation]

## Risks
[Known risks and mitigations]
```

The implementation plan gives `dev_code_reviewer` and `qe_verifier` inspectable context: what was planned vs what was built.

### 3.5 Hat Instruction Updates

Six hats receive instruction updates:

| Hat | Current Behavior | New Behavior |
|-----|-----------------|-------------|
| `arch_designer` | Writes design doc without frontmatter | Adds YAML frontmatter to design docs. Sets `status: draft` on creation, `status: in-review` on transition to `lead:design-review`. |
| `arch_planner` | Posts breakdown as GitHub comment only | Writes breakdown file to `plans/epic-<N>-breakdown.md` alongside the comment. Sets `status: draft`. |
| `dev_implementer` | Starts coding immediately | Writes implementation plan to `plans/story-<N>-impl.md` before coding. Sets `status: in-progress`. |
| `dev_code_reviewer` | Reviews code without plan context | Reads `plans/story-<N>-impl.md` to validate implementation matches the plan. Checks for plan drift. |
| `qe_test_designer` | Reads story acceptance criteria from issue | Also reads the parent epic's breakdown file for test scope and inter-story dependency context. |
| `qe_verifier` | Verifies against acceptance criteria | Also reads the implementation plan for verification context (intended approach, affected files, test strategy). |

### 3.6 Profile-Level Convention

The scrum-compact profile gains a knowledge document:

**`profiles/scrum-compact/knowledge/plan-artifact-convention.md`**

This document describes:
- The three plan types and their purposes
- YAML frontmatter schema
- File naming convention
- Which hats produce and consume each plan type
- How plan status maps to issue status

This knowledge doc is extracted to `team/knowledge/plan-artifact-convention.md` during `bm init`, making it available to all hats via knowledge resolution.

### 3.7 Commit and Git Integration

Plan files are committed to the team repo by the hats that produce them. The commit follows existing conventions:

```
docs(plans): add breakdown for epic #116

Ref: #116
```

Plan files are git-tracked. Revision history is captured both in the frontmatter `revision` field and in git history. On revision (e.g., after rejection feedback), the hat increments the `revision` field and overwrites the file — git diff shows what changed.

---

## 4. Data Models

### 4.1 Plan Frontmatter (YAML)

```yaml
# Required for all plan types
type: string         # "design" | "breakdown" | "implementation"
status: string       # "draft" | "in-review" | "approved" | "in-progress" | "complete"
parent: integer      # GitHub issue number
revision: integer    # starts at 1, incremented on each revision
created: string      # ISO date (YYYY-MM-DD)
updated: string      # ISO date (YYYY-MM-DD)

# Breakdown-specific
stories: integer[]   # GitHub issue numbers of created stories

# Implementation-specific
depends_on: integer[] # GitHub issue numbers of blocking stories
```

### 4.2 File Naming Convention

| Pattern | Example | When Created |
|---------|---------|-------------|
| `designs/epic-<N>.md` | `designs/epic-116.md` | `arch_designer` creates design |
| `plans/epic-<N>-breakdown.md` | `plans/epic-116-breakdown.md` | `arch_planner` decomposes design |
| `plans/story-<N>-impl.md` | `plans/story-42-impl.md` | `dev_implementer` starts story |

`<N>` is always the GitHub issue number. This makes plan files deterministically locatable from any issue reference.

---

## 5. Error Handling

- **Missing plan file:** If a downstream hat expects a plan file and it doesn't exist, the hat proceeds without it and logs a warning in the issue comment. Plan files enhance the workflow but are not hard blockers. This prevents a missing file from stalling the entire pipeline.
- **Malformed frontmatter:** If frontmatter is missing or unparseable, the hat treats the file as `status: draft, revision: 1` (safe defaults). The hat does not crash or reject.
- **Concurrent writes:** Plan files are written by one hat at a time (the workflow is serial). No concurrent write conflicts. If git merge conflicts occur during team repo sync, the latest revision (higher `revision` number) takes precedence.
- **Stale plan references:** If a plan references story issues that no longer exist (closed, deleted), downstream hats skip those references. The plan file itself is not invalidated.
- **File write failure:** If a hat fails to write a plan file (disk error, permission issue), the hat continues with its primary action (posting the GitHub comment, starting implementation). The missing plan file is noted in the issue comment as a warning.

---

## 6. Acceptance Criteria

- **Given** `arch_designer` produces a design doc, **when** the design doc is written, **then** it contains valid YAML frontmatter with `type: design`, `status: draft`, the parent epic number, and `revision: 1`.

- **Given** `arch_planner` decomposes a design into stories, **when** the breakdown is posted, **then** a file exists at `team/projects/<project>/knowledge/plans/epic-<N>-breakdown.md` with valid frontmatter and the same story content as the GitHub comment.

- **Given** `dev_implementer` starts working on a story, **when** implementation begins, **then** a file exists at `team/projects/<project>/knowledge/plans/story-<N>-impl.md` describing the approach, affected files, and test strategy.

- **Given** `dev_code_reviewer` reviews a story, **when** an implementation plan exists, **then** the reviewer reads the plan and checks whether the code changes match the planned approach and affected files.

- **Given** a design doc is revised after rejection feedback, **when** the revised design is written, **then** the frontmatter `revision` field is incremented and `updated` date reflects the revision date.

- **Given** `arch_breakdown` creates story issues from a breakdown, **when** issues are created, **then** the breakdown file's `stories` field is updated with the created issue numbers.

- **Given** a plan file has malformed or missing frontmatter, **when** a hat reads it, **then** the hat treats it as `status: draft, revision: 1` and proceeds without error.

---

## 7. Impact on Existing System

| Component | Change |
|-----------|--------|
| `arch_designer` hat instructions | Add YAML frontmatter to design doc output |
| `arch_planner` hat instructions | Write breakdown file alongside GitHub comment |
| `arch_breakdown` hat instructions | Update breakdown file's `stories` field after creating issues |
| `dev_implementer` hat instructions | Write implementation plan before coding |
| `dev_code_reviewer` hat instructions | Read implementation plan during review |
| `qe_test_designer` hat instructions | Read breakdown file for test scope |
| `qe_verifier` hat instructions | Read implementation plan for verification context |
| `team/projects/<project>/knowledge/plans/` | New directory for breakdown and implementation plan files |
| `profiles/scrum-compact/knowledge/` | New `plan-artifact-convention.md` |
| Existing design docs | Add frontmatter (backward-compatible; no content changes) |

**No changes to:** Ralph Orchestrator, BotMinter CLI (`bm`), agent CLI (`bm-agent`), daemon/web console, bridge system, existing status graph, existing invariant files, existing test infrastructure, existing ADRs, `.planning/` directory, `specs/` directory, `.agents/planning/` directory.

---

## 8. Security Considerations

Plan artifacts are markdown files stored in the git-tracked team repo. They contain architectural decisions, implementation approaches, and file path references — no secrets, no credentials, no runtime state.

**No new attack surface:** Plans are read and written by the agent's existing file access. No new permissions, no network requests beyond existing GitHub API usage, no shell execution.

**Prompt injection risk:** Plan files could theoretically contain prompt injection if a malicious actor gains team repo write access. This is the same trust model as all existing knowledge files, hat instructions, and invariants. The mitigation is unchanged: team repo write access is restricted to authorized team members and their agents.

**No secret exposure:** Plan files describe code structure and approach. They do not contain API keys, tokens, database credentials, or environment-specific secrets. The frontmatter schema has no secret fields.
