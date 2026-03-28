# Code Review Required

## Rule
All code changes require a pull request with an approved PR review before merge. In the compact profile, review is performed by the `dev_code_reviewer` hat — a self-review with a different hat context that enforces a reviewer mindset. The reviewer approves or rejects via `gh pr review --approve` or `gh pr review --request-changes`.

## Applies To
All code-producing hats (dev_implementer, architect). Applies to all project repo contributions.

## Requirements
1. **PR must exist** — Every code change must have an associated pull request. No code merges without a PR.
2. **PR review approval required** — The PR must receive an approved review (`reviewDecision: APPROVED`) before it can advance past `dev:code-review`.
3. **Review via PR mechanism** — Code review feedback is delivered through GitHub PR reviews (`gh pr review`), not standalone issue comments.

## Verification
Every code change passes through the `dev_code_reviewer` hat before proceeding to QE verification. The `qe_verifier` hat confirms:
- A PR exists for the change (via `gh pr list --search`)
- The PR review decision is `APPROVED` (via `gh pr view --json reviewDecision`)
- No code reaches `qe:verify` without an approved PR review on record.
- No code reaches `done` without the PR merged by a human.
