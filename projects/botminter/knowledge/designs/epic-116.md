# Design: Plans as First-Class Artifacts

**Epic:** #116 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's SDLC workflow produces three categories of plans: design documents, story breakdowns, and implementation plans. Today these fragment across locations and formats:

- **Design docs** — Files at `team/projects/<project>/knowledge/designs/epic-<N>.md`. Four of seven existing docs have ad-hoc YAML frontmatter (fields like `epic:`, `author:`, `sub_epics:`, `depends_on:` with string-typed values), while three have none. There is no consistent schema — field names, types, and presence vary across docs. No doc tracks plan lifecycle status.
- **Story breakdowns** — Posted by `arch_planner` as GitHub issue comments only. No file-system presence. Once posted, they're accessible only via the GitHub API. Agents that need to reference a breakdown must re-parse the comment from the issue timeline.
- **Implementation plans** — Exist only in the agent's context window during `dev_implementer` execution. Lost entirely on context refresh. No downstream hat can inspect what approach the implementer intended.

There is no plan registry. Plans are discovered by path convention (`designs/epic-<N>.md`), not by structured index. Story breakdowns and implementation plans have no file presence at all.

This sub-epic introduces a plan artifact convention: structured, git-tracked files with YAML frontmatter, consistent locations, and integration into 7 hats. Agent-produced plans become inspectable, auditable, and consumable across iterations and hat transitions.

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
- Hat instruction updates (7 hats: `arch_designer`, `arch_planner`, `arch_breakdown`, `dev_implementer`, `dev_code_reviewer`, `qe_test_designer`, `qe_verifier`)
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
status: draft | in-review | in-progress
parent: 114          # issue number this plan belongs to
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
| Design | `designs/epic-<N>.md` | `arch_designer` | `arch_planner`, `dev_implementer`, `lead_reviewer`, `po_reviewer` |
| Breakdown | `plans/epic-<N>-breakdown.md` | `arch_planner` | `dev_implementer`, `lead_reviewer`, `po_reviewer`, `qe_test_designer` |
| Implementation | `plans/story-<N>-impl.md` | `dev_implementer` | `dev_code_reviewer`, `qe_verifier` |

**Note:** `arch_breakdown` is not a consumer of the breakdown file — it reads the GitHub comment for story creation (see §3.3, §3.5). It writes back to the file to update the `stories` field with created issue numbers.

### 2.3 Plan Lifecycle

Plan status tracks three states. Every transition has a named responsible hat:

```
               ┌─────────┐     producing hat creates
               │  draft   │     (arch_designer, arch_planner)
               └────┬─────┘
                    │  producing hat transitions to review gate
                    ▼
               ┌──────────┐    plan under lead/po review
               │ in-review │    (lead_reviewer / po_reviewer evaluating)
               └────┬──────┘
                    │  rejected → producing hat revises → back to draft
                    │  approved → consuming hat starts work
                    ▼
               ┌──────────────┐  consuming hat is actively using the plan
               │  in-progress  │  (arch_planner using design, dev_implementer using breakdown)
               └───────────────┘
```

| Transition | Responsible Hat | Trigger |
|------------|----------------|---------|
| → `draft` | Producing hat (`arch_designer`, `arch_planner`) | Plan file created or revised after rejection |
| `draft` → `in-review` | Producing hat (`arch_designer`, `arch_planner`) | Issue transitions to review gate (`lead:design-review`, `lead:plan-review`) |
| `in-review` → `draft` | Producing hat | Rejection feedback received; revision written |
| `in-review` → `in-progress` | Consuming hat (`arch_planner`, `dev_implementer`) | Downstream hat starts using the approved plan |

`approved` and `complete` are not tracked in plan frontmatter. Approval is already captured by the issue moving past the review gate — if the consuming hat is running, the plan was approved. Completion is captured by the issue closing. Tracking these would create redundant state with no consumer.

Implementation plans are an exception — they enter the lifecycle at `in-progress` directly because they are unreviewed working documents produced by `dev_implementer` immediately before coding. They skip `draft` and `in-review`. On revision after code-review rejection, the implementer overwrites the existing plan: increments `revision`, updates the `updated` date, and retains `status: in-progress` (since impl plans never use `draft` or `in-review`).

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
status: draft | in-review | in-progress
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

Existing design docs gain YAML frontmatter conforming to the §3.1 schema. The existing content remains unchanged.

**Docs without frontmatter** (e.g., `epic-114.md`, `epic-117.md`): The first hat that touches the doc adds the full §3.1 frontmatter block. Until then, hats treat missing frontmatter as `status: draft, revision: 1`.

**Docs with ad-hoc frontmatter** (e.g., `epic-106.md`, `epic-118.md`, `epic-119.md`, `epic-120.md`): These use a divergent schema — `epic:` (string), `author:`, `sub_epics:`, `depends_on:` (on designs), with string-typed values. The first hat that touches each doc rewrites the frontmatter to conform to the §3.1 schema:

| Ad-hoc field | Disposition |
|-------------|-------------|
| `epic: "N"` | Dropped — redundant with the filename (`epic-<N>.md`) |
| `author:` | Dropped — captured by `git blame` |
| `sub_epics:` | Dropped — the breakdown file's `stories` field replaces this |
| `depends_on:` (on designs) | Dropped — only applicable to implementation plans per §3.1 |
| `parent: "N"` (string) | Retained as `parent: N` (integer) |
| `type:`, `status:`, `revision:`, `created:`, `updated:` | Retained or added per §3.1 |

Batch migration of all existing docs is not in scope. Migration happens lazily — each doc is rewritten when a hat next produces or revises it. During the transition, hats encountering unrecognized fields ignore them and apply the §3.1 schema on write. Design docs committed alongside this specification (e.g., `epic-106.md`) may still use the ad-hoc schema — they will be migrated when a hat next revises them.

Example transformation for `epic-114.md` (no existing frontmatter):

```markdown
---
type: design
status: in-review
parent: 114
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
1. Read the design doc from `designs/epic-<N>.md` and update its frontmatter to `status: in-progress`
2. Decompose into stories (existing behavior)
3. **Write breakdown file** to `plans/epic-<N>-breakdown.md` with frontmatter
4. Post the breakdown as a GitHub comment (existing behavior)
5. Update breakdown frontmatter to `status: in-review` and transition to `lead:plan-review`

The breakdown file contains the same content as the comment, plus the frontmatter header. The comment provides visibility in the issue timeline. The file provides persistence and machine-readability.

**Revision after rejection:** When a breakdown is rejected at `lead:plan-review` and the planner must revise, the same steps apply with revision semantics. The planner overwrites the existing file (incrementing `revision`, resetting `status` to `draft`, updating `updated` date) and posts a NEW comment to the issue. The latest comment is authoritative for `arch_breakdown` — it always reads the most recent breakdown comment, which will match the latest file revision.

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
1. Read the story issue and its parent epic's breakdown; update the breakdown's frontmatter to `status: in-progress`
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

**Revision after rejection:** When a story is rejected at `dev:code-review` and returns to `dev:implement`, the implementer overwrites the existing plan file: increments `revision`, updates the `updated` date, and retains `status: in-progress` (implementation plans never enter `draft` or `in-review`). No new GitHub comment is posted — the file is the sole artifact. The code reviewer reads the updated plan to see what changed in the approach.

### 3.5 Hat Instruction Updates

Seven hats receive instruction updates:

| Hat | Current Behavior | New Behavior |
|-----|-----------------|-------------|
| `arch_designer` | Writes design doc without frontmatter | Adds YAML frontmatter to design docs. Sets `status: draft` whenever the plan file is written (initial creation or revision after rejection), `status: in-review` on transition to `lead:design-review`. |
| `arch_planner` | Posts breakdown as GitHub comment only | Writes breakdown file to `plans/epic-<N>-breakdown.md` alongside the comment. Sets `status: draft` whenever the plan file is written (initial creation or revision after rejection), `status: in-review` on transition to `lead:plan-review`. Also updates the parent design's frontmatter to `status: in-progress` when starting breakdown work. |
| `arch_breakdown` | Creates story issues from breakdown comment | Also updates the breakdown file's `stories` field with created issue numbers after creating story issues. |
| `dev_implementer` | Starts coding immediately | Writes implementation plan to `plans/story-<N>-impl.md` before coding. Sets `status: in-progress` whenever the plan file is written (initial creation or revision after code-review rejection). Also updates the parent breakdown's frontmatter to `status: in-progress` when starting story work. |
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
status: string       # "draft" | "in-review" | "in-progress"
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

- **Given** a design doc is revised after rejection feedback, **when** the revised design is written, **then** the frontmatter `revision` field is incremented, `status` is set to `draft`, and `updated` date reflects the revision date.

- **Given** a breakdown file is revised after rejection feedback at `lead:plan-review`, **when** the revised breakdown is written, **then** the frontmatter `revision` field is incremented, `status` is set to `draft`, `updated` date reflects the revision date, and a new GitHub comment is posted with the revised breakdown content.

- **Given** an implementation plan is revised after code-review rejection, **when** the revised plan is written, **then** the frontmatter `revision` field is incremented, `status` remains `in-progress`, and `updated` date reflects the revision date.

- **Given** `arch_breakdown` creates story issues from a breakdown, **when** issues are created, **then** the breakdown file's `stories` field is updated with the created issue numbers.

- **Given** `arch_planner` starts decomposing a design, **when** the planner reads the approved design doc, **then** the design doc's frontmatter is updated to `status: in-progress`.

- **Given** `arch_planner` transitions a breakdown to `lead:plan-review`, **when** the transition occurs, **then** the breakdown file's frontmatter is updated to `status: in-review`.

- **Given** `dev_implementer` starts working on a story, **when** the implementer reads the parent breakdown, **then** the breakdown file's frontmatter is updated to `status: in-progress`.

- **Given** `arch_designer` transitions a design to `lead:design-review`, **when** the transition occurs, **then** the design doc's frontmatter is updated to `status: in-review` and the `updated` date reflects the transition date.

- **Given** `dev_implementer` writes an implementation plan, **when** the plan file is created, **then** it contains valid YAML frontmatter with `type: implementation`, `status: in-progress`, the parent story number, and `revision: 1`.

- **Given** `qe_test_designer` designs tests for a story, **when** the parent epic has a breakdown file at `plans/epic-<N>-breakdown.md`, **then** the test designer reads the breakdown file for test scope and inter-story dependency context. **When** no breakdown file exists, **then** the test designer proceeds using story issue content alone and logs a warning.

- **Given** `qe_verifier` verifies a completed story, **when** an implementation plan exists at `plans/story-<N>-impl.md`, **then** the verifier reads the plan for verification context (intended approach, affected files, test strategy). **When** no implementation plan exists, **then** the verifier proceeds using story acceptance criteria alone and logs a warning.

- **Given** a plan file has malformed or missing frontmatter, **when** a hat reads it, **then** the hat treats it as `status: draft, revision: 1` and proceeds without error.

---

## 7. Impact on Existing System

| Component | Change |
|-----------|--------|
| `arch_designer` hat instructions | Add YAML frontmatter to design doc output |
| `arch_planner` hat instructions | Write breakdown file alongside GitHub comment; set breakdown `in-review` on transition; update parent design status to `in-progress` |
| `arch_breakdown` hat instructions | Update breakdown file's `stories` field after creating issues |
| `dev_implementer` hat instructions | Write implementation plan before coding; update parent breakdown status to `in-progress` |
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
