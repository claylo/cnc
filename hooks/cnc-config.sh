#!/usr/bin/env bash
# Shared config check for cnc hooks.
# Source this, then: cnc_enabled "hook-name" || exit 0
#
# Precedence: project (.claude/settings.local.json) > global (~/.config/cnc/defaults.json) > default (on)
# One jq call resolves the cascade. Uses != null (not //) because jq's // treats false as falsy.

CNC_GLOBAL_CONFIG="${HOME}/.config/cnc/defaults.json"
CNC_LOG_DIR="${HOME}/.local/share/cnc"

# ERR trap: log hook errors to oops.jsonl so we're not blind to our own failures.
# Every hook sources this file, so the trap covers all of them.
cnc_on_error() {
  local exit_code=$?
  local line="${BASH_LINENO[0]}"
  local src="${BASH_SOURCE[1]:-$0}"
  local log_file="${CNC_LOG_DIR}/oops.jsonl"
  mkdir -p "$CNC_LOG_DIR"
  # Use printf fallback in case jq is the thing that broke
  if command -v jq >/dev/null 2>&1; then
    jq -n -c \
      --arg hook "$(basename "$src")" \
      --arg source "${src}:${line}" \
      --argjson exit_code "$exit_code" \
      '{hook_error: true, hook: $hook, source: $source, exit_code: $exit_code, ts: now | todate}' \
      >> "$log_file" 2>/dev/null
  else
    printf '{"hook_error":true,"hook":"%s","source":"%s:%s","exit_code":%d}\n' \
      "$(basename "$src")" "$src" "$line" "$exit_code" \
      >> "$log_file" 2>/dev/null
  fi
}
trap cnc_on_error ERR

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
