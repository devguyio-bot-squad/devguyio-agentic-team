# Merge Gate Configuration — botminter

## E2E Tests

- **Command:** `just test`
- **Required:** Yes
- **Working directory:** Project root (`.`)
- **Timeout:** 600 seconds (10 minutes)
- **Notes:** Includes unit tests, conformance tests, and e2e tests. Requires `TESTS_GH_TOKEN`, `TESTS_GH_ORG`, and `TESTS_APP_*` env vars.

## Exploratory Tests

- **Command:** `just exploratory-test`
- **Required:** Yes (when changes touch bridge, workspace, sync, or exploratory test infrastructure)
- **Condition:** Run if any changed files match: `crates/bm/src/bridge/`, `crates/bm/src/workspace/`, `crates/bm/src/commands/init.rs`, `crates/bm/tests/exploratory/`
- **Working directory:** Project root (`.`)
- **Timeout:** 600 seconds (10 minutes)
- **Notes:** Runs on `bm-test-user@localhost` via SSH. Requires SSH access, podman, `gh` auth on test user.

## Coverage

- **Command:** None (coverage verified by test pass/fail, no separate tool yet)
- **Threshold:** N/A (placeholder — to be defined)

## Gate Sequence

1. E2E tests (always run)
2. Exploratory tests (conditional — check changed paths against the condition above)
3. Coverage check (skip — no threshold defined yet)

## Rejection Behavior

On any gate failure, return the story to `dev:implement` with detailed failure output including the last 50 lines of test output. The developer will fix and the story re-traverses the pipeline.
