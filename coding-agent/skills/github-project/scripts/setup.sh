#!/bin/bash
# Common setup for all github-project skill operations
# Source this file at the start of each script

set -euo pipefail

# ── Cache helpers ─────────────────────────────────────────────────────────────
# File-based cache with TTL. Degrades gracefully — on any failure, falls back
# to a fresh API call.

_gh_cache_dir() {
  local repo_slug
  repo_slug=$(echo "$1" | tr '/' '-')
  local dir="/tmp/gh-project-cache-${repo_slug}"
  mkdir -p "$dir" 2>/dev/null
  echo "$dir"
}

# Returns 0 if the cache file exists and is younger than $ttl_seconds.
_cache_fresh() {
  local file="$1" ttl_seconds="$2"
  [ -f "$file" ] || return 1
  local age=$(( $(date +%s) - $(stat -c %Y "$file" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$ttl_seconds" ]
}

# Read a cached value. Returns 1 if missing or stale.
_cache_get() {
  local file="$1" ttl_seconds="$2"
  if _cache_fresh "$file" "$ttl_seconds"; then
    cat "$file"
    return 0
  fi
  return 1
}

# Write a value to cache.
_cache_set() {
  local file="$1" value="$2"
  echo "$value" > "$file" 2>/dev/null || true
}

# ── TTL constants (seconds) ──────────────────────────────────────────────────
TTL_SCOPE=3600      # 1 hour  — token scope doesn't change mid-session
TTL_PROJECT=14400   # 4 hours — project ID, field schema
TTL_IMMUTABLE=86400 # 24 hours — repo ID, issue type IDs

# ── Detect team repo ─────────────────────────────────────────────────────────
# Uses git remote directly — no API call needed.

TEAM_REPO=$(cd team && git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')

if [ -z "$TEAM_REPO" ]; then
  echo "❌ ERROR: Could not detect team repository from git remote"
  exit 1
fi

OWNER=$(echo "$TEAM_REPO" | cut -d/ -f1)
CACHE_DIR=$(_gh_cache_dir "$TEAM_REPO")

# ── Scope check (cached) ─────────────────────────────────────────────────────
# Uses REST API (separate rate limit from GraphQL) to check token scopes.

if ! _cache_fresh "$CACHE_DIR/scope_ok" "$TTL_SCOPE"; then
  TOKEN_SCOPES=$(gh api -i user 2>/dev/null | grep -i "x-oauth-scopes:" || true)
  if [ -n "$TOKEN_SCOPES" ] && ! echo "$TOKEN_SCOPES" | grep -qi "project"; then
    echo "❌ ERROR: Missing 'project' scope on GH_TOKEN"
    echo "Run: gh auth refresh -s project -h github.com"
    exit 1
  fi
  _cache_set "$CACHE_DIR/scope_ok" "1"
fi

# ── Member identity (needed by minimal mode too, for attributed comments) ─────

if [ -f .botminter.yml ]; then
  ROLE=$(grep '^role:' .botminter.yml | awk '{print $2}')
  EMOJI=$(grep '^comment_emoji:' .botminter.yml | sed 's/comment_emoji: *"//' | sed 's/"$//')
else
  ROLE="superman"
  EMOJI="🦸"
fi

# Minimal mode: only detect team repo, owner, and identity
# (for scripts that don't need project IDs or field data)
if [ "${SETUP_MODE:-}" = "minimal" ]; then
  export TEAM_REPO OWNER ROLE EMOJI CACHE_DIR TTL_IMMUTABLE
  # Export cache helpers so scripts can use them
  export -f _gh_cache_dir _cache_fresh _cache_get _cache_set
  return 0 2>/dev/null || exit 0
fi

# ── Project number (from config) ─────────────────────────────────────────────

BM_CONFIG="$HOME/.botminter/config.yml"
PROJECT_NUM=""
if [ -f "$BM_CONFIG" ]; then
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

# ── Project ID (cached) ──────────────────────────────────────────────────────

PROJECT_ID=$(_cache_get "$CACHE_DIR/project_id" "$TTL_PROJECT" 2>/dev/null || true)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
  PROJECT_ID=$(gh project view "$PROJECT_NUM" --owner "$OWNER" --format json 2>&1 | jq -r '.id')
  if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    echo "❌ ERROR: Could not get project ID for project #$PROJECT_NUM"
    exit 1
  fi
  _cache_set "$CACHE_DIR/project_id" "$PROJECT_ID"
fi

# ── Field data (cached) ──────────────────────────────────────────────────────

FIELD_DATA=$(_cache_get "$CACHE_DIR/field_data" "$TTL_PROJECT" 2>/dev/null || true)
if [ -z "$FIELD_DATA" ]; then
  if ! FIELD_DATA=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json 2>&1); then
    echo "❌ ERROR: Could not fetch project field list"
    echo "$FIELD_DATA"
    exit 1
  fi
  if [ -z "$FIELD_DATA" ]; then
    echo "❌ ERROR: Empty response from project field list"
    exit 1
  fi
  _cache_set "$CACHE_DIR/field_data" "$FIELD_DATA"
fi

# Extract Status field ID with validation
STATUS_FIELD_ID=$(echo "$FIELD_DATA" | jq -r '.fields[] | select(.name=="Status") | .id')
if [ -z "$STATUS_FIELD_ID" ] || [ "$STATUS_FIELD_ID" = "null" ]; then
  echo "❌ ERROR: No 'Status' field found in project #$PROJECT_NUM"
  echo "Available fields:"
  echo "$FIELD_DATA" | jq -r '.fields[] | .name'
  exit 1
fi

echo "✓ Setup complete: $TEAM_REPO, project #$PROJECT_NUM"

# Export variables for use in calling scripts
export TEAM_REPO OWNER PROJECT_NUM PROJECT_ID FIELD_DATA STATUS_FIELD_ID ROLE EMOJI
export CACHE_DIR TTL_IMMUTABLE
export -f _gh_cache_dir _cache_fresh _cache_get _cache_set
