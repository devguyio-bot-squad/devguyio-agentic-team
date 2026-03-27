# GSD (Get Shit Done) — Research Document

Research into [GSD](https://github.com/gsd-build/get-shit-done)'s interaction model, contract system, and architecture. This research informs the design of BotMinter's formation contracts (ADR-0012).

**Version researched:** 1.30.0 (2026-03-26)
**Research date:** 2026-03-27

---

## 1. What GSD Is

GSD is a spec-driven development system that sits between the user and AI coding agents. It provides structured context — "the right information at the right time" — so each agent session gets fresh, scoped instructions. It works with 8 runtimes (Claude Code, Cursor, Windsurf, Copilot, Gemini CLI, Codex, OpenCode, Antigravity) and has a headless SDK.

The core insight: **plans are prompts, not documents that become prompts.** A PLAN.md file is simultaneously a specification and the literal prompt injected into an agent's context window.

---

## 2. Architecture: Five Layers

```
USER
  |
COMMAND LAYER         (44 slash commands)
  |
WORKFLOW LAYER        (46 thin orchestrator .md files)
  |
AGENT LAYER           (18 specialized agents)
  |
CLI TOOLS LAYER       (gsd-tools.cjs — deterministic state management)
  |
FILE SYSTEM           (.planning/ — all state as markdown + JSON)
```

### Key Design Principles

1. **Fresh context per agent** — every spawned agent gets a clean context window. No accumulated drift.
2. **Thin orchestrators** — workflows coordinate but never do heavy lifting. Deterministic bookkeeping only.
3. **File-based state** — all state lives in `.planning/` as human-readable Markdown and JSON. No databases.
4. **Plans are prompts** — PLAN.md files are the literal prompts executors receive.
5. **Goal-backward verification** — verify what must be TRUE for goals to be achieved, not what tasks were completed.

---

## 3. The Contract System

### 3.1 PLAN.md — The Fundamental Unit

Every unit of work is a PLAN.md file with YAML frontmatter (the contract metadata) and an XML body (the task definitions). Structure:

```
┌─────────────────────────────┐
│  --- YAML frontmatter ---   │  ← Contract metadata
│  phase, plan, type, wave,   │
│  depends_on, files_modified,│
│  autonomous, must_haves     │
│  ---                        │
├─────────────────────────────┤
│  <objective>...</objective> │  ← What this plan achieves
├─────────────────────────────┤
│  <execution_context>        │  ← File references for agent
│  @path/to/file              │
│  </execution_context>       │
├─────────────────────────────┤
│  <tasks>                    │  ← Task definitions
│    <task type="auto">       │
│      <name>...</name>       │
│      <files>...</files>     │
│      <action>...</action>   │
│      <verify>...</verify>   │
│      <done>...</done>       │
│    </task>                  │
│  </tasks>                   │
└─────────────────────────────┘
```

Required frontmatter fields:
- `phase` (string) — which phase this belongs to
- `plan` (string) — plan ID
- `type` — `execute` or other plan types
- `wave` (integer) — dependency group for parallel execution
- `depends_on` (string[]) — plan IDs this plan requires completed first
- `files_modified` (string[]) — file paths touched by this plan
- `autonomous` (boolean) — whether the plan can run without human gates
- `must_haves` (object) — the verification contract

### 3.2 Task Anatomy

Each `<task>` has four required fields:

| Field | Purpose |
|-------|---------|
| `<files>` | Comma-separated list of files this task touches |
| `<action>` | What the agent should do (natural language) |
| `<verify>` | Executable command to prove the task succeeded |
| `<done>` | Human-readable completion criterion |

Optional fields: `<name>`, `<read_first>`, `<acceptance_criteria>`.

Task types via the `type` attribute:
- `auto` — fully autonomous execution
- `checkpoint:human-verify` — requires human confirmation
- `checkpoint:decision` — requires human choice
- `checkpoint:human-action` — requires human to perform an action
- `tdd` — test-driven development cycle (RED/GREEN/REFACTOR)

### 3.3 The `must_haves` Contract

This is the heart of the contract system — three layers of goal-backward verification:

```yaml
must_haves:
  truths:
    - "User can see existing messages"
    - "User can send a message"
    - "Messages persist across refresh"
  artifacts:
    - path: "src/components/Chat.tsx"
      provides: "Message list rendering"
      min_lines: 30
    - path: "src/app/api/chat/route.ts"
      provides: "Message CRUD operations"
      exports: ["GET", "POST"]
  key_links:
    - from: "src/components/Chat.tsx"
      to: "/api/chat"
      via: "fetch in useEffect"
      pattern: "fetch.*api/chat"
```

**Truths** (`string[]`): Observable behaviors that must be TRUE. User-facing statements about what the system does. These are the top-level success criteria.

**Artifacts** (`object[]`): Concrete files that must EXIST and be substantive. Each has:
- `path` (required) — file path
- `provides` (required) — what this artifact contributes
- `min_lines` (optional) — minimum line count to prove substance
- `exports` (optional) — named exports that must exist
- `contains` (optional) — pattern that must appear

**Key Links** (`object[]`): Critical connections between artifacts. Catches the failure mode where files exist but aren't connected:
- `from` — source file
- `to` — target file or endpoint
- `via` — mechanism of connection
- `pattern` (optional) — regex to grep for

### 3.4 The `<verify>` Block

Each task's `<verify>` contains an executable shell command:

```xml
<verify>test -f output.txt</verify>
<verify>curl -X POST localhost:3000/api/auth/login returns 200 + Set-Cookie</verify>
<verify>grep -q "export function createUser" src/lib/users.ts</verify>
```

Enforcement:
- **During execution**: executor runs verify after completing a task. Up to 3 auto-fix attempts on failure. Atomic git commit only after verify passes.
- **Pre-execution**: plan-checker enforces Nyquist compliance — every `<verify>` must be automated, no manual-only verification allowed.
- **Post-execution**: verifier cross-references verify results against must_haves.

---

## 4. Goal-Backward Verification

This is the philosophical core of GSD. Instead of "did we complete tasks?", it asks "did we achieve the goal?"

> Task completion =/= Goal achievement. A task "create chat component" can be marked complete when the component is a placeholder. The task was done — but the goal "working chat interface" was not achieved.

### The Five-Step Derivation

1. **State the Goal** — what outcome must the phase deliver?
2. **Derive Observable Truths** — what must be TRUE for the goal to be achieved?
3. **Derive Required Artifacts** — what files must EXIST for those truths to hold?
4. **Derive Required Wiring** — what connections must exist for those artifacts to function?
5. **Identify Key Links** — which specific connections are most likely to be missing?

### Four-Level Artifact Verification

| Level | Check | Failure Status |
|-------|-------|---------------|
| 1. Exists | File is present on disk | MISSING |
| 2. Substantive | Not a stub (meets min_lines, exports, contains) | STUB |
| 3. Wired | Imported AND used by other code | ORPHANED |
| 4. Data Flowing | Real data passes through the wiring | DEAD |

### Verification Flow

```
Planning Phase:
  Planner creates PLAN.md → Plan-checker validates 10 dimensions → Loop until pass

Execution Phase:
  Per task: Read <action> → Execute → Run <verify> → Pass? Commit. Fail? Auto-fix or stop.

Verification Phase:
  Load must_haves from all plans →
  Verify truths (observable behaviors) →
  Verify artifacts (4 levels) →
  Verify key links (grep for patterns) →
  Scan anti-patterns (TODO/FIXME/HACK, placeholders) →
  Status: passed / gaps_found / human_needed

Gap Closure (if gaps_found):
  Cluster gaps → Generate fix plans → Execute → Re-verify
```

### Nyquist Rule

Named after the Nyquist-Shannon sampling theorem: just as signal reconstruction requires 2x sampling, GSD requires sufficient automated verification to reconstruct confidence. Every `<verify>` must include an automated command. Manual-only verification is not allowed.

---

## 5. The Interaction Model

### 5.1 CLI vs Agent Boundary

The boundary between deterministic logic and AI reasoning is clean and explicit:

**Deterministic (gsd-tools.cjs):**
- State file reads/writes (STATE.md, ROADMAP.md, config.json)
- Phase directory discovery and numbering
- Model resolution from profiles
- Git operations
- Slug generation, timestamps
- 30+ subcommands, all purely deterministic

**AI Reasoning (Agent Layer):**
- Understanding requirements and context
- Making design decisions
- Writing code
- Decomposing work into plans
- Verifying correctness against goals
- Research and synthesis

**The handoff pattern:** Workflow loads context deterministically → hands structured prompt to AI agent → deterministically processes agent's file-system output. The agent writes files and makes commits; the orchestrator reads those results.

### 5.2 The Orchestrator-Agent Pattern

Workflows are "thin orchestrators." Their job:

1. **Load context** via `gsd-tools.cjs init <workflow> <phase>` (deterministic JSON payload)
2. **Resolve model** via `gsd-tools.cjs resolve-model <agent-name>`
3. **Spawn an agent** via `Task()` with fully-constructed prompt + tool permissions
4. **Collect result** from agent
5. **Update state** via `gsd-tools.cjs state update/patch/advance-plan`

### 5.3 Agent Types (18 Agents)

| Category | Agents | Role |
|----------|--------|------|
| Researchers | project-researcher, phase-researcher, ui-researcher, advisor-researcher | Read-only discovery |
| Synthesizers | research-synthesizer | Combine research outputs |
| Planners | planner, roadmapper | Decompose into PLAN.md files |
| Checkers | plan-checker, integration-checker, ui-checker | Read-only validation |
| Executors | executor | Write code, make commits |
| Verifiers | verifier, nyquist-auditor | Goal-backward verification |
| Debuggers | debugger | Diagnose and fix failures |
| Mappers | codebase-mapper | Map codebase structure |

### 5.4 Wave-Based Parallel Execution

Plans are grouped into dependency waves. Within a wave, plans run in parallel (each in its own agent with isolated worktree). Waves run sequentially:

```
Wave 1: [Plan A, Plan B]     ← parallel, no dependencies
Wave 2: [Plan C]              ← depends on A or B
Wave 3: [Plan D, Plan E]     ← depend on C
```

### 5.5 Tool Scoping (Principle of Least Privilege)

Each phase type gets only the tools it needs:

| Phase | Tools |
|-------|-------|
| Research | Read, Grep, Glob, Bash, WebSearch |
| Plan | Read, Write, Bash, Glob, Grep, WebFetch |
| Execute | Read, Write, Edit, Bash, Grep, Glob |
| Verify | Read, Bash, Grep, Glob |
| Discuss | Read, Bash, Grep, Glob |

Researchers get web access but can't write source. Verifiers are read-only. Executors can write but have no web access.

### 5.6 Execution Modes

| Mode | Scope | Agent Involvement |
|------|-------|-------------------|
| `gsd:fast` | Trivial (<=3 file edits) | None — direct edit + commit |
| `gsd:quick` | Small (1-3 tasks) | Single plan, optional discuss/research/verify |
| Full workflow | Normal phases | Multiple plans, wave parallelism, full verification |
| `gsd:do` | Multi-phase autonomous | Chains discuss/plan/execute across all remaining phases |

### 5.7 Human Gates

- `checkpoint:human-verify` — human confirms output
- `checkpoint:decision` — human chooses between options
- `checkpoint:human-action` — human performs a step
- In auto-mode, checkpoints are auto-approved (human-verify) or auto-select first option (decision)

---

## 6. The SDK

The TypeScript SDK (`@gsd-build/sdk`, v0.1.0) wraps the file-based system into a programmatic API for headless execution via `@anthropic-ai/claude-agent-sdk`.

### API Surface

```typescript
import { GSD } from '@gsd-build/sdk';

const gsd = new GSD({ projectDir: '/path/to/project' });

// Single plan execution
await gsd.executePlan('.planning/phases/01-auth/01-PLAN.md');

// Full phase lifecycle (discuss -> research -> plan -> execute -> verify)
await gsd.runPhase('01');

// Full milestone (all phases)
await gsd.run('Build the auth system');

// Event subscription
gsd.onEvent((event) => console.log(event.type));
```

### Key Components

| Module | Purpose |
|--------|---------|
| `session-runner.ts` | Wraps Agent SDK `query()` with prompt/tool/budget config |
| `phase-runner.ts` | State machine: discuss -> research -> plan -> execute -> verify -> advance |
| `plan-parser.ts` | Stack-based YAML parser + XML task extractor |
| `tool-scoping.ts` | Phase-to-tools mapping |
| `prompt-sanitizer.ts` | Strips interactive patterns for headless use |
| `event-stream.ts` | 27 typed event types with transport management |

### Headless Operation

Sessions run with `permissionMode: 'bypassPermissions'`. The prompt sanitizer strips interactive patterns (`@file:`, `/gsd:`, `AskUserQuestion`, `STOP`) so agent prompts work without user interaction.

---

## 7. The Hook System

Five advisory hooks that warn but never block:

| Hook | Trigger | Purpose |
|------|---------|---------|
| Context Monitor | PostToolUse | Warns when context window filling up |
| Statusline | StatusLine | Displays model/task/context bar |
| Workflow Guard | PreToolUse | Warns about edits outside GSD workflow |
| Prompt Guard | PreToolUse | Detects prompt injection in `.planning/` writes |
| Update Checker | SessionStart | Checks for new GSD versions |

Notable pattern — **two-part bridge** for context monitoring: statusline hook writes metrics to a bridge file; context monitor reads it. Thresholds at 35% (WARNING) and 25% (CRITICAL) remaining context.

---

## 8. State Management

### File Layout

```
.planning/
  PROJECT.md            # Project definition (constant after init)
  ROADMAP.md            # Phase list with completion status
  REQUIREMENTS.md       # Formal requirements (REQ-XX-NN format)
  STATE.md              # Living memory — current position, decisions
  config.json           # Project configuration
  research/             # Research outputs
  phases/
    NN-slug/
      NN-slug-WW-PLAN.md
      NN-slug-WW-SUMMARY.md
      NN-slug-VERIFICATION.md
```

### Workstreams (Parallel Isolation)

Multiple independent workstreams can run simultaneously. Each gets its own STATE.md, ROADMAP.md, and phases/ under `.planning/workstreams/{name}/`. Shared files (PROJECT.md, config.json) stay at root.

### Parallel Commit Safety

STATE.md uses file-level locking with `O_EXCL` atomic creation. Lock files have 10-second stale timeout with spin-wait and jitter.

---

## 9. Relevance to BotMinter (ADR-0012)

GSD's contract model directly inspired BotMinter's formation contract design. Key patterns borrowed:

| GSD Pattern | BotMinter Adaptation |
|-------------|---------------------|
| YAML frontmatter as machine-readable contracts | `contract.yml` for formations |
| `<verify>` blocks per task | `verify.command` per dependency |
| `must_haves.truths` | `truths[]` section in formation contract |
| Goal-backward verification | `verification.command` (`bm env check`) |
| Deterministic CLI + AI reasoning boundary | `bm env check` (deterministic) + Minty skill (AI-driven) |
| Plans are prompts | Formation contract is consumed directly by Minty |
| Four-level artifact verification | Applicable to dependency checking (exists -> functional) |

### Key Differences

| Aspect | GSD | BotMinter Formation |
|--------|-----|---------------------|
| Scope | Software development lifecycle | Environment provisioning |
| Agent count | 18 specialized agents | 1 AI assistant (Minty) |
| Execution model | Wave-based parallel | Sequential dependency resolution |
| State persistence | `.planning/` directory | Formation config + keyring |
| Verification | Goal-backward with Nyquist | Deterministic `bm env check` |

### What to Adopt

1. **The contract-as-prompt pattern** — formation `contract.yml` should be directly consumable by the provisioning agent
2. **Deterministic verification** — `bm env check` as a fast, no-AI check (like GSD's `gsd-tools.cjs verify`)
3. **Truths as success criteria** — formation truths define "environment is ready" observably
4. **The verify-per-dependency pattern** — each dependency in `contract.yml` gets its own verification command
5. **Goal-backward thinking** — verify "can member operate?" not "were install steps run?"

### What to Skip

1. **Wave-based parallel execution** — overkill for sequential environment setup
2. **18 agent types** — single Minty skill is sufficient for provisioning
3. **PLAN.md format** — too complex; `contract.yml` is simpler and sufficient
4. **Nyquist validation** — relevant for code quality, not environment provisioning
