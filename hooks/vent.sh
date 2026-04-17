#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "vent" || exit 0

# SessionEnd hook: journal prompt — focused on what changes future behavior.
# Only fires when the private-journal MCP server is actually connected in
# this session. The cnc mcp-probe async SessionStart hook populates the
# cache this reads.

input=$(cat)
session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)
[[ -n "$session_id" ]] || exit 0

if cnc_mcp_connected "private-journal" "$session_id"; then
  cat <<'EOF'
Before you go: if anything happened this session that should change how future sessions work, use the private-journal tool to capture it in ~/.private-journal/. Keep it focused:

- Corrections or pushback from the user — what, why, do differently
- Approaches that clicked — what worked and why
- Platform/tooling gotchas that burned time
- Design principles that surfaced and aren't obvious from code

Skip technical implementation notes (the code captures those). Be candid about how the collaboration went — wins and friction both. This is private.

If the session was routine with nothing new to capture, that's fine — don't force it.
EOF
fi
