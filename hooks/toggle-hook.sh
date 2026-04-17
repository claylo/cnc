#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"

# UserPromptSubmit hook: toggle cnc hooks on/off
#
# /cncflip                       — list all hooks and their current state
# /cncflip <hook-name>           — flip the named hook (project-level)
# /cncflip --global <hook-name>  — flip the named hook (global default)
# /cncflip --global              — list global defaults only

input=$(cat)
prompt=$(echo "$input" | jq -r '.user_prompt // empty')

# Only act on /cncflip commands (plain or plugin-namespaced /cnc:cncflip)
[[ "$prompt" == */cncflip* || "$prompt" == */cnc:cncflip* ]] || exit 0

# Extract everything after "cncflip"
args=$(echo "$prompt" | sed -E -n 's|.*/(cnc:)?cncflip[[:space:]]*||p' | xargs)

# Parse --global flag
global_mode=false
if [[ "$args" == --global* ]]; then
  global_mode=true
  args="${args#--global}"
  args=$(echo "$args" | xargs)
fi

hook_name="$args"

config=".claude/settings.local.json"

# Load both configs without mutating anything.
# Missing files become empty objects; scaffolding is deferred to the
# toggle branches so a plain list call never writes to disk.
project_data='{}'
[[ -f "$config" ]] && project_data=$(cat "$config")

global_data='{}'
[[ -f "$CNC_GLOBAL_CONFIG" ]] && global_data=$(cat "$CNC_GLOBAL_CONFIG")

# Known hooks
hooks=("handoff-filename-guard" "for-the-record" "rustfmt-on-save" "clippy-harvest" "oops" "wiretap" "session-start" "vent" "context-warn" "mcp-probe")

# jq expressions for resolving state (one call per hook, both files as args)
# Effective: project > global > default
_jq_effective='
  ($project.cnc.hooks[$hook]) as $p |
  ($global[$hook]) as $g |
  if $p != null then (if $p == false then "OFF" else "on" end)
  elif $g != null then (if $g == false then "OFF (global)" else "on (global)" end)
  else "on"
  end
'
# Global only
_jq_global='
  ($global[$hook]) as $g |
  if $g != null then (if $g == false then "OFF" else "on" end)
  else "(unset)"
  end
'

_resolve() {
  local expr="$1" h="$2"
  jq -n -r --argjson project "$project_data" --argjson global "$global_data" --arg hook "$h" "$expr"
}

# --- WIRETAP EVENT MODE ---
# /cncflip wiretap:              → list all wiretap-wired events + state
# /cncflip wiretap:<event>       → flip project-level
# /cncflip --global wiretap:...  → same, global
if [[ "$hook_name" == wiretap:* ]]; then
  event="${hook_name#wiretap:}"
  hooks_json="$(dirname "$0")/hooks.json"

  # Source of truth for which events can be wiretapped: every event that
  # has a hook registered invoking wiretap.sh.
  wt_events=$(jq -r '
    .hooks
    | to_entries[]
    | select(.value[].hooks[]?.command | tostring | contains("wiretap.sh"))
    | .key
  ' "$hooks_json" | sort -u)

  _jq_wt_effective='
    ($project.cnc.wiretap.events[$hook]) as $p |
    ($global.wiretap.events[$hook]) as $g |
    if $p != null then (if $p == false then "OFF" else "on" end)
    elif $g != null then (if $g == false then "OFF (global)" else "on (global)" end)
    else "on"
    end
  '
  _jq_wt_global='
    ($global.wiretap.events[$hook]) as $g |
    if $g != null then (if $g == false then "OFF" else "on" end)
    else "(unset)"
    end
  '

  # LIST
  if [[ -z "$event" ]]; then
    if [[ "$global_mode" == true ]]; then
      echo "cnc wiretap events — global (~/.config/cnc/defaults.json):"
      while IFS= read -r e; do
        echo "  $e: $(_resolve "$_jq_wt_global" "$e")"
      done <<<"$wt_events"
    else
      echo "cnc wiretap events (.claude/settings.local.json):"
      while IFS= read -r e; do
        echo "  $e: $(_resolve "$_jq_wt_effective" "$e")"
      done <<<"$wt_events"
    fi
    exit 0
  fi

  # TOGGLE — validate event is actually wiretapped
  if ! grep -qx "$event" <<<"$wt_events"; then
    echo "Unknown wiretap event: $event"
    echo "Available:"
    while IFS= read -r e; do echo "  $e"; done <<<"$wt_events"
    exit 0
  fi

  if [[ "$global_mode" == true ]]; then
    current=$(_resolve "$_jq_wt_global" "$event")
    if [[ "$current" == "OFF" ]]; then
      new_val="true"; label="on"
    else
      new_val="false"; label="OFF"
    fi
    mkdir -p "$(dirname "$CNC_GLOBAL_CONFIG")"
    tmp=$(mktemp)
    jq -n --argjson global "$global_data" --arg event "$event" --argjson val "$new_val" \
      '$global | .wiretap.events[$event] = $val' > "$tmp" && mv "$tmp" "$CNC_GLOBAL_CONFIG"
    echo "Toggled wiretap:$event → $label (global)"
  else
    state=$(_resolve "$_jq_wt_effective" "$event")
    if [[ "$state" == OFF* ]]; then
      new_val="true"; label="on"
    else
      new_val="false"; label="OFF"
    fi
    mkdir -p .claude
    tmp=$(mktemp)
    jq --arg event "$event" --argjson val "$new_val" \
      '.cnc.wiretap.events[$event] = $val' <<<"$project_data" > "$tmp" && mv "$tmp" "$config"
    echo "Toggled wiretap:$event → $label"
  fi
  exit 0
fi

# --- LIST MODE ---
if [[ -z "$hook_name" ]]; then
  if [[ "$global_mode" == true ]]; then
    echo "cnc global defaults (~/.config/cnc/defaults.json):"
    for h in "${hooks[@]}"; do
      echo "  $h: $(_resolve "$_jq_global" "$h")"
    done
  else
    echo "cnc hook toggles (.claude/settings.local.json):"
    for h in "${hooks[@]}"; do
      echo "  $h: $(_resolve "$_jq_effective" "$h")"
    done
  fi
  exit 0
fi

# --- TOGGLE MODE ---

# Validate hook name
found=false
for h in "${hooks[@]}"; do
  [[ "$h" == "$hook_name" ]] && found=true && break
done

if [[ "$found" != "true" ]]; then
  echo "Unknown hook: $hook_name"
  echo "Available: ${hooks[*]}"
  exit 0
fi

if [[ "$global_mode" == true ]]; then
  current=$(_resolve "$_jq_global" "$hook_name")
  if [[ "$current" == "OFF" ]]; then
    new_val="true"; label="on"
  else
    new_val="false"; label="OFF"
  fi
  # Scaffold only at write time — atomic tmp+mv
  mkdir -p "$(dirname "$CNC_GLOBAL_CONFIG")"
  tmp=$(mktemp)
  jq -n --argjson global "$global_data" --arg hook "$hook_name" --argjson val "$new_val" \
    '$global | .[$hook] = $val' > "$tmp" && mv "$tmp" "$CNC_GLOBAL_CONFIG"
  echo "Toggled $hook_name → $label (global)"
else
  state=$(_resolve "$_jq_effective" "$hook_name")
  if [[ "$state" == OFF* ]]; then
    new_val="true"; label="on"
  else
    new_val="false"; label="OFF"
  fi
  # Scaffold only at write time — jq creates .cnc and .cnc.hooks
  # automatically when the path doesn't exist.
  mkdir -p .claude
  tmp=$(mktemp)
  jq --arg hook "$hook_name" --argjson val "$new_val" '.cnc.hooks[$hook] = $val' <<<"$project_data" > "$tmp" && mv "$tmp" "$config"
  echo "Toggled $hook_name → $label"
fi
