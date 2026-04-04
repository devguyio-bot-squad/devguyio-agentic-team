# Design: Graduated Autonomy for Human Gates

**Epic:** #112 (sub-epic of #106)
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

The scrum-compact profile hard-codes three human gates: `po:design-review`, `po:plan-review`, `po:accept`. Every epic hits all three regardless of agent output quality. The operator must review and approve at each gate — even when mechanical enforcement (check scripts) and agent-to-agent review (lead reviewer, code reviewer, verifier) have already validated the work.

This epic adds a configurable autonomy tier that progressively reduces human gates as enforcement and quality data prove agent reliability.

### Harness Pattern

> "Humans may review pull requests, but aren't required to. Over time, we've pushed almost all review effort towards being handled agent-to-agent."

> "In a system where agent throughput far exceeds human attention, corrections are cheap, and waiting is expensive."

Harness reached a point where Codex could drive entire features end-to-end — validate, implement, review, merge — with humans stepping in only for judgment calls. This required investment in enforcement and observability first.

**Critical sequencing:** Harness built mechanical enforcement *first*, then graduated. This epic has hard dependencies on #108 (checks) and #113 (metrics).

### Scope

- `autonomy` field in `botminter.yml` manifest
- CLI parsing in `ProfileManifest`
- `po_reviewer` hat behavior changes per tier
- Override mechanism (rejection at any tier)

### Out of Scope

- Ralph Orchestrator engine changes (autonomy is read from manifest, applied in hat behavior)
- Automatic tier promotion (operator decides when to graduate)
- ADR-0011 implementation (per-member identity — compatible but independent)

---

## 2. Architecture

### Three Tiers

| Tier | Human Gates | Prerequisites |
|---|---|---|
| `supervised` (default) | design-review, plan-review, accept | None — current behavior |
| `guided` | accept only | Executable checks passing. Rejection rate <15% at lead review (measured by #113). |
| `autonomous` | none — async notification only | Quality metrics sustained at `guided` for at least one full epic cycle. |

### Manifest-to-Runtime Flow

`team/botminter.yml` IS the runtime config. The codebase reads it via `read_team_repo_manifest()` in `profile/team_repo.rs`. Hats access the team repo at `team/`.

```
1. Extraction: `bm init` writes the `autonomy` field to `team/botminter.yml`
   (default: supervised)

2. Change: Operator updates the field and runs `bm teams sync`.
   Agents CANNOT change this field through normal workflow.

3. Runtime: `po_reviewer` hat reads `team/botminter.yml`, checks `autonomy.tier`.
```

The `ProfileManifest` struct in `crates/bm/src/profile/manifest.rs` gains an `autonomy` field. This is a BotMinter product change — the manifest schema expands. The extraction logic writes the field. The runtime reads it.

---

## 3. Components and Interfaces

### Manifest Extension

```yaml
# team/botminter.yml
autonomy:
  tier: supervised    # supervised | guided | autonomous
```

Default is `supervised`. Only the operator can change this via `bm teams sync`. The field is a BotMinter product feature, not a Ralph configuration.

### po_reviewer Hat Behavior

The `po_reviewer` hat checks the tier when dispatched to a review gate:

**`supervised`** (current behavior):
- Post review request comment
- Wait for human comment (approval or rejection)
- Process human response on next scan cycle

**`guided`**:
- `po:design-review`: auto-advance after lead approval. Post notification: "Design auto-approved (guided tier). Lead review passed. Override: comment 'Rejected: <feedback>'."
- `po:plan-review`: auto-advance after lead approval. Same notification pattern.
- `po:accept`: wait for human comment (same as supervised).

**`autonomous`**:
- All gates: auto-advance. Post notification: "Auto-approved (autonomous tier). Override: comment 'Rejected: <feedback>' or 'Hold'."
- Human retains override capability at every gate.

### Override Mechanism

At any tier:
- `Rejected: <feedback>` on any issue reverts an auto-advance. The issue returns to the previous status with the feedback processed as a rejection.
- `Hold` pauses auto-advance for that specific issue. The issue stays at the review gate until the human comments with approval or rejection.
- Tier changes require `bm teams sync`. Agents cannot escalate their own autonomy — the `autonomy.tier` field in `botminter.yml` is not writable through the normal hat workflow.

### Auth Interaction (ADR-0011)

Auto-advance uses the same GitHub Projects API calls as the current board scanner. When ADR-0011 (per-member GitHub App identity) is implemented, auto-advance transitions are attributed to the member's bot identity. Until then, the shared PAT works. No auth escalation path exists.

---

## 4. Acceptance Criteria

- **Given** `autonomy: { tier: guided }` in `team/botminter.yml`, **when** lead review approves a design, **then** `po:design-review` auto-advances to the next status with a notification comment.
- **Given** `guided` tier and an epic at `po:accept`, **when** the scanner dispatches, **then** the `po_reviewer` waits for human comment (same as supervised).
- **Given** a human comments `Rejected: <feedback>` on an auto-advanced issue, **when** the `po_reviewer` scans, **then** the status reverts and the feedback is processed as a rejection.
- **Given** a human comments `Hold` on an issue in `guided` or `autonomous` tier, **when** the `po_reviewer` scans, **then** auto-advance is paused for that issue.
- **Given** `autonomy: { tier: supervised }` (default), **when** the system operates, **then** behavior is identical to current — no changes.

---

## 5. Impact on Existing System

| Component | Change |
|---|---|
| `team/botminter.yml` | New `autonomy` field (default: supervised) |
| `crates/bm/src/profile/manifest.rs` | Parse `autonomy` field in `ProfileManifest` |
| Profile extraction logic | Write `autonomy` field during `bm init` |
| `po_reviewer` hat instructions (`ralph.yml`) | Read `team/botminter.yml`, vary behavior by tier |
| CLAUDE.md | Document autonomy configuration |

No changes to: Ralph Orchestrator engine, status graph, other hat definitions, formation system, board scanner dispatch logic.

This is pre-alpha. No backward compatibility for the manifest schema change — the field is additive (default: supervised) and existing deployments get current behavior without modification.

---

## 6. Security Considerations

**Autonomy escalation prevention.** The `autonomy.tier` field lives in `team/botminter.yml` and requires `bm teams sync` to change. Agents cannot modify this file through normal workflow — they don't have hat instructions that write to the manifest. The `Rejected:` comment provides an emergency brake at any tier.

**Override priority.** A human `Rejected:` or `Hold` comment always overrides auto-advance, regardless of tier. The override is processed on the next scan cycle.

**Prerequisite enforcement.** The design specifies prerequisites (checks passing, rejection rate <15%) but does not mechanically enforce them — the operator decides when the team is ready to graduate. This is intentional: the operator has context about risk tolerance that metrics alone cannot capture. Metrics (#113) provide the evidence; the human makes the judgment.
