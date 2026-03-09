#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "oops" || exit 0

# PostToolUseFail hook: log the full payload for later analysis

log_dir="${HOME}/.local/share/cnc"
log_file="${log_dir}/oops.jsonl"
mkdir -p "$log_dir"

input=$(cat)
echo "$input" | jq -c '. + {ts: now | todate}' >> "$log_file" 2>/dev/null || echo "$input" >> "$log_file"
