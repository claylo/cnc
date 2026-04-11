#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "clippy-harvest" || exit 0

# PostToolUse hook on Bash: harvest clippy lints from actual cargo output.
# Zero-cost — no parallel compile, just parses what already ran.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only act on cargo commands
[[ "$command" == *"cargo "* ]] || exit 0

# Extract output — handle both string and structured tool_response
# (Claude Code's PostToolUse payload uses .tool_response, not .tool_output)
output=$(echo "$input" | jq -r '
  if (.tool_response | type) == "string" then .tool_response
  elif (.tool_response | type) == "object" then
    [.tool_response.stdout // "", .tool_response.stderr // ""] | join("\n")
  else ""
  end
')

# Quick check — bail if no clippy lints in output
[[ "$output" == *"clippy::"* ]] || exit 0

log_dir="${HOME}/.local/share/cnc"
log_file="${log_dir}/clippy-harvest.jsonl"
mkdir -p "$log_dir"

# Parse clippy warning blocks from human-readable output.
# Tracks state across lines: warning/error → file location → lint name.
lints=$(echo "$output" | awk -v ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
/^(warning|error)(\[[A-Z][0-9]+\])?: / {
  if (/generated [0-9]+ warning/) next
  level = "warning"
  if (/^error/) level = "error"
  sub(/^(warning|error)(\[[^\]]+\])?: /, "")
  message = $0
  gsub(/"/, "\\\"", message)
  file = ""; line = 0
}

/^[[:space:]]+--> / {
  s = $0
  sub(/^[[:space:]]+--> /, "", s)
  n = split(s, loc, ":")
  file = loc[1]
  line = (n >= 2) ? loc[2]+0 : 0
}

/clippy::[a-z_]+/ {
  match($0, /clippy::[a-z_]+/)
  lint = substr($0, RSTART, RLENGTH)
  if (lint != "" && message != "") {
    printf "{\"lint\":\"%s\",\"level\":\"%s\",\"file\":\"%s\",\"line\":%d,\"message\":\"%s\",\"ts\":\"%s\"}\n", \
      lint, level, (file != "" ? file : "unknown"), line, message, ts
  }
  lint = ""; file = ""; message = ""; line = 0; level = "warning"
}')

[[ -n "$lints" ]] || exit 0

# Serialize appends across concurrent Claude sessions (see wiretap.sh for
# the PIPE_BUF race this prevents).
if command -v flock >/dev/null 2>&1; then
  (
    flock -x -w 5 9 || exit 0
    printf '%s\n' "$lints" >&9
  ) 9>>"$log_file"
else
  printf '%s\n' "$lints" >> "$log_file"
fi
