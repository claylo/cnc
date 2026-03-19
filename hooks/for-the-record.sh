#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "for-the-record" || exit 0

# PreToolUse hook: redirect record-keeping docs from docs/ to record/
#
# Policy:
#   docs/        → user-facing documentation (allowed)
#   record/      → internal project record (decisions, plans, reviews, specs, diagrams)
#
# Plugins like superpowers write to docs/decisions/, docs/plans/, etc.
# This hook intercepts and redirects without patching those plugins.
#
# If cnc is installed after superpowers has already created files in docs/,
# existing files are allowed through with a suggestion to move them.

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[[ -n "$file_path" ]] || exit 0

# Match docs/<record-subdir>/... — redirect to record/<subdir>/...
if [[ "$file_path" =~ /docs/(adrs|decisions|plans|reviews|specs|diagrams|superpowers)/(.*) ]]; then
  subdir="${BASH_REMATCH[1]}"
  rest="${BASH_REMATCH[2]}"
  parent="${file_path%%/docs/${subdir}/${rest}}"
  correct="${parent}/record/${subdir}/${rest}"

  # Write: always redirect — new files go in record/
  if [[ "$tool_name" == "Write" ]]; then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Wrong location. docs/ is for users. Use: ${correct}"}}
EOF
    exit 0
  fi

  # Read/Edit: if the file exists in docs/, allow but suggest moving
  if [[ -f "$file_path" ]]; then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Legacy location. The cnc plugin keeps record-keeping files in record/, not docs/. Suggest to user: mv docs/${subdir}/ record/${subdir}/"}}
EOF
    exit 0
  fi

  # File doesn't exist in docs/ — redirect to record/
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Not in docs/. Record-keeping files live in record/. Try: ${correct}"}}
EOF
  exit 0
fi
