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

# Extract everything after "cncflip"
args=$(echo "$prompt" | sed -n 's|.*/cncflip[[:space:]]*||p' | xargs)

# Parse --global flag
global_mode=false
if [[ "$args" == --global* ]]; then
  global_mode=true
  args="${args#--global}"
  args=$(echo "$args" | xargs)
fi

hook_name="$args"

config=".claude/settings.local.json"

# Ensure project config exists
if [[ ! -f "$config" ]]; then
  mkdir -p .claude
  echo '{}' > "$config"
fi
if ! jq -e '.cnc.hooks' "$config" &>/dev/null; then
  tmp=$(mktemp)
  jq '.cnc.hooks = {}' "$config" > "$tmp" && mv "$tmp" "$config"
fi

# Ensure global config exists when in global mode
if [[ "$global_mode" == true ]]; then
  mkdir -p "$(dirname "$CNC_GLOBAL_CONFIG")"
  [[ -f "$CNC_GLOBAL_CONFIG" ]] || echo '{}' > "$CNC_GLOBAL_CONFIG"
fi

# Load both configs once
project_data=$(cat "$config")
global_data='{}'
[[ -f "$CNC_GLOBAL_CONFIG" ]] && global_data=$(cat "$CNC_GLOBAL_CONFIG")

# Known hooks
hooks=("handoff-filename-guard" "for-the-record" "rustfmt-on-save" "clippy-harvest" "oops" "wiretap" "session-start" "vent")

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
  tmp=$(mktemp)
  jq --arg hook "$hook_name" --argjson val "$new_val" '.[$hook] = $val' "$CNC_GLOBAL_CONFIG" > "$tmp" && mv "$tmp" "$CNC_GLOBAL_CONFIG"
  echo "Toggled $hook_name → $label (global)"
else
  state=$(_resolve "$_jq_effective" "$hook_name")
  if [[ "$state" == OFF* ]]; then
    new_val="true"; label="on"
  else
    new_val="false"; label="OFF"
  fi
  tmp=$(mktemp)
  jq --arg hook "$hook_name" --argjson val "$new_val" '.cnc.hooks[$hook] = $val' "$config" > "$tmp" && mv "$tmp" "$config"
  echo "Toggled $hook_name → $label"
fi
