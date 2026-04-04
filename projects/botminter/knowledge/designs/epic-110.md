# Design: Automated Codebase Gardening

**Epic:** #110 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

BotMinter's codebase evolved through multiple methodology phases. Planning artifacts exist across `.planning/` (11 ADRs, 7 architecture docs, milestone plans, specs, research, debug docs, proposals), `docs/`, and team knowledge directories. No process detects stale documentation, duplicated utility code, or quality drift.

Agents replicate existing patterns — including suboptimal ones. Without active cleanup, drift compounds.

This epic adds an `arch_gardener` hat that runs on idle board cycles, scanning for quality issues and opening targeted fix issues through the normal dev pipeline.

### Harness Pattern

> "Our team used to spend every Friday (20% of the week) cleaning up 'AI slop.' Unsurprisingly, that didn't scale. Instead, we started encoding what we call 'golden principles' directly into the repository and built a recurring cleanup process."

> "Technical debt is like a high-interest loan: it's almost always better to pay it down continuously in small increments than to let it compound."

Harness runs regular background tasks that scan for deviations from golden principles, update quality grades, and open targeted refactoring PRs — most reviewable in under a minute and automerged. BotMinter's gardener does the same through the existing issue lifecycle.

### Scope

- `arch_gardener` hat definition
- Board scanner scheduling (gardener.scan event)
- Golden principles config (mechanical + judgment-based)
- Documentation freshness scanning
- Weekly metrics report triggering (coordinates with #113)

### Out of Scope

- The check runner itself (that's #108 — the gardener uses it)
- Harness-style quality grades per domain (future enhancement)

---

## 2. Architecture

### Scheduling and Board Coexistence

The gardener is the **lowest-priority dispatch item**. It only runs when:
1. No issue on the board is at a dispatch-ready status
2. The scan cycle counter reaches the configured interval

The board scanner skill gains a `gardener.scan` dispatch entry. This is a profile-level change — it modifies the scanner skill's instructions and adds a new event type.

**Scheduling mechanism:**
- The scanner tracks a cycle counter in its scratchpad
- A knowledge file (`team/knowledge/gardener-config.md`) specifies the interval (e.g., run every 10 scan cycles)
- When counter reaches interval AND board is idle: emit `gardener.scan`
- If any issue is dispatch-ready: issue takes precedence, counter is not reset

**Coexistence guarantee:** The gardener never blocks issue processing. If a new issue enters the board during a gardener cycle, the scanner dispatches the issue next. The gardener's output IS issues — violations flow through `dev:implement` -> `dev:code-review` -> `qe:verify`.

### Gardener Hat Activities

```
gardener.scan received
  → Run check runner (Feature #108) — aggregate static violation results
  → Scan code against golden principles — detect pattern violations
  → Check documentation freshness — do referenced files/functions still exist?
  → Check metrics report freshness — >7 days since last report?
  → Open targeted issues for violations (specific files, specific fixes)
  → Create cw:write issue if metrics report is due
```

---

## 3. Components and Interfaces

### Golden Principles

A YAML file at `projects/<project>/invariants/golden-principles.yml`, split by enforcement:

**Mechanically checkable** — each becomes a check script (reuses #108 infrastructure):

```yaml
principles:
  mechanically_checkable:
    - name: consistent-error-handling
      description: "Use anyhow for application errors, thiserror for library errors"
      check_script: "consistent-error-handling.sh"
      remediation: "Standardize on the crate's chosen error strategy"
```

**Judgment-based** — the gardener applies LLM judgment. This is honest: these are trust-based, same as prose invariants, but centralized and applied on a recurring schedule by a dedicated hat:

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

The `detection_hint` tells the gardener what to look for. The distinction from scattered prose invariants: golden principles are centralized, versioned, and applied on a recurring schedule.

### Documentation Freshness

The gardener checks knowledge files and docs for stale references:
- Do referenced file paths still exist?
- Do referenced function/type names still exist in the codebase?
- Are ADR status fields current?

Stale references produce fix-up issues with the specific file, the stale reference, and what needs updating.

### Metrics Report Trigger

The gardener checks file timestamps in `team/projects/<project>/knowledge/reports/`. If >7 days since the last report, it creates a `cw:write` issue. This flows through normal dispatch to `cw_writer`, which reads the transition JSONL (#113) and generates a summary.

### Gardener Hat Definition

Added to `ralph.yml` as `arch_gardener`:
- Triggered by `gardener.scan` event
- Hat instructions specify: run check runner, scan golden principles, check freshness, open issues
- Issues created by the gardener flow through the normal dev pipeline (never self-merged)

---

## 4. Acceptance Criteria

- **Given** the board has no actionable issues and the gardener interval is reached, **when** the scanner dispatches, **then** `gardener.scan` fires.
- **Given** the gardener scans and finds duplicated utility code matching a golden principle, **then** it opens an issue naming specific files, the principle violated, and a remediation plan.
- **Given** a knowledge file references a function that was renamed, **when** the freshness check runs, **then** a fix-up issue is opened with the stale reference and the current name.
- **Given** an active story enters the board during a gardener cycle, **when** the scanner dispatches next, **then** the story takes priority over the gardener.
- **Given** >7 days since the last metrics report, **when** the gardener runs, **then** it creates a `cw:write` issue for the weekly summary.
- **Given** the gardener scan fails, **when** the next cycle runs, **then** it retries (max 3 retries before flagging for human attention).

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| `ralph.yml` hats | New `arch_gardener` hat definition |
| Board scanner skill instructions | Add `gardener.scan` dispatch entry + cycle counter + idle check |
| `team/knowledge/gardener-config.md` | New config file (scan interval) |
| `projects/<project>/invariants/golden-principles.yml` | New golden principles config |
| `team/projects/<project>/knowledge/reports/` | New directory for weekly reports |

No changes to: Ralph Orchestrator engine, existing hat definitions (gardener is additive), status graph (no new statuses), formation system.

The gardener is a profile-level orchestration change: it adds a hat, a dispatch entry, and a scheduling mechanism to the board scanner skill. It does not change Ralph's core event loop or dispatch engine.

---

## 6. Security Considerations

The gardener is read-only for scanning and creates issues for violations. All fixes flow through the normal `dev:implement` -> `dev:code-review` -> `qe:verify` pipeline — the gardener never merges its own changes. Golden principles are version-controlled. The gardener cannot modify check scripts, invariants, or golden principles — it only reads them and opens issues when violations are found. Gardener failures are bounded (max 3 retries) and never block other work.
