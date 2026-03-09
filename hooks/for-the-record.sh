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

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[[ -n "$file_path" ]] || exit 0

# Match docs/<record-subdir>/... — redirect to record/<subdir>/...
if [[ "$file_path" =~ /docs/(adrs|decisions|plans|reviews|specs|diagrams)/(.*) ]]; then
  subdir="${BASH_REMATCH[1]}"
  rest="${BASH_REMATCH[2]}"
  parent="${file_path%%/docs/${subdir}/${rest}}"
  correct="${parent}/record/${subdir}/${rest}"

  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"Wrong location. docs/ is for users. Use: ${correct}"}}
EOF
  exit 0
fi
