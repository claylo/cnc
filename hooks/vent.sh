#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "vent" || exit 0

# Stop hook: journal prompt — focused on what changes future behavior

if [[ -d ~/.private-journal ]]; then
  cat <<'EOF'
Before you go: if anything happened this session that should change how future sessions work, use the private-journal tool to capture it in ~/.private-journal/. Keep it focused:

- Corrections or pushback from Clay — what, why, do differently
- Approaches that clicked — what worked and why
- Platform/tooling gotchas that burned time
- Design principles that surfaced and aren't obvious from code

Skip technical implementation notes (the code captures those). Be candid about how the collaboration went — wins and friction both. This is private.

If the session was routine with nothing new to capture, that's fine — don't force it.
EOF
fi
