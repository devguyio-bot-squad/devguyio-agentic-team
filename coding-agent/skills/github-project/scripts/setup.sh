#!/bin/bash
# Common setup for all github-project skill operations
# Source this file at the start of each script

set -euo pipefail

# Derive workspace root from script location
# Scripts live at <workspace>/.claude/skills/github-project/scripts/
_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$_SETUP_DIR/../../../.." && pwd)"

# Verify project scope by testing access
if ! gh project list --owner "$(gh api user -q .login)" --limit 1 --format json &>/dev/null; then
  echo "❌ ERROR: Missing 'project' scope on GH_TOKEN"
  echo "Run: gh auth refresh -s project -h github.com"
  exit 1
fi

# Detect team repo
TEAM_REPO=$(cd "$WORKSPACE_ROOT/team" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)

# Fallback: extract owner/repo from git remote URL
if [ -z "$TEAM_REPO" ]; then
  TEAM_REPO=$(cd "$WORKSPACE_ROOT/team" && git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')
fi

if [ -z "$TEAM_REPO" ]; then
  echo "❌ ERROR: Could not detect team repository"
  exit 1
fi

# Resolve project IDs (cache for session)
OWNER=$(echo "$TEAM_REPO" | cut -d/ -f1)

# Minimal mode: only detect team repo and owner (for scripts that don't need project IDs)
if [ "${SETUP_MODE:-}" = "minimal" ]; then
  export TEAM_REPO OWNER
  return 0 2>/dev/null || exit 0
fi

# Get project number from ~/.botminter/config.yml (set by bm init).
# Matches the team entry whose github_repo equals TEAM_REPO.
BM_CONFIG="$HOME/.botminter/config.yml"
PROJECT_NUM=""
if [ -f "$BM_CONFIG" ]; then
  # Simple YAML extraction: find the team block matching github_repo, then read project_number.
  # Uses awk to avoid python/PyYAML dependency.
  PROJECT_NUM=$(awk -v repo="$TEAM_REPO" '
    /^- name:/ || /^  - name:/ { in_team=1; found_repo=0; pn="" }
    in_team && /github_repo:/ && $0 ~ repo { found_repo=1 }
    in_team && /project_number:/ { pn=$2 }
    in_team && found_repo && pn { print pn; exit }
  ' "$BM_CONFIG" 2>/dev/null)
fi

if [ -z "$PROJECT_NUM" ]; then
  echo "❌ ERROR: No project_number found in $BM_CONFIG for team repo: $TEAM_REPO"
  echo "Ensure 'bm init' was run and project_number is set in config.yml"
  exit 1
fi

# Get project ID with error checking
PROJECT_ID=$(gh project view "$PROJECT_NUM" --owner "$OWNER" --format json 2>&1 | jq -r '.id')
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
  echo "❌ ERROR: Could not get project ID for project #$PROJECT_NUM"
  exit 1
fi

# Get field data with error checking
if ! FIELD_DATA=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json 2>&1); then
  echo "❌ ERROR: Could not fetch project field list"
  echo "$FIELD_DATA"
  exit 1
fi

if [ -z "$FIELD_DATA" ]; then
  echo "❌ ERROR: Empty response from project field list"
  exit 1
fi

# Extract Status field ID with validation
STATUS_FIELD_ID=$(echo "$FIELD_DATA" | jq -r '.fields[] | select(.name=="Status") | .id')
if [ -z "$STATUS_FIELD_ID" ] || [ "$STATUS_FIELD_ID" = "null" ]; then
  echo "❌ ERROR: No 'Status' field found in project #$PROJECT_NUM"
  echo "Available fields:"
  echo "$FIELD_DATA" | jq -r '.fields[] | .name'
  exit 1
fi

# Get member identity from .botminter.yml (optional)
if [ -f "$WORKSPACE_ROOT/.botminter.yml" ]; then
  ROLE=$(grep '^role:' "$WORKSPACE_ROOT/.botminter.yml" | awk '{print $2}')
  EMOJI=$(grep '^comment_emoji:' "$WORKSPACE_ROOT/.botminter.yml" | sed 's/comment_emoji: *"//' | sed 's/"$//')
else
  ROLE="superman"
  EMOJI="🦸"
fi

echo "✓ Setup complete: $TEAM_REPO, project #$PROJECT_NUM"

# Export variables for use in calling scripts
export TEAM_REPO OWNER PROJECT_NUM PROJECT_ID FIELD_DATA STATUS_FIELD_ID ROLE EMOJI WORKSPACE_ROOT
