#!/usr/bin/env bash
# Shared config check for cnc hooks.
# Source this, then: cnc_enabled "hook-name" || exit 0
#
# Precedence: project (.claude/settings.local.json) > global (~/.config/cnc/defaults.json) > default (on)
# One jq call resolves the cascade. Uses != null (not //) because jq's // treats false as falsy.

CNC_GLOBAL_CONFIG="${HOME}/.config/cnc/defaults.json"

# Cascade expression reused by cnc_enabled and toggle-hook.sh
# Inputs: --argjson project, --argjson global, --arg hook
CNC_JQ_CASCADE='
  ($project.cnc.hooks[$hook]) as $p |
  ($global[$hook]) as $g |
  if $p != null then ($p != false)
  elif $g != null then ($g != false)
  else true
  end
'

cnc_enabled() {
  local hook="$1"
  local project='{}'
  local global='{}'
  [[ -f ".claude/settings.local.json" ]] && project=$(cat ".claude/settings.local.json")
  [[ -f "$CNC_GLOBAL_CONFIG" ]] && global=$(cat "$CNC_GLOBAL_CONFIG")

  jq -n -e \
    --argjson project "$project" \
    --argjson global "$global" \
    --arg hook "$hook" \
    "$CNC_JQ_CASCADE" > /dev/null 2>&1
}
