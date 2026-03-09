#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "vent" || exit 0

# Stop hook: remind agent to journal about the session

if [[ -d ~/.private-journal ]] || [[ -d .private-journal ]]; then
  cat <<'EOF'
Before you go: use the private-journal tool to write honestly about how this session went. Not a status report — how you *felt* about the work. What was frustrating, what clicked, what you'd do differently. Be candid. This is private.
EOF
fi
