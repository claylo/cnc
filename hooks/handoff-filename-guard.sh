#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "handoff-filename-guard" || exit 0

# PreToolUse hook: enforces YYYY-MM-DD-HHMM-<description>.md naming
# for files written to .handoffs/

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Only act on .handoffs/ paths
[[ "$file_path" == */.handoffs/* ]] || exit 0

# Edit on an existing file older than 30 min: allow (historical maintenance)
if [[ "$tool_name" == "Edit" && -f "$file_path" ]]; then
  now_epoch=$(date +%s)
  file_epoch=$(stat -f %m "$file_path" 2>/dev/null || stat -c %Y "$file_path" 2>/dev/null || echo 0)
  age=$(( now_epoch - file_epoch ))
  if (( age > 1800 )); then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"historical handoff edit allowed"}}
EOF
    exit 0
  fi
fi

basename=$(basename "$file_path")
dirpath=$(dirname "$file_path")

# Strip leading digits and hyphens to get the description portion
description="${basename#"${basename%%[!0-9-]*}"}"

# Current timestamp — allow off-by-one minute for writes that land on the cusp
now=$(date +%Y-%m-%d-%H%M)
prev=$(date -v-1M +%Y-%m-%d-%H%M 2>/dev/null || date -d '1 minute ago' +%Y-%m-%d-%H%M 2>/dev/null || echo "")

correct="${now}-${description}"
correct_path="${dirpath}/${correct}"

# If the filename matches current or previous minute, allow
if [[ "$basename" == "${now}-${description}" ]] || [[ -n "$prev" && "$basename" == "${prev}-${description}" ]]; then
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"handoff filename OK"}}
EOF
  exit 0
fi

# Block and tell the agent the correct filename
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Wrong handoff filename. Use: ${correct_path}"}}
EOF
