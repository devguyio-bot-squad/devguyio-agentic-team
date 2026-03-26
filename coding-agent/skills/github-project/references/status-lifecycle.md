# Status Lifecycle Reference

Status is tracked as a single-select field on the GitHub Project. Each value below is an option in the project's "Status" field.

## Issue Types (GitHub Native)

Classification uses GitHub's native issue types:

- **Epic** — top-level work item (epic)
- **Task** — child work item (story/subtask), linked as native sub-issue
- **Bug** — bug requiring investigation and fix

Stories are linked to epics as native sub-issues.

## Epic Lifecycle (Epic type)

```
po:triage
    ↓
po:backlog
    ↓
arch:design
    ↓
lead:design-review
    ↓
po:design-review (human gate)
    ↓
arch:plan
    ↓
lead:plan-review
    ↓
po:plan-review (human gate)
    ↓
arch:breakdown
    ↓
lead:breakdown-review
    ↓
po:ready
    ↓
arch:in-progress
    ↓
po:accept (human gate)
    ↓
done
```

## Story Lifecycle (Task type, sub-issue of Epic)

```
qe:test-design
    ↓
dev:implement
    ↓
dev:code-review
    ↓
qe:verify
    ↓
arch:sign-off (auto-advance)
    ↓
po:merge (auto-advance)
    ↓
done
```

## Bug Lifecycle (Bug type)

### Simple Track (80% of bugs)

QE fixes directly, arch reviews, QE validates.

```
bug:investigate
    ↓
arch:review
    ↓ (approve → qe:verify)
    ↓ (escalate → arch:refine, becomes complex track)
qe:verify
    ↓
done
```

### Complex Track (20% of bugs)

QE plans, arch refines, PO approves, arch creates subtasks.

```
bug:investigate
    ↓
arch:refine
    ↓
po:plan-review (human gate)
    ↓ (reject → arch:refine)
bug:breakdown
    ↓
bug:in-progress (monitor subtask completion)
    ↓
qe:verify
    ↓
done
```

Subtasks created during `bug:breakdown` are Task-type sub-issues that flow through the story lifecycle.

## Human Gates

Human approval is required at these statuses:

1. **po:design-review** — PO reviews and approves design (epics)
2. **po:plan-review** — PO reviews and approves plan (epics and complex bugs)
3. **po:accept** — PO accepts completed work (epics)

All other transitions auto-advance without human-in-loop.

## Auto-Advance Statuses

- **arch:sign-off** → `po:merge` (automatic)
- **po:merge** → `done` + issue closed (automatic)

## Rejection Loops

| Gate | Reject target |
|------|---------------|
| `po:design-review` | `arch:design` |
| `po:plan-review` (epic) | `arch:plan` |
| `po:plan-review` (bug) | `arch:refine` |
| `po:accept` | `arch:in-progress` |
| `arch:review` (escalate) | `arch:refine` |
