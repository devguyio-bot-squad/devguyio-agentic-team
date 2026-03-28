# Compact Process

This document defines the conventions used by the compact single-member team. All hats follow these formats when creating and updating issues, milestones, PRs, and comments on GitHub. All GitHub operations go through the `github-project` skill.

The compact profile has a single member ("superman") — the agent self-transitions through the full issue lifecycle wearing different hats.

---

## Issue Format

Issues are GitHub issues on the **team repo** (not the project repo). The `github-project` skill auto-detects the team repo from `team/`'s git remote.

### Fields

| Field | GitHub Mapping | Description |
|-------|---------------|-------------|
| `title` | Issue title | Concise, descriptive issue title |
| `state` | Issue state | `open` or `closed` |
| `type` | Native issue type | Epic, Task (story), Bug |
| `assignee` | Issue assignee | GitHub username or unassigned |
| `milestone` | Issue milestone | Milestone name or none |
| `parent` | Native sub-issue relationship | Links stories to their parent epic |
| `body` | Issue body | Description, acceptance criteria, and context (markdown) |

Issues are created via the `github-project` skill (create-issue operation). See the skill for exact commands.

---

## Issue Types

Issue classification uses GitHub's native issue types:

| Issue Type | Kind | Description |
|------------|------|-------------|
| **Epic** | `epic` | A large body of work spanning multiple stories |
| **Task** | `story` | A single deliverable unit of work (sub-issue of an Epic) |
| **Bug** | `bug` | A bug requiring investigation, planning, and fix |

Stories are linked to epics as native sub-issues.
Subtasks for complex bugs are also native sub-issues (Task type under a Bug).

Every issue MUST have exactly one issue type set.

### Labels

Labels are used as modifiers on any issue type, not for classification:

| Label | Description |
|-------|-------------|
| `kind/docs` | Routes the issue to content writer hats for documentation work |
| `role/*` | Assigns the issue to a specific role |

---

## Project Status Convention

Status is tracked via a single-select "Status" field on the team's GitHub Project board (v2). Status values follow the naming pattern:

```
<role>:<phase>
```

- `<role>` — the role responsible (e.g., `po`, `arch`, `dev`, `qe`, `lead`, `sre`, `cw`)
- `<phase>` — the current phase within that role's workflow

Examples:
- `po:triage` — PO is triaging the issue
- `dev:implement` — developer is implementing the story
- `qe:verify` — QE is verifying the implementation

In the compact profile, the same agent self-transitions through all statuses by switching hats. Comment headers still use the role of the active hat (e.g., architect, dev, qe) for audit trail clarity.

---

## Epic Statuses

The epic lifecycle statuses, with the role responsible at each stage:

| Status | Role | Description |
|--------|------|-------------|
| `po:triage` | PO | New epic, awaiting evaluation |
| `po:backlog` | PO | Accepted, prioritized, awaiting activation |
| `arch:design` | architect | Producing design doc |
| `lead:design-review` | team lead | Design doc awaiting lead review |
| `po:design-review` | PO | Design doc awaiting human review |
| `arch:plan` | architect | Proposing story breakdown (plan) |
| `lead:plan-review` | team lead | Story breakdown awaiting lead review |
| `po:plan-review` | PO | Story breakdown awaiting human review |
| `arch:breakdown` | architect | Creating story issues |
| `lead:breakdown-review` | team lead | Story issues awaiting lead review |
| `po:ready` | PO | Stories created, epic parked in ready backlog. Human decides when to activate. |
| `arch:in-progress` | architect | Monitoring story execution (fast-forwards to `po:accept`) |
| `po:accept` | PO | Epic awaiting human acceptance |
| `done` | — | Epic complete |

### Rejection Loops

At human review gates, the human can reject and send the epic back:
- `po:design-review` → `arch:design` (with feedback comment)
- `po:plan-review` → `arch:plan` (with feedback comment)
- `po:accept` → `arch:in-progress` (with feedback comment)

At team lead review gates, the lead can reject and send back to the work hat:
- `lead:design-review` → `arch:design` (with feedback comment)
- `lead:plan-review` → `arch:plan` (with feedback comment)
- `lead:breakdown-review` → `arch:breakdown` (with feedback comment)

The feedback comment uses the standard comment format and includes specific concerns.

---

## Story Statuses

The story lifecycle follows a TDD flow:

| Status | Role | Description |
|--------|------|-------------|
| `qe:test-design` | QE | QE designing tests and writing test stubs |
| `dev:implement` | dev | Developer implementing the story |
| `dev:code-review` | dev | Code review of implementation |
| `qe:verify` | QE | QE verifying implementation against acceptance criteria |
| `arch:sign-off` | architect | Auto-advance (see below) |
| `po:merge` | PO | Human-gated merge for code PRs; auto-advance for non-code issues (see below) |
| `done` | — | Story complete |

### Story Rejection Loops

- `dev:code-review` → `dev:implement` (code reviewer rejects with feedback)
- `qe:verify` → `dev:implement` (QE rejects with feedback)

---

## Bug Statuses

The bug workflow has two tracks: **simple** (fast path) and **complex** (full planning).

| Status | Role | Description |
|--------|------|-------------|
| `bug:investigate` | QE | QE reproduces bug, determines simple vs complex, and either fixes (simple) or plans (complex) |
| `arch:review` | architect | Reviews simple bug fix — approves or escalates to complex track |
| `arch:refine` | architect | Refines complex bug plan (after QE's proposal or arch escalation) |
| `po:plan-review` | PO | Human reviews complex bug plan (reused from epic workflow) |
| `bug:breakdown` | architect | Creates GitHub native subtask issues for complex bugs |
| `bug:in-progress` | architect | Monitors subtask completion |
| `done` | — | Bug complete |

### Simple vs Complex Criteria

During `bug:investigate`, QE determines track using these criteria:

| Criterion | Simple ✅ | Complex ❌ |
|-----------|----------|-----------|
| Files affected | Single file | Multiple files/modules |
| Lines changed | < 20 lines | > 20 lines |
| Scope | Isolated fix | Touches shared code/APIs |
| Architecture | No design change | Requires architectural change |
| Dependencies | No new dependencies | New libraries/packages |
| Testing | Covered by existing tests or trivial addition | Requires new test infrastructure |
| Risk | Low - localized impact | Medium/High - wide impact |

**Rule of thumb:** If QE can fix it in one sitting without subtasks, it's simple.

### Simple Bug Track (Fast Path)

```
bug:investigate → arch:review → qe:verify → done
```

QE implements the fix during investigation, arch reviews code quality, QE validates the fix works.

### Complex Bug Track (Full Planning)

```
bug:investigate → arch:refine → po:plan-review → bug:breakdown → bug:in-progress → qe:verify → done
```

QE proposes plan, arch refines, PO approves, arch creates subtasks, monitor tracks completion, QE validates integrated fix.

### Bug Rejection Loops

- `arch:review` → `arch:refine` (Arch escalates simple bug as too complex)
- `po:plan-review` → `arch:refine` (PO rejects complex bug plan with feedback)
- `qe:verify` → `bug:investigate` (QE verification fails - simple bugs)
- `qe:verify` → `bug:in-progress` (QE verification fails - complex bugs)

### Detailed Workflow

#### Simple Bug Track

| Status | Actions | Next |
|--------|---------|------|
| `bug:investigate` | QE: Reproduce, apply criteria, implement fix, commit to branch | `arch:review` |
| `arch:review` | Arch: Code review, verify simplicity. Approve → next, Too complex → escalate | `qe:verify` or `arch:refine` |
| `qe:verify` | QE: Re-run reproduction, verify bug resolved, test suite. Pass → close, Fail → reopen | `done` or `bug:investigate` |

#### Complex Bug Track

| Status | Actions | Next |
|--------|---------|------|
| `bug:investigate` | QE: Reproduce, root cause, propose solution + subtask breakdown | `arch:refine` |
| `arch:refine` | Arch: Review/amend plan, refine subtasks, add architectural notes | `po:plan-review` |
| `po:plan-review` | PO (human): Approve via comment or reject with feedback | `bug:breakdown` or `arch:refine` |
| `bug:breakdown` | Arch: Create GitHub native subtask issues, set to `dev:implement` | `bug:in-progress` |
| `bug:in-progress` | Arch (monitor): Query subtask status, wait for all to reach `done` | `qe:verify` |
| `qe:verify` | QE: Integration test, re-run original reproduction, verify full fix. Pass → close, Fail → reopen | `done` or `bug:in-progress` |

### Subtask Integration (Complex Bugs Only)

Subtasks created during `bug:breakdown` use GitHub's native sub-issue feature. Each subtask:
- Has native issue type "Task"
- Is a native sub-issue of the parent Bug
- Flows through the normal story workflow: `dev:implement` → `dev:code-review` → `qe:verify` → `arch:sign-off` → `po:merge` → `done`

When all subtasks reach `done`, the bug monitor advances the parent bug to `qe:verify` for final verification.

---

## SRE Statuses

| Status | Role | Description |
|--------|------|-------------|
| `sre:infra-setup` | SRE | Setting up test infrastructure |

SRE is a service role — after completing infrastructure work, the issue returns to its previous status.

---

## Content Writer Statuses

For documentation stories (`kind/docs`):

| Status | Role | Description |
|--------|------|-------------|
| `cw:write` | content writer | Writing documentation |
| `cw:review` | content writer | Reviewing documentation |

Content stories follow the same terminal path as regular stories: on review approval, transition to `po:merge` → auto-advance to `done`.

---

## Auto-Advance Statuses

Some statuses are handled automatically by the board scanner without dispatching a hat:

- `arch:sign-off` → auto-advances to `po:merge`. In the compact profile, the same agent that designed the epic signs off — no separate gate needed.
- `po:merge` → behavior depends on whether the issue has an associated PR:
  - **With PR (code changes):** Board scanner verifies the PR exists and is approved, then notifies the human via RObot. Human is the sole merge authority — the board scanner NEVER calls `gh pr merge`. Once the human merges, the next scan detects the merge and advances to `done`.
  - **Without PR (non-code issues):** Auto-advances to `done` as before.

---

## Supervised Mode

The compact profile uses supervised mode by default. Only these transitions require human approval via GitHub issue comments:

| Gate | Status | What's Presented |
|------|--------|-----------------|
| Design approval | `po:design-review` | Design doc summary |
| Plan approval | `po:plan-review` | Story breakdown |
| Final acceptance | `po:accept` | Completed epic summary |

All other transitions auto-advance without human interaction.

### How approval works

1. The agent adds a **review request comment** on the issue summarizing the artifact
2. The agent **returns control** and moves on to other work
3. The **human** reviews the artifact on GitHub and responds via an issue comment:
   - `Approved` (or `LGTM`) → agent advances the status on the next scan cycle
   - `Rejected: <feedback>` → agent reverts the status and appends the feedback
4. If no human comment is found, the issue stays at its review status — **the agent NEVER auto-approves**

### Idempotency

The agent adds only ONE review request comment per review gate. On subsequent scan cycles, it checks for a human response but does NOT re-comment if a review request is already present.

---

## Error Status

| Status | Description |
|--------|-------------|
| `error` | Issue failed processing 3 times. Board scanner skips it. Human investigates and resets the status to retry. |

---

## Comment Format

Comments are GitHub issue comments, added via `gh issue comment`. Each comment uses this format:

```markdown
### <emoji> <role> — <ISO-8601-UTC-timestamp>

Comment text here. May contain markdown formatting, code blocks, etc.
```

The `<emoji>` and `<role>` are read from the member's `.botminter.yml` file at runtime by the `github-project` skill. Since all agents share one `GH_TOKEN` (one GitHub user), the role attribution in the comment body is the primary way to identify which hat/role wrote it.

### Standard Emoji Mapping

| Role | Emoji | Example Header |
|------|-------|----------------|
| po | 📝 | `### 📝 po — 2026-01-15T10:30:00Z` |
| architect | 🏗️ | `### 🏗️ architect — 2026-01-15T10:30:00Z` |
| dev | 💻 | `### 💻 dev — 2026-01-15T10:30:00Z` |
| qe | 🧪 | `### 🧪 qe — 2026-01-15T10:30:00Z` |
| sre | 🛠️ | `### 🛠️ sre — 2026-01-15T10:30:00Z` |
| cw | ✍️ | `### ✍️ cw — 2026-01-15T10:30:00Z` |
| lead | 👑 | `### 👑 lead — 2026-01-15T10:30:00Z` |
| superman | 🦸 | `### 🦸 superman — 2026-01-15T10:30:00Z` |

In the compact profile, the `<role>` in the comment header reflects which hat is acting (e.g., architect, dev, qe, lead, sre, cw) even though it is the same agent. This preserves audit trail clarity and compatibility with multi-member profiles.

Example:

```markdown
### 🏗️ architect — 2026-01-15T10:30:00Z

Design document produced. See `projects/my-project/knowledge/designs/epic-1.md`.
```

Comments are append-only. Never edit or delete existing comments.

---

## Milestone Format

Milestones are GitHub milestones on the team repo, managed via the `github-project` skill.

**Fields:**

| Field | GitHub Mapping | Description |
|-------|---------------|-------------|
| `title` | Milestone title | Milestone name (e.g., `M1: Initial setup`) |
| `state` | Milestone state | `open` or `closed` |
| `description` | Milestone description | Goals and scope of the milestone |
| `due_on` | Milestone due date | Optional ISO 8601 date |

Issues are assigned to milestones via the `github-project` skill (milestone-ops operation).

---

## Pull Request Format

Pull requests are real GitHub PRs on the team repo. PRs are used for team evolution (knowledge, invariants, process changes), NOT for code changes.

**Fields:**

| Field | GitHub Mapping | Description |
|-------|---------------|-------------|
| `title` | PR title | Descriptive title of the change |
| `state` | PR state | `open`, `merged`, or `closed` |
| `base` | Base branch | Target branch (usually `main`) |
| `head` | Head branch | Feature branch |
| `labels` | PR labels | e.g., `kind/process-change` |
| `body` | PR body | Description of the change (markdown) |

### Reviews

Reviews use GitHub's native review system via `gh pr review`:

- `gh pr review <number> --approve` — approve the PR
- `gh pr review <number> --request-changes` — request changes

Review comments follow the standard comment format with an explicit status:

```markdown
### <emoji> <role> — <ISO-8601-UTC-timestamp>

**Status: approved**

Review comments here.
```

Valid review statuses: `approved`, `changes-requested`.

---

## PR Lifecycle for Code Changes

Pull requests for project code changes (bug fixes, feature implementations) follow this lifecycle:

### Branch Naming

```
feature/<type>-<issue-number>-<description>
```

Where `<type>` is `bug`, `story`, or `epic` (e.g., `feature/bug-42-fix-null-pointer`).

### PR Format

| Field | Convention |
|-------|------------|
| Title | `[#<issue-number>] <description>` |
| Base | `main` (or earlier PR branch for stacked PRs) |
| Body | Must reference the issue number and summarize the change |

### Draft vs Ready States

- **Draft:** Created during `qe:test-design` or early implementation when work is not yet complete.
- **Ready:** Marked ready when implementation is complete and code review passes at `dev:code-review`.

### PR Stacking

When multiple PRs target `main` and conflicts are expected, or for batching related fixes:

1. First PR bases on `main`
2. Subsequent PRs base on the previous PR's branch
3. Human merges in order — each PR is rebased after the previous one merges

### Merge Authority

The **human is the sole merge authority**. The board scanner at `po:merge`:

1. Checks if the issue has an associated PR that is approved
2. Notifies the human via RObot that the PR is ready to merge
3. Keeps the issue at `po:merge` until the human merges
4. On the next scan after merge is detected, advances the issue to `done`

The board scanner NEVER calls `gh pr merge`.

---

## Communication Protocols

The compact profile uses a single-member self-transition model. All operations use the `github-project` skill:

### Status Transitions

The agent transitions an issue's status by:
1. Using `gh project item-edit` to update the Status field on the project board
2. Adding an attribution comment documenting the transition

The same agent detects the new status on the next board scan cycle (querying the project board via `gh project item-list`) and dispatches the appropriate hat.

### Comments

The agent records work output by:
1. Adding a GitHub issue comment via `gh issue comment` using the standard comment format

### Pull Requests

**Team repo PRs** are for team-level changes:
- Process document updates
- Knowledge file additions or modifications
- Invariant changes

**Project repo PRs** are for code changes:
- Bug fixes
- Feature implementations
- Refactoring

See the "PR Lifecycle for Code Changes" section for branch naming, PR format, and merge conventions.

---

## Team Agreements

All significant process changes, role changes, and team decisions MUST be recorded as team agreements before the change is applied. Agreements provide traceability for why changes were made and who participated in the decision.

- **Decisions** go in `agreements/decisions/` — role changes, process changes, tool adoption
- **Retrospective outcomes** go in `agreements/retros/` — summaries from retrospective sessions
- **Working norms** go in `agreements/norms/` — living team agreements (e.g., "we prefer small PRs")

See `knowledge/team-agreements.md` for the full convention including file format and lifecycle.

---

## Process Evolution

The team process can evolve through two paths:

### Formal Path

1. Create a PR on the team repo proposing the change
2. Review the PR (self-review via lead hat)
3. Approve and merge

### Informal Path

1. Human comments on an issue or the team repo with the change request
2. Agent edits the process file directly
3. Commit the change to the team repo

The informal path is appropriate for urgent corrections or clarifications. The formal path is preferred for significant process changes.
