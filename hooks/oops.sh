#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "oops" || exit 0

# PostToolUseFail hook: log the full payload for later analysis

log_file="${CNC_LOG_DIR}/oops.jsonl"
mkdir -p "$CNC_LOG_DIR"

input=$(cat)

# Serialize appends across concurrent Claude sessions (see wiretap.sh for
# the PIPE_BUF race this prevents).
if command -v flock >/dev/null 2>&1; then
  (
    flock -x -w 5 9 || exit 0
    echo "$input" | jq -c '. + {ts: now | todate}' >&9 2>/dev/null || echo "$input" >&9
  ) 9>>"$log_file"
else
  echo "$input" | jq -c '. + {ts: now | todate}' >> "$log_file" 2>/dev/null || echo "$input" >> "$log_file"
fi
