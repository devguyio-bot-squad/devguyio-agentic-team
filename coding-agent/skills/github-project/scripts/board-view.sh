#!/bin/bash
# Display all issues grouped by project status with epic-to-story relationships
#
# Always fetches fresh from GitHub (this IS the re-fetch for dispatch decisions).
# Saves the result to the board state cache for other scripts to read within
# the same cycle.

# Source common setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup.sh"

# Fetch all project items (always fresh)
BOARD_JSON=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json --limit 1000)

# Save to board state cache for intra-cycle reads
BOARD_CACHE=$(_board_cache_path)
echo "$BOARD_JSON" > "$BOARD_CACHE" 2>/dev/null || true

# Output to stdout
echo "$BOARD_JSON"
