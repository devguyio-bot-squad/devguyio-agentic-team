# Umbrella: Transition BotMinter to Fully Agentic SDLC

**Epic:** #106
**Author:** bob (superman)
**Date:** 2026-04-04
**Status:** Umbrella — design decomposed into sub-epics

---

## Overview

BotMinter's scrum-compact profile provides a complete agentic SDLC: 18 specialized hats, board-driven dispatch, a four-level knowledge hierarchy, and rejection loops at every review gate. The machinery runs on trust — invariants are prose, enforcement is judgment-based, and quality is unmeasured.

OpenAI's Harness Engineering team demonstrated that agents produce correct output when the environment mechanically prevents incorrect output. Their team shipped ~1M lines of production code in 5 months with zero manually-written code. The core lesson: stop writing code, start building environments where agent work is correct by construction.

This umbrella epic closes six capability gaps between BotMinter's current process structure and mechanical enforcement. Each gap is a separate sub-epic with its own design document.

## Sub-Epics

| # | Epic | Gap | Design Doc |
|---|------|-----|------------|
| #108 | Executable Invariant Checks | Mechanical Enforcement | `epic-108.md` |
| #109 | Application Legibility for Agent Development | Application Legibility | `epic-109.md` |
| #110 | Automated Codebase Gardening | Entropy Management | `epic-110.md` |
| #111 | Plans as First-Class Artifacts | Plan Fragmentation | `epic-111.md` |
| #112 | Graduated Autonomy for Human Gates | Fixed Human Gates | `epic-112.md` |
| #113 | Metrics and Feedback Loops | No Quality Data | `epic-113.md` |

## Implementation Order and Dependencies

```
Phase 1 (parallel):  #108 Checks ─────────┐
                     #111 Plans            │
                     #113 Metrics ────────┐│
                                          ││
Phase 2:             #110 Gardening ◄─────┘│  (needs check runner from #108)
                                           │
Phase 3:             #112 Autonomy ◄───────┘  (needs #108 enforcement + #113 quality data)

Phase 4:             #109 Legibility           (most complex, least coupled)
```

Enforcement first (#108). Autonomy only after enforcement + metrics prove reliability (#112 depends on #108 + #113). Legibility last because it's the most complex and least coupled to the others.

## Harness Engineering Alignment

| Harness Technique | BotMinter Has | Gap Closed By |
|---|---|---|
| Custom linters with agent-readable output | 11 prose invariants, 11 ADRs | #108 |
| Per-worktree app boot + observability | Formation abstraction, daemon + web console | #109 |
| Golden principles + doc-gardening | Nothing | #110 |
| Plans as first-class versioned artifacts | Design docs only, breakdowns in comments | #111 |
| Graduated human involvement | 3 fixed gates | #112 |
| Quality grading + metrics | poll-log.txt only | #113 |

## Product Framing

All changes are BotMinter product capabilities that the BotMinter project dogfoods:

- **Check scripts** are a profile feature — any scrum-compact project can use them
- **Application legibility** is a project-level concern — each project configures its own dev-boot
- **Gardening** is a profile feature — the hat and scheduling ship with the profile
- **Plans** are a profile convention — the directory structure and hat behavior ship with the profile
- **Autonomy** is a manifest-level feature — operators configure it per team
- **Metrics** are a profile feature — transition logging is part of the board scanner skill

This is pre-alpha software. No backward compatibility shims or feature flags.
