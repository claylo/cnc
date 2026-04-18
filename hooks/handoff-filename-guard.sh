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

# User-configurable drift tolerance (plugin.json → userConfig). Default 5 min.
# This is the window that catches "agent swagged the timestamp and got it off
# by hours" without being pedantic about a few minutes of clock skew.
drift_minutes="${CLAUDE_PLUGIN_OPTION_HANDOFF_DRIFT_MINUTES:-5}"
[[ "$drift_minutes" =~ ^[0-9]+$ ]] || drift_minutes=5

now=$(date +%Y-%m-%d-%H%M)
now_epoch=$(date +%s)

correct="${now}-${description}"
correct_path="${dirpath}/${correct}"

# Extract the YYYY-MM-DD-HHMM prefix from the basename (if present).
stamp_prefix=$(echo "$basename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}' || true)

if [[ -n "$stamp_prefix" ]]; then
  # Parse to epoch. macOS uses -j -f; GNU uses -d with a reformatted string.
  d="${stamp_prefix:0:10}"
  hh="${stamp_prefix:11:2}"
  mm="${stamp_prefix:13:2}"
  file_epoch=$(date -j -f "%Y-%m-%d-%H%M" "$stamp_prefix" +%s 2>/dev/null \
               || date -d "${d} ${hh}:${mm}" +%s 2>/dev/null \
               || echo "")
  if [[ -n "$file_epoch" ]]; then
    diff=$(( now_epoch - file_epoch ))
    abs=${diff#-}
    if (( abs <= drift_minutes * 60 )); then
      cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"handoff filename OK"}}
EOF
      exit 0
    fi
  fi
fi

# Block and tell the agent the correct filename
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Wrong handoff filename. Use: ${correct_path}"}}
EOF
