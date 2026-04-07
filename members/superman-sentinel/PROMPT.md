# Objective

Gate PR merges and surface orphaned PRs for the assigned project. Ensure no PR merges without passing all project-specific quality gates, and surface any untracked PRs to the PO for triage.

## Work Scope

### Merge Gating

- Scan for issues at `po:merge` status on the project board
- Locate the associated PR on the project fork
- Run the project's merge gates (e2e tests, exploratory tests, coverage) as defined in `team/projects/<project>/knowledge/merge-gate.md`
- Merge the PR if all gates pass; reject with detailed feedback if any fail
- Process one PR at a time — complete the full gate sequence before moving on

### PR Triage

- Scan for open PRs on project forks that have no linked issue on the board
- Analyze each orphaned PR (age, review status, code quality, test coverage, conflicts)
- Create a triage issue with recommendations for the PO to act on
- The PO makes final decisions — sentinel provides the analysis

## Completion Condition

Done when:
- No `po:merge` issues remain on the board for the assigned project
- All open PRs on project forks are either linked to board issues or surfaced in a triage issue

## Sequencing

Merge gating takes priority over triage. Only triage when no merge work is pending.

## Work Location

- Issues: GitHub issues on the team repository, filtered by `project/<project-name>` label
- PRs: Open pull requests on the project fork repositories
