---
type: design
status: draft
parent: "106"
epic: "119"
revision: 1
created: 2026-04-04
updated: 2026-04-04
author: bob (superman)
depends_on:
  - "114"
  - "117"
---

# Epic #119: Graduated Autonomy for Human Gates

## 1. Overview

### Problem

BotMinter's supervised mode enforces three unconditional human review gates:

| Gate | Status | What's reviewed |
|------|--------|-----------------|
| Design approval | `po:design-review` | Design documents for epics |
| Plan approval | `po:plan-review` | Story breakdowns (epics) and bug plans (complex bugs) |
| Final acceptance | `po:accept` | Completed epic |

These gates are unconditional. The `po_reviewer` hat (ralph.yml lines 86-204) enforces `NEVER auto-approve` — it polls for a human GitHub comment each board scan cycle and takes no action until one appears. There is no risk assessment, no track record evaluation, no distinction between a 2-line documentation change and a cross-module architecture rework.

**Observed consequences in this project:**

- Issues #114, #116, #117, #118 are all parked at `po:design-review` simultaneously. The human must review each one before any can advance. The agent produced 4 designs in ~2 hours; review throughput is bottlenecked on one human.
- The board scanner dispatches `po.review` every cycle for every review-gated issue. The `po_reviewer` hat checks for a human comment, finds none, and returns. This is non-blocking but produces scan noise in `poll-log.txt`.
- The agent cannot distinguish between "this design needs careful scrutiny because it introduces a new dependency" and "this is a well-understood pattern I've successfully delivered 5 times before."

### Solution

Graduate the three human gates from unconditional blocking to risk-based policies. Introduce three autonomy tiers where the behavior of `po_reviewer` changes based on a configurable autonomy level and a per-issue risk assessment:

| Tier | Behavior | When |
|------|----------|------|
| **Supervised** | All gates require human approval (current behavior) | Default. No trust earned yet. |
| **Monitored** | Low-risk gates auto-advance with human notification. Medium/high-risk gates still block. | After sustained track record of approvals without rejection. |
| **Autonomous** | All gates auto-advance with human notification. Human can intervene asynchronously. | After extended period of successful monitored-mode operation. |

The human always receives notification and can always intervene — autonomy changes the default from "block until approved" to "proceed unless stopped."

### Harness Pattern

> "Agents start with zero autonomy. Autonomy is earned through demonstrated reliability, not assumed from capability."

> "When something failed, the fix was almost never 'try harder.' Human engineers always asked: 'what capability is missing, and how do we make it both legible and enforceable for the agent?'"

Harness Engineering principles applied here:
- **Earned autonomy** — The agent starts supervised and graduates based on measurable signals, not operator intuition.
- **Legible decisions** — Every auto-advance is documented with a risk assessment comment explaining WHY the system judged it low-risk. The human can audit the reasoning.
- **Enforceable guardrails** — Check scripts (#114) provide mechanical confidence. Metrics (#117) provide quality data. Autonomy decisions reference both.

### Scope

- Autonomy tier model (supervised → monitored → autonomous)
- Risk classifier for gate decisions (per-issue risk assessment)
- Trust state tracker (accumulates trust signals from #117 metrics)
- Gate policy engine in `po_reviewer` hat instructions
- Configuration via team manifest (`team/botminter.yml`)
- Demotion and circuit breaker safeguards
- Notification protocol for auto-advanced gates
- Hat instruction updates (`po_reviewer`, board scanner documentation)
- Knowledge document for the autonomy model

### Out of Scope

- Modifying the status graph (no new statuses added)
- Changing the `lead_reviewer` gate (AI-only review remains mandatory)
- Autonomy for non-PO gates (e.g., `dev:code-review` is agent-to-agent, not human-gated)
- Per-project autonomy levels (single project initially; multi-project is a future concern)
- Dashboard or UI for autonomy state (file-based is sufficient for pre-alpha)
- Automated promotion (tier upgrades are human-initiated; demotions are automated)

---

## 2. Architecture

### 2.1 System Context

BotMinter's supervised mode operates via a polling loop:

```
Board Scanner
  → sees issue at po:design-review / po:plan-review / po:accept
  → emits po.review event
  → po_reviewer hat activates
    → (today) checks for human comment, acts if found, returns if not
    → (graduated) evaluates gate policy: block, auto-advance, or notify-and-advance
```

The current `po_reviewer` hat has a single code path: check for human comment. This design adds a branching decision before that check.

### 2.2 Gate Decision Flow

```
po_reviewer receives po.review event
  │
  ├─ Read autonomy tier from trust state file
  │
  ├─ If tier == supervised:
  │    → Current behavior (check for human comment, block if absent)
  │
  ├─ If tier == monitored:
  │    ├─ Run risk classifier on the issue
  │    ├─ If risk == LOW:
  │    │    → Auto-advance with notification comment
  │    │    → Log auto-advance in trust state
  │    ├─ If risk == MEDIUM or HIGH:
  │    │    → Current behavior (block for human approval)
  │    └─ End
  │
  └─ If tier == autonomous:
       ├─ Run risk classifier on the issue
       ├─ Auto-advance with notification comment (all risk levels)
       ├─ Log auto-advance in trust state
       └─ If risk == HIGH:
            → Add prominent warning to notification comment
            → Send Telegram notification (if RObot enabled)
```

### 2.3 Trust State Architecture

```
Trust State File                    Risk Classifier              Gate Policy
────────────────                    ───────────────              ───────────

team/projects/<project>/            Issue metadata ──┐
  autonomy/                         (type, labels,   │
    trust-state.yml                  files changed,  │
    ├── tier: monitored              dependencies,   ├──► risk: LOW|MEDIUM|HIGH
    ├── promoted_at: ISO date        check results)  │
    ├── approvals_since_last: N      │               │
    ├── rejections_since_last: N     └───────────────┘
    ├── auto_advances: []                    │
    └── demotions: []                        │
                                             ▼
                                    Gate Policy Decision
                                    ├── block (wait for human)
                                    ├── auto-advance + notify
                                    └── auto-advance + warn + notify
```

### 2.4 Component Interaction

Three new components, all consumed by the `po_reviewer` hat:

1. **Trust state file** — YAML file tracking the current autonomy tier and its history. Human-editable. The single source of truth for the current tier.
2. **Risk classifier** — Shell script that assesses an issue's risk level based on observable signals.
3. **Gate policy** — Logic in the `po_reviewer` hat instructions that combines tier + risk to decide behavior.

No new hats, no new statuses, no new events. The `po_reviewer` hat gains conditional logic based on the trust state and risk assessment.

---

## 3. Components and Interfaces

### 3.1 Trust State File

**Location:** `team/projects/<project>/autonomy/trust-state.yml`

```yaml
# Autonomy configuration for project
tier: supervised          # supervised | monitored | autonomous
promoted_at: null         # ISO date of last tier promotion (null if never promoted)
promoted_by: human        # who promoted: always "human" (promotions are human-initiated)
demotion_cooldown: 0      # cycles remaining before re-evaluation after demotion

# Cumulative counters (reset on promotion)
stats:
  approvals: 0            # human approvals since last promotion
  rejections: 0           # human rejections since last promotion
  auto_advances: 0        # auto-advances since last promotion (monitored/autonomous only)
  auto_advance_reversals: 0  # auto-advances the human later reversed

# History (append-only, last 20 entries)
history:
  - ts: "2026-04-04T12:00:00Z"
    event: "initialized"
    tier: "supervised"
    reason: "Project created"
```

**Who writes:**
- `po_reviewer` — updates stats after each approval, rejection, or auto-advance
- Human — edits `tier` field directly to promote (committed to team repo)
- `po_reviewer` — writes demotion events (automated demotion on rejection)

**Who reads:**
- `po_reviewer` — reads tier and stats at the start of each gate check

### 3.2 Risk Classifier

**Script:** `team/coding-agent/skills/autonomy/classify-risk.sh`

**Input:** Project name, issue number

**Output:** JSON to stdout:

```json
{
  "risk": "LOW",
  "signals": {
    "issue_type": "Epic",
    "gate": "po:design-review",
    "scope_files": 3,
    "new_dependencies": false,
    "cross_module": false,
    "has_security_section": true,
    "check_scripts_pass": true,
    "prior_rejections": 0,
    "pattern_novelty": "known"
  },
  "reasoning": "Design for documentation-only epic, no new dependencies, all check scripts pass, pattern seen 3 times before"
}
```

**Risk classification rules:**

| Signal | LOW | MEDIUM | HIGH |
|--------|-----|--------|------|
| Issue type at gate | `po:accept` for docs-only epic | Standard epic/story | — |
| Prior rejections on this issue | 0 | 1 | >=2 |
| Design scope (files listed in impact section) | <=5 files | 6-15 files | >15 files or "No changes to" lists fewer exclusions |
| New dependencies introduced | No | — | Yes |
| Cross-module changes | No | Single direction | Bidirectional or circular |
| Check scripts (if #114 is deployed) | All pass | — | Any violation |
| Pattern novelty | Known pattern (similar issue succeeded before) | Variant of known pattern | First time this pattern is attempted |
| Security section flags concerns | No concerns | Mitigated concerns | Unmitigated or missing |

**Composite rule:**
- **LOW:** All signals are LOW, no signals are HIGH
- **HIGH:** Any signal is HIGH
- **MEDIUM:** Everything else

The classifier reads the issue body, comments, and related design doc to extract signals. It uses the `github-project` skill to query the issue. If `run-checks.sh` exists (from #114), it runs it and includes the result. If metrics are available (from #117), it reads rejection rate for the project.

**Pattern novelty detection:**

The classifier checks `team/projects/<project>/autonomy/trust-state.yml` history for previous auto-advances at the same gate for issues with similar characteristics (same issue type, similar scope). If >=3 prior successful auto-advances exist for similar issues, the pattern is "known". If 1-2 exist, "variant". If 0, "first time".

### 3.3 Gate Policy in `po_reviewer`

The `po_reviewer` hat instructions gain a new decision block at the top of its workflow:

```
### Gate Policy (Graduated Autonomy)

Before checking for human response, evaluate the gate policy:

1. Read the trust state file at `team/projects/<project>/autonomy/trust-state.yml`.
   If the file doesn't exist, treat as tier=supervised.

2. If tier == supervised:
   → Proceed to human comment check (current behavior). Stop here.

3. Run the risk classifier:
   bash team/coding-agent/skills/autonomy/classify-risk.sh <project> --issue <N>

4. If tier == monitored AND risk == LOW:
   → Auto-advance (see auto-advance procedure below)

5. If tier == monitored AND risk != LOW:
   → Proceed to human comment check (current behavior)

6. If tier == autonomous:
   → Auto-advance (see auto-advance procedure below)
   → If risk == HIGH, add warning flag to notification

### Auto-Advance Procedure

1. Post an auto-advance notification comment (see format below)
2. Set the issue's project status to the approval target:
   - po:design-review → arch:plan
   - po:plan-review → arch:breakdown (Epic) or bug:breakdown (Bug)
   - po:accept → done (and close issue)
3. Update trust-state.yml: increment stats.auto_advances, append history entry
4. Send Telegram notification (if RObot enabled): "Auto-advanced issue #N
   at <gate>. Risk: <level>. Review the decision at <issue-url>"
```

### 3.4 Auto-Advance Notification Comment

```markdown
### 📝 po — <ISO-timestamp>

**Auto-advanced** (tier: monitored, risk: LOW)

Gate: po:design-review → arch:plan
Risk assessment: LOW
Signals: scope=3 files, no new deps, checks pass, pattern seen 4x before

This was auto-advanced per the graduated autonomy policy. To reverse:
- Comment `Rejected: <feedback>` on this issue
- The system will revert the status and record the reversal

Full risk assessment: [risk classifier output summary]
```

For HIGH-risk auto-advances (autonomous tier only):

```markdown
### 📝 po — <ISO-timestamp>

**Auto-advanced** (tier: autonomous, risk: HIGH)

**WARNING: This is a high-risk auto-advance. Please review promptly.**

Gate: po:design-review → arch:plan
Risk assessment: HIGH
Signals: 2 prior rejections, new dependency introduced, first-time pattern
Reasoning: [classifier reasoning]

To reverse:
- Comment `Rejected: <feedback>` on this issue within 24 hours
- The system will revert the status, record the reversal, and evaluate demotion
```

### 3.5 Asynchronous Reversal Mechanism

Even after auto-advance, the human can still reject. The `po_reviewer` hat gains a **post-advance scan**:

On each scan cycle, before checking for new review gates, the `po_reviewer` checks recently auto-advanced issues (from `trust-state.yml` history, last 48 hours) for human reversal comments:

1. Read auto-advance entries from trust-state history (last 48 hours)
2. For each auto-advanced issue, check for a human comment containing `rejected` posted after the auto-advance timestamp
3. If found:
   - Revert the issue status to the pre-auto-advance state (e.g., `arch:plan` back to `po:design-review`)
   - Wait — no, revert to the rejection target (e.g., `po:design-review` rejection goes to `arch:design`)
   - Increment `stats.auto_advance_reversals`
   - Evaluate demotion (see Section 3.6)
   - Post a comment documenting the reversal

This ensures the human's "last word" is always honored, even after auto-advance.

### 3.6 Demotion and Circuit Breakers

**Automated demotion triggers:**

| Trigger | Action |
|---------|--------|
| Any rejection at monitored tier (human rejects an issue that was NOT auto-advanced) | Demote to supervised. Reset stats. Set `demotion_cooldown: 10` cycles. |
| Any auto-advance reversal at monitored tier | Demote to supervised. Reset stats. Set `demotion_cooldown: 20` cycles. |
| Any auto-advance reversal at autonomous tier | Demote to monitored (not all the way to supervised). Set `demotion_cooldown: 10` cycles. |
| 2 auto-advance reversals within 7 days at autonomous tier | Demote to supervised. Reset stats. Set `demotion_cooldown: 30` cycles. |

**Demotion procedure:**
1. Update trust-state.yml: set new tier, reset stats, set cooldown, append history
2. Post comment on the triggering issue documenting the demotion
3. Send Telegram notification: "Autonomy demoted from <old> to <new> for project <project>. Reason: <trigger>. Cooldown: N cycles."

**Demotion cooldown:** After demotion, the `demotion_cooldown` counter decrements each scan cycle. During cooldown, the system stays at the demoted tier regardless of stats. This prevents oscillation.

**Promotion is always human-initiated.** The system never self-promotes. The human edits `trust-state.yml` to change the tier. This is a deliberate asymmetry: demotion is automated (safety), promotion is manual (trust).

### 3.7 Promotion Guidance

While promotion is human-initiated, the system surfaces readiness signals. When the `po_reviewer` hat finds the system at supervised tier with `demotion_cooldown: 0` and `stats.approvals >= 5` and `stats.rejections == 0`, it adds a one-time comment:

```markdown
### 📝 po — <ISO-timestamp>

**Promotion readiness:** This project has 5 consecutive approvals with 0 rejections
at the supervised tier. It may be ready for monitored tier.

To promote, edit `team/projects/<project>/autonomy/trust-state.yml` and set
`tier: monitored`. Commit the change.
```

This comment is added at most once per supervised period (tracked via a flag in trust-state history).

---

## 4. Data Models

### 4.1 Trust State Schema (YAML)

```yaml
tier: string              # "supervised" | "monitored" | "autonomous"
promoted_at: string|null  # ISO 8601 UTC timestamp or null
promoted_by: string       # always "human"
demotion_cooldown: int    # scan cycles remaining (0 = no cooldown)

stats:
  approvals: int          # human approvals since last tier change
  rejections: int         # human rejections since last tier change
  auto_advances: int      # auto-advances since last tier change
  auto_advance_reversals: int  # reversals since last tier change

history:                  # append-only, keep last 20 entries
  - ts: string            # ISO 8601 UTC
    event: string         # "initialized" | "approval" | "rejection" | "auto_advance"
                          #   | "reversal" | "promotion" | "demotion" | "readiness_notified"
    tier: string          # tier at time of event
    issue: int|null       # issue number (null for initialization)
    gate: string|null     # gate status (null for initialization)
    risk: string|null     # "LOW" | "MEDIUM" | "HIGH" (null when not applicable)
    reason: string        # human-readable reason
```

### 4.2 Risk Assessment Output Schema (JSON)

```json
{
  "risk": "LOW | MEDIUM | HIGH",
  "signals": {
    "issue_type": "string",
    "gate": "string",
    "scope_files": "int",
    "new_dependencies": "bool",
    "cross_module": "bool",
    "has_security_section": "bool",
    "check_scripts_pass": "bool | null",
    "prior_rejections": "int",
    "pattern_novelty": "known | variant | first_time"
  },
  "reasoning": "string"
}
```

### 4.3 File Layout

```
team/projects/<project>/
  autonomy/
    trust-state.yml        # Current tier + stats + history
  metrics/                 # From #117
    ...
  knowledge/
    designs/
      epic-119.md          # This design doc
```

---

## 5. Error Handling

- **Missing trust-state.yml:** If the file doesn't exist, `po_reviewer` treats the project as `tier: supervised`. First gate event creates the file with `tier: supervised` and an `initialized` history entry. No special setup needed.

- **Risk classifier failure:** If `classify-risk.sh` fails (exits non-zero without valid JSON), the gate falls back to `tier: supervised` behavior (block for human approval). A warning is logged in the issue comment: "Risk classifier unavailable — defaulting to supervised gate." This ensures the system fails safe.

- **Malformed trust-state.yml:** If the YAML is unparseable, treat as `tier: supervised`. Log a warning. Do not overwrite the file — the human may need to inspect the corruption.

- **Check scripts unavailable (#114 not deployed):** The risk classifier treats missing check runner as a neutral signal (`check_scripts_pass: null`). The classifier does not require #114 — it works without it, just with less confidence.

- **Metrics unavailable (#117 not deployed):** The risk classifier works without metrics. Pattern novelty falls back to "variant" (conservative default) when no history data exists. Rejection rate defaults to "unknown" rather than "zero."

- **Race condition on trust-state.yml:** The `po_reviewer` hat processes one gate per cycle (board scanner dispatches one event at a time). No concurrent writes to trust-state.yml. If the team repo has merge conflicts on this file, the latest `tier` value wins (take the more conservative tier if ambiguous).

- **Human edits trust-state.yml incorrectly:** If `tier` is set to an invalid value, treat as `supervised`. If `stats` are inconsistent, the hat resets them on the next update. Trust-state is a coordination artifact, not a security boundary — the human can always fix it.

- **Telegram notification failure:** Non-blocking. If RObot is unavailable, the auto-advance still proceeds. The GitHub comment is the authoritative record; Telegram is convenience.

---

## 6. Acceptance Criteria

- **Given** a project at `supervised` tier, **when** the `po_reviewer` hat activates for `po:design-review`, **then** it blocks for human comment exactly as it does today — no behavioral change.

- **Given** a project at `monitored` tier and an issue classified as LOW risk, **when** the `po_reviewer` hat activates for `po:design-review`, **then** it auto-advances the status to `arch:plan`, posts a notification comment with the risk assessment, and updates `trust-state.yml`.

- **Given** a project at `monitored` tier and an issue classified as MEDIUM risk, **when** the `po_reviewer` hat activates for `po:plan-review`, **then** it blocks for human comment (same as supervised).

- **Given** a project at `autonomous` tier and an issue classified as HIGH risk, **when** the `po_reviewer` hat activates, **then** it auto-advances but includes a prominent warning in the notification comment and sends a Telegram notification.

- **Given** a human posts `Rejected: <feedback>` on an auto-advanced issue within 48 hours, **when** the `po_reviewer` scans on the next cycle, **then** it reverts the status to the rejection target (e.g., `arch:design`), increments `auto_advance_reversals`, and evaluates demotion.

- **Given** any auto-advance reversal at `monitored` tier, **when** the reversal is processed, **then** the tier is demoted to `supervised`, stats are reset, `demotion_cooldown` is set to 20, and a demotion comment is posted.

- **Given** a project at `supervised` tier with 5 approvals and 0 rejections and `demotion_cooldown == 0`, **when** the `po_reviewer` completes a gate check, **then** a one-time readiness notification comment is posted suggesting promotion to `monitored`.

- **Given** the risk classifier script fails, **when** `po_reviewer` catches the error, **then** it falls back to supervised behavior and logs a warning — no auto-advance occurs.

- **Given** `trust-state.yml` does not exist, **when** the `po_reviewer` hat first activates, **then** it creates the file with `tier: supervised` and proceeds with supervised behavior.

---

## 7. Impact on Existing System

| Component | Change |
|-----------|--------|
| `po_reviewer` hat instructions (ralph.yml) | Gate policy decision block before human comment check. Auto-advance procedure. Post-advance reversal scan. Demotion logic. Promotion readiness notification. |
| `team/coding-agent/skills/autonomy/` | New directory with `classify-risk.sh` |
| `team/projects/<project>/autonomy/` | New directory with `trust-state.yml` (created on first use) |
| `team/knowledge/` | New `graduated-autonomy.md` knowledge document describing the tier model |
| Board scanner documentation | Updated to note that `po.review` dispatch behavior depends on autonomy tier |
| `team/PROCESS.md` (Supervised Mode section) | Updated to reference graduated autonomy as an evolution of the fixed gates |
| `team/members/superman-bob/CLAUDE.md` (Operating Mode) | Updated to reference graduated autonomy |
| Communication protocols | Updated notification format for auto-advance comments |

**No changes to:** Ralph Orchestrator, BotMinter CLI (`bm`), agent CLI (`bm-agent`), daemon/web console, existing status graph (no new statuses), `lead_reviewer` hat (AI review gate remains mandatory), `po_backlog` hat, story-level gates (`dev:code-review`, `qe:verify`), existing invariant files, existing test infrastructure, check script system (#114), plan artifact system (#116), metrics system (#117), gardening system (#118).

**Key non-change:** The `lead_reviewer` gate (`lead:design-review`, `lead:plan-review`) is unaffected. AI-to-AI review remains mandatory at all tiers. Graduated autonomy applies only to the human gates (`po:*-review`, `po:accept`).

---

## 8. Security Considerations

**Trust-state.yml is a coordination artifact, not a security boundary.** An attacker who can edit this file can set `tier: autonomous` and bypass human review. This is the same trust model as all team repo files — the team repo is write-restricted to authorized members and their agents. The trust-state file adds no new trust boundary.

**Auto-advance does not bypass the AI review gate.** The `lead_reviewer` hat reviews all designs and plans before they reach the PO gate. Graduated autonomy affects only the human gate after the AI gate. A LOW-risk auto-advance means the design was already AI-reviewed and found acceptable.

**Demotion is automated; promotion is manual.** This asymmetry is a security design choice. The system can only reduce its own autonomy (fail safe). Increasing autonomy requires a deliberate human decision.

**Risk classifier output is logged.** Every auto-advance comment includes the full risk assessment. If the classifier produces incorrect assessments, the audit trail in issue comments shows exactly what signals were evaluated and why the system chose to auto-advance. This makes risk classifier bugs visible and auditable.

**No new external access.** The risk classifier reads issue metadata via the existing `github-project` skill. The trust state is a local YAML file. No new API calls, no new network access, no new credentials.

**Reversal window limits exposure.** Auto-advanced work that the human later rejects is caught within 48 hours. The downstream work (story planning, implementation) proceeds in parallel, but the reversal mechanism ensures the human's rejection is honored. This bounds the blast radius of a bad auto-advance.

**Prompt injection risk:** The risk classifier reads issue bodies and design docs to extract signals. These are the same inputs the `po_reviewer` already reads. No new prompt injection surface. The classifier parses structured signals (file counts, dependency lists), not natural language instructions.
