#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "wiretap" || exit 0

# Log undocumented/interesting hook events to see what's in the payload

log_dir="${HOME}/.local/share/cnc"
log_file="${log_dir}/wiretap.jsonl"
mkdir -p "$log_dir"

input=$(cat)
echo "$input" | jq -c '. + {ts: now | todate}' >> "$log_file" 2>/dev/null || echo "$input" >> "$log_file"
