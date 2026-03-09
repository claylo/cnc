#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "handoff-filename-guard" || exit 0

# PreToolUse hook: enforces YYYY-MM-DD-HHMM-<description>.md naming
# for files written to .handoffs/

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Only act on .handoffs/ paths
[[ "$file_path" == */.handoffs/* ]] || exit 0

basename=$(basename "$file_path")
dirpath=$(dirname "$file_path")

# Strip leading digits and hyphens to get the description portion
description="${basename#"${basename%%[!0-9-]*}"}"

# Current timestamp prefix
now=$(date +%Y-%m-%d-%H%M)

correct="${now}-${description}"
correct_path="${dirpath}/${correct}"

# If the filename already matches, allow
if [[ "$basename" == "$correct" ]]; then
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"handoff filename OK"}}
EOF
  exit 0
fi

# Block and tell the agent the correct filename
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"Wrong handoff filename. Use: ${correct_path}"}}
EOF
