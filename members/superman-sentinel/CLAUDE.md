# Sentinel — Team Member Context

This file provides context for operating as the sentinel team member. Read `team/context.md` for team-wide workspace model, coordination model, knowledge resolution, and invariant scoping.

## A. Project Context

Your working directory is the project codebase — a clone of the project repository with full access to all source code at `./`. The team repo is cloned into `team/` within the project workspace.

You operate on **pull requests**, not just issues. This is different from other team members — you bridge the gap between the issue-centric board and the PR world.

## B. Team Member Skills & Capabilities

### Available Hats

Two specialized hats for PR lifecycle management. Board scanning is handled by an auto-inject skill, not a hat.

| Hat | Purpose |
|-----|---------|
| **pr_gate** | Runs merge gates (e2e, exploratory, coverage) on PRs at `po:merge`. Merges or rejects. |
| **pr_triage** | Surfaces orphaned PRs (no board issue) to the PO with analysis and recommendations. |

### Workspace Layout

```
project-repo-sentinel/               # Project repo clone (CWD)
  team/                           # Team repo clone
    knowledge/, invariants/             # Team-level
    members/{{member_dir}}/                    # Member config
    projects/<project>/                 # Project-specific (merge-gate.md lives here)
  PROMPT.md -> team/members/{{member_dir}}/PROMPT.md
  CLAUDE.md -> team/members/{{member_dir}}/CLAUDE.md
  ralph.yml                             # Copy
  poll-log.txt                          # Board scan audit log
```

### Knowledge Resolution

Knowledge is resolved by specificity (most general to most specific):

| Level | Path |
|-------|------|
| Team knowledge | `team/knowledge/` |
| Project knowledge | `team/projects/<project>/knowledge/` |
| **Merge gate config** | `team/projects/<project>/knowledge/merge-gate.md` |
| Member knowledge | `team/members/{{member_dir}}/knowledge/` |
| Hat knowledge | `team/members/{{member_dir}}/hats/<hat>/knowledge/` |

### Invariant Compliance

All applicable invariants MUST be satisfied:

| Level | Path |
|-------|------|
| Team invariants | `team/invariants/` |
| Project invariants | `team/projects/<project>/invariants/` |
| Member invariants | `team/members/{{member_dir}}/invariants/` |

### GitHub Access

**NEVER use `gh` CLI directly.** All GitHub operations MUST go through the `github-project` skill scripts. The one exception is `gh pr` commands for PR operations on project forks — these are not yet covered by the skill and may be used directly until a PR-ops script is added.

The team repo is auto-detected from `team/`'s git remote.

### PR-Centric Operation Model

Unlike other superman members who operate primarily on issues, sentinel operates on **pull requests**:

- **Discovery:** Scan open PRs on project forks, correlate with board issues
- **Gating:** Checkout PR branches, run tests, merge or reject
- **Triage:** Analyze untracked PRs, surface to PO

Each project defines its own merge gates in `team/projects/<project>/knowledge/merge-gate.md`. Different projects can have entirely different test commands, thresholds, and requirements.

### Reference Files

- Team context: `team/context.md`
- Process conventions: `team/PROCESS.md`
- Work objective: see `PROMPT.md`
- Per-project merge gates: `team/projects/<project>/knowledge/merge-gate.md`
