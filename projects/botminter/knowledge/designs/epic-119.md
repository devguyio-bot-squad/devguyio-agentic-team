---
type: design
status: draft
parent: "106"
epic: "119"
revision: 2
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
- Reversal cascade mechanism for downstream work invalidation
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
    ├── bootstrap_remaining: 2       │               │
    ├── approvals_since_last: N      └───────────────┘
    ├── rejections_since_last: N             │
    ├── auto_advances: []                    │
    └── demotions: []                        ▼
                                    Gate Policy Decision
                                    ├── block (wait for human)
                                    ├── auto-advance + notify
                                    └── auto-advance + warn + notify
```

### 2.4 Component Interaction

Three new components, all consumed by the `po_reviewer` hat:

1. **Trust state file** — YAML file tracking the current autonomy tier, bootstrap window, and history. Human-editable. The single source of truth for the current tier.
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

# Bootstrap window (rev 2)
# When tier is promoted to monitored, bootstrap_remaining is set to 3.
# During bootstrap, pattern_novelty is excluded from the composite risk rule.
# Each successful auto-advance decrements bootstrap_remaining by 1.
# When bootstrap_remaining reaches 0, pattern_novelty becomes a full signal.
bootstrap_remaining: 0    # remaining bootstrap auto-advances (0 = bootstrap complete)

# Reversal window configuration (rev 2)
# "next_gate" = reversal allowed until the issue reaches its next human gate
# or can be set to a number of hours (e.g., 72) for time-based window
reversal_window: next_gate  # "next_gate" | integer (hours)

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
- `po_reviewer` — reads tier, bootstrap_remaining, and stats at the start of each gate check

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
    "prior_rejections_at_gate": 0,
    "pattern_novelty": "known",
    "pattern_novelty_excluded": false
  },
  "reasoning": "Design for documentation-only epic, no new dependencies, all check scripts pass, pattern seen 3 times before"
}
```

**Risk classification rules:**

| Signal | LOW | MEDIUM | HIGH |
|--------|-----|--------|------|
| Issue type at gate | `po:accept` for docs-only epic | Standard epic/story | — |
| Prior rejections at this gate (see 3.2.1) | 0 | 1 | >=2 |
| Design scope (files listed in impact section) | <=5 files | 6-15 files | >15 files or "No changes to" lists fewer exclusions |
| New dependencies introduced | No | — | Yes |
| Cross-module changes | No | Single direction | Bidirectional or circular |
| Check scripts (if #114 is deployed) | All pass | — | Any violation |
| Pattern novelty (see 3.2.2) | Known (>=3 prior successes) | Variant (1-2 prior) | First time (0 prior) |
| Security section flags concerns | No concerns | Mitigated concerns | Unmitigated or missing |

**Composite rule:**
- **HIGH:** Any signal is HIGH
- **LOW:** No signals are HIGH AND no signals are MEDIUM — except during bootstrap (see 3.2.2), where pattern_novelty is excluded from this check
- **MEDIUM:** Everything else

The classifier reads the issue body, comments, and related design doc to extract signals. It uses the `github-project` skill to query the issue. If `run-checks.sh` exists (from #114), it runs it and includes the result. If metrics are available (from #117), it reads rejection rate for the project.

#### 3.2.1 Prior Rejections Scope (rev 2)

"Prior rejections at this gate" is defined as: the number of human rejection comments on *this specific issue* that occurred *at the current gate status*. The classifier counts comments matching the rejection pattern (e.g., `Rejected:`) that were posted between the most recent transition INTO the current gate and now.

This is a **per-gate, per-issue** count. A rejection at `po:design-review` does NOT inflate the risk when the same issue later reaches `po:plan-review` — the design was revised and approved before advancing, so the prior rejection is no longer relevant.

Auto-advance reversals are NOT counted as "prior rejections" for this signal. Reversals are tracked separately in `trust-state.yml` stats and contribute to demotion decisions, not per-issue risk classification.

The `trust-state.yml` flat `stats.rejections` counter tracks project-wide rejection count for demotion/promotion decisions. The risk classifier's per-issue count is derived from issue comments, not from trust-state.yml.

#### 3.2.2 Bootstrap Window for Pattern Novelty (rev 2)

Pattern novelty creates a bootstrapping problem: a freshly-promoted monitored tier has zero auto-advance history, so pattern novelty starts at "first_time" (HIGH). The composite rule requires no HIGH signals for LOW risk. Monitored tier only auto-advances LOW risk. Result: the first auto-advance can never happen.

**Solution: Bootstrap window.** When the tier is promoted to monitored, `bootstrap_remaining` is set to 3.

During the bootstrap window (`bootstrap_remaining > 0`):
- Pattern novelty is **still evaluated** and **still reported** in the risk assessment output (with `"pattern_novelty_excluded": true`)
- Pattern novelty is **excluded from the composite rule** — it does not contribute to the LOW/MEDIUM/HIGH classification
- If pattern novelty would have been HIGH, the notification comment includes a note: "Pattern novelty (first_time) was excluded during bootstrap window. N bootstrap auto-advances remaining."
- Each successful auto-advance decrements `bootstrap_remaining` by 1
- If an auto-advance is later reversed, `bootstrap_remaining` is NOT restored (the reversal already triggers demotion, which resets everything)

After bootstrap (`bootstrap_remaining == 0`):
- Pattern novelty is a full composite signal as originally designed
- By this point, at least 3 auto-advances have succeeded, providing history for the pattern classifier to assess similarity

**Bootstrap only applies to monitored tier.** The autonomous tier auto-advances all risk levels, so pattern novelty doesn't gate decisions there. If a monitored-tier demotion occurs, the bootstrap counter is irrelevant (tier drops to supervised; when re-promoted, a fresh bootstrap_remaining: 3 is set).

**Pattern novelty detection:**

The classifier checks `team/projects/<project>/autonomy/trust-state.yml` history for previous auto-advances at the same gate for issues with similar characteristics (same issue type, similar scope). If >=3 prior successful auto-advances exist for similar issues, the pattern is "known". If 1-2 exist, "variant". If 0, "first_time".

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
   - If bootstrap_remaining > 0, decrement it by 1
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
- The system will revert the status, cascade to downstream work, and record the reversal

Full risk assessment: [risk classifier output summary]
```

For bootstrap auto-advances (monitored tier, `bootstrap_remaining > 0`):

```markdown
### 📝 po — <ISO-timestamp>

**Auto-advanced** (tier: monitored, risk: LOW — bootstrap window)

Gate: po:design-review → arch:plan
Risk assessment: LOW (pattern novelty excluded during bootstrap; 2 bootstrap auto-advances remaining)
Signals: scope=3 files, no new deps, checks pass
Note: Pattern novelty = first_time (excluded from composite during bootstrap)

To reverse: comment `Rejected: <feedback>` on this issue.
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
- Comment `Rejected: <feedback>` on this issue
- Downstream work will be cascaded (see reversal cascade)
- The system will evaluate demotion
```

### 3.5 Asynchronous Reversal Mechanism (rev 2)

Even after auto-advance, the human can still reject. The `po_reviewer` hat gains a **post-advance scan**:

On each scan cycle, before checking for new review gates, the `po_reviewer` checks recently auto-advanced issues for human reversal comments.

#### 3.5.1 Reversal Window (rev 2)

The reversal window is configurable via `trust-state.yml` field `reversal_window`:

- **`next_gate`** (default): Reversal is allowed until the issue reaches its next human gate (`po:plan-review` after `po:design-review`, `po:accept` after `po:plan-review`). At the next gate, the human gets a fresh opportunity to review, making reversal of the previous gate unnecessary. For `po:accept`, since there is no subsequent gate, the window defaults to 168 hours (7 days).
- **Integer (hours)**: A fixed time window (e.g., `72` for 72 hours). After the window expires, reversal is no longer scanned. The human can still reject at the next gate.

**Why `next_gate` is the default:** The fixed 48-hour window (rev 1) was unjustified — no data supports that duration, and it expires before the human may even look at the issue (weekends, vacations). The `next_gate` semantic is self-adjusting: fast pipelines have short windows, slow ones have long windows, and the human always gets at least one opportunity to intervene at each stage. The time-based option exists as an override for teams that prefer explicit deadlines.

#### 3.5.2 Reversal Scan Procedure

1. Read auto-advance entries from trust-state history
2. For each auto-advanced issue still within its reversal window:
   a. Check for a human comment containing `Rejected:` posted after the auto-advance timestamp
   b. If found:
      - Run the **reversal cascade** (see 3.5.3)
      - Revert the issue status to the rejection target (e.g., `po:design-review` rejection goes to `arch:design`)
      - If the auto-advance closed the issue (`po:accept → done`), **reopen the issue first** before reverting the status
      - Increment `stats.auto_advance_reversals`
      - Evaluate demotion (see Section 3.6)
      - Post a comment documenting the reversal and listing affected downstream work

#### 3.5.3 Reversal Cascade — Downstream Work Invalidation (rev 2)

When an auto-advance is reversed, downstream work that was built on the auto-advanced gate decision may now be invalid. The reversal procedure MUST identify and handle downstream artifacts.

**Cascade procedure:**

1. **Identify downstream issues:** Query for sub-issues (stories, subtasks) of the reversed issue that were created or transitioned AFTER the auto-advance timestamp.

2. **Classify each downstream issue by status:**

   | Downstream status | Action |
   |-------------------|--------|
   | Before `dev:implement` (e.g., `qe:test-design`, `sre:infra-setup`, `dev:implement` not started) | Close as "not planned" with reversal comment |
   | At or past `dev:implement` (active development in progress) | Post warning comment but leave open. Include: "Parent issue #N was reversed at <gate>. Human decision required: continue, adapt, or close." |
   | `done` (already completed) | Post warning comment. Include: "Parent issue #N was reversed. This completed work may need revision." |

3. **Handle associated PRs:** If any PRs reference reversed downstream issues, post a comment on each PR: "Parent epic #N was reversed at <gate>. This PR may no longer be valid."

4. **Handle plan artifacts:** If the reversed gate is `po:design-review`, any plan breakdown document at `team/projects/<project>/knowledge/plans/epic-<N>.md` is flagged by prepending a YAML front-matter field: `invalidated_by_reversal: true, reversal_ts: <timestamp>`.

5. **Post cascade summary:** On the reversed issue, post a summary listing all affected downstream work:

   ```markdown
   ### 📝 po — <ISO-timestamp>

   **Reversal cascade for issue #N**

   Gate reversed: po:design-review (auto-advanced at <ts>, reversed at <ts>)
   Reason: <human's rejection comment>

   Downstream impact:
   - #201 "Story A" — closed (was at qe:test-design)
   - #202 "Story B" — closed (was at dev:implement, not started)
   - #203 "Story C" — WARNING: active development (at dev:implement)
   - PR #15 — warning comment posted

   Human review needed for items marked WARNING.
   ```

**Design rationale:** The cascade deliberately does NOT auto-close issues past `dev:implement` because significant work may have been invested. Closing active development without human input could waste completed work that is still valid despite the parent design changing. The warning-and-wait approach bounds blast radius while respecting sunk work.

**Blast radius acknowledgment (rev 2):** Auto-advancing trades review latency for reversal cost. A reversed auto-advance at `po:design-review` that cascades to 8 child stories is more expensive to unwind than blocking would have been. This is an intentional trade-off: the system earns autonomy by demonstrating that reversals are rare. If reversals are frequent, demotion triggers (Section 3.6) pull the system back to supervised mode before cascade costs accumulate.

### 3.6 Demotion and Circuit Breakers

**Automated demotion triggers:**

| Trigger | Action |
|---------|--------|
| Any rejection at monitored tier (human rejects an issue that was NOT auto-advanced) | Demote to supervised. Reset stats. Set `demotion_cooldown: 10` cycles. |
| Any auto-advance reversal at monitored tier | Demote to supervised. Reset stats. Set `demotion_cooldown: 20` cycles. |
| Any auto-advance reversal at autonomous tier | Demote to monitored (not all the way to supervised). Set `demotion_cooldown: 10` cycles. |
| 2 auto-advance reversals within 7 days at autonomous tier | Demote to supervised. Reset stats. Set `demotion_cooldown: 30` cycles. |

**Demotion procedure:**
1. Update trust-state.yml: set new tier, reset stats, reset `bootstrap_remaining` to 0, set cooldown, append history
2. Post comment on the triggering issue documenting the demotion
3. Send Telegram notification: "Autonomy demoted from <old> to <new> for project <project>. Reason: <trigger>. Cooldown: N cycles."

**Demotion cooldown:** After demotion, the `demotion_cooldown` counter decrements each scan cycle. During cooldown, the system stays at the demoted tier regardless of stats. This prevents oscillation.

**Promotion is always human-initiated.** The system never self-promotes. The human edits `trust-state.yml` to change the tier and sets `bootstrap_remaining: 3` (for monitored promotion). This is a deliberate asymmetry: demotion is automated (safety), promotion is manual (trust).

### 3.7 Promotion Guidance

While promotion is human-initiated, the system surfaces readiness signals. When the `po_reviewer` hat finds the system at supervised tier with `demotion_cooldown: 0` and `stats.approvals >= 5` and `stats.rejections == 0`, it adds a one-time comment:

```markdown
### 📝 po — <ISO-timestamp>

**Promotion readiness:** This project has 5 consecutive approvals with 0 rejections
at the supervised tier. It may be ready for monitored tier.

To promote, edit `team/projects/<project>/autonomy/trust-state.yml`:
- Set `tier: monitored`
- Set `bootstrap_remaining: 3`
- Commit the change.
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
bootstrap_remaining: int  # (rev 2) bootstrap auto-advances remaining (0 = complete)
reversal_window: string|int  # (rev 2) "next_gate" or integer hours

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
    bootstrap: bool|null  # (rev 2) true if auto-advance used bootstrap exclusion
    cascade: object|null  # (rev 2) for reversal events: {closed: [int], warned: [int]}
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
    "prior_rejections_at_gate": "int",
    "pattern_novelty": "known | variant | first_time",
    "pattern_novelty_excluded": "bool"
  },
  "reasoning": "string"
}
```

Note (rev 2): `prior_rejections` renamed to `prior_rejections_at_gate` to clarify scope (per-gate, per-issue count from comments, not from trust-state.yml flat counter — see 3.2.1).

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

- **Human edits trust-state.yml incorrectly:** If `tier` is set to an invalid value, treat as `supervised`. If `stats` are inconsistent, the hat resets them on the next update. If `bootstrap_remaining` is missing or negative, treat as 0 (bootstrap complete). If `reversal_window` is invalid, default to `next_gate`. Trust-state is a coordination artifact, not a security boundary — the human can always fix it.

- **Telegram notification failure:** Non-blocking. If RObot is unavailable, the auto-advance still proceeds. The GitHub comment is the authoritative record; Telegram is convenience.

- **Reversal cascade failure (rev 2):** If a downstream issue cannot be closed or commented on (e.g., API error), log the error and continue with remaining cascade items. Post a partial cascade summary listing which items succeeded and which failed. The human can manually handle failed cascade items. Cascade failure does NOT prevent the reversal itself — the parent issue status is still reverted.

- **Issue reopen failure (rev 2):** If reopening a closed issue fails during `po:accept` reversal, log the error and post a comment on the issue explaining that manual reopening is needed. Do not silently skip the reversal.

---

## 6. Acceptance Criteria

- **Given** a project at `supervised` tier, **when** the `po_reviewer` hat activates for `po:design-review`, **then** it blocks for human comment exactly as it does today — no behavioral change.

- **Given** a project at `monitored` tier with `bootstrap_remaining: 2` and an issue where all signals except pattern_novelty are LOW and pattern_novelty is "first_time", **when** the `po_reviewer` hat activates, **then** it classifies risk as LOW (pattern_novelty excluded during bootstrap), auto-advances with a notification comment noting the bootstrap exclusion, and decrements `bootstrap_remaining` to 1.

- **Given** a project at `monitored` tier with `bootstrap_remaining: 0` and an issue classified as LOW risk, **when** the `po_reviewer` hat activates for `po:design-review`, **then** it auto-advances the status to `arch:plan`, posts a notification comment with the risk assessment, and updates `trust-state.yml`.

- **Given** a project at `monitored` tier and an issue classified as MEDIUM risk (pattern_novelty is "variant", bootstrap complete), **when** the `po_reviewer` hat activates for `po:plan-review`, **then** it blocks for human comment (same as supervised).

- **Given** a project at `autonomous` tier and an issue classified as HIGH risk, **when** the `po_reviewer` hat activates, **then** it auto-advances but includes a prominent warning in the notification comment and sends a Telegram notification.

- **Given** a human posts `Rejected: <feedback>` on an auto-advanced issue that has not yet reached its next human gate, **when** the `po_reviewer` scans on the next cycle, **then** it runs the reversal cascade (closing pre-implementation downstream issues, warning active development), reverts the status to the rejection target, increments `auto_advance_reversals`, and evaluates demotion.

- **Given** a reversal on an auto-advanced `po:accept` (issue was closed), **when** the reversal is processed, **then** the issue is **reopened first**, then its status is reverted to `arch:in-progress`, and a cascade summary is posted.

- **Given** a reversal that affects 3 downstream stories (one at `qe:test-design`, one at `dev:implement` not started, one at `dev:implement` with work in progress), **when** the cascade runs, **then** the first two are closed as "not planned" and the third receives a warning comment requiring human decision.

- **Given** any auto-advance reversal at `monitored` tier, **when** the reversal is processed, **then** the tier is demoted to `supervised`, stats are reset, `demotion_cooldown` is set to 20, and a demotion comment is posted.

- **Given** a project at `supervised` tier with 5 approvals and 0 rejections and `demotion_cooldown == 0`, **when** the `po_reviewer` completes a gate check, **then** a one-time readiness notification comment is posted suggesting promotion to `monitored`.

- **Given** the risk classifier script fails, **when** `po_reviewer` catches the error, **then** it falls back to supervised behavior and logs a warning — no auto-advance occurs.

- **Given** `trust-state.yml` does not exist, **when** the `po_reviewer` hat first activates, **then** it creates the file with `tier: supervised` and proceeds with supervised behavior.

- **Given** `reversal_window: next_gate` and an auto-advanced issue at `po:design-review` that has now reached `po:plan-review`, **when** a `Rejected:` comment is found on the original design gate, **then** the reversal is NOT processed (the issue has passed its reversal window; the human can reject at the current `po:plan-review` gate instead).

---

## 7. Impact on Existing System

| Component | Change |
|-----------|--------|
| `po_reviewer` hat instructions (ralph.yml) | Gate policy decision block before human comment check. Auto-advance procedure with bootstrap logic. Post-advance reversal scan with cascade mechanism. Demotion logic. Promotion readiness notification. |
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

**Reversal cascade bounds blast radius but does not eliminate it (rev 2).** Auto-advancing trades review latency for potential reversal cost. A reversed design auto-advance can cascade to multiple downstream stories. The design is explicit about this trade-off:
- Pre-implementation work (test design, infra setup) is auto-closed — low-cost recovery.
- Active development receives warnings but is NOT auto-closed — the human decides whether the work is salvageable.
- Completed work receives informational warnings only.
The cascading cost is bounded by the demotion mechanism: even a single reversal at monitored tier demotes to supervised, preventing repeated cascade scenarios. The system must re-earn trust through 5+ supervised approvals before regaining auto-advance capability.

**Bootstrap window is time-limited and self-resolving.** The bootstrap window (3 auto-advances with pattern_novelty excluded) is a necessary concession to make the monitored tier functional. It is bounded (exactly 3 gates), logged (every bootstrap auto-advance is flagged in the notification), and self-resolving (after 3 successes, the full risk model applies). A reversal during bootstrap immediately triggers demotion — the system does not get a second bootstrap window without human re-promotion.

**Prompt injection risk:** The risk classifier reads issue bodies and design docs to extract signals. These are the same inputs the `po_reviewer` already reads. No new prompt injection surface. The classifier parses structured signals (file counts, dependency lists), not natural language instructions.

---

## Appendix: Revision 2 Changes

This revision addresses 5 findings from the lead design review:

| # | Finding | Severity | Fix |
|---|---------|----------|-----|
| 1 | Bootstrapping deadlock: pattern novelty prevents first monitored auto-advance | Critical | Added bootstrap window (Section 3.2.2): first 3 auto-advances exclude pattern_novelty from composite rule. Self-resolving. |
| 2 | Downstream work invalidation undefined on reversal | Critical | Added reversal cascade (Section 3.5.3): downstream issues closed or warned based on status. Blast radius claim rewritten honestly. |
| 3 | 48-hour reversal window unjustified | Significant | Replaced with configurable `reversal_window` (Section 3.5.1): default `next_gate` (until issue reaches next human gate). Time-based option available as override. |
| 4 | Prior rejections scope ambiguous | Significant | Defined explicitly (Section 3.2.1): per-gate, per-issue count from comments. Reversals tracked separately. Renamed field to `prior_rejections_at_gate`. |
| 5 | po:accept reversal needs issue reopening | Significant | Added explicit reopen step in reversal procedure (Section 3.5.2 step b). Error handling for reopen failure added (Section 5). |
