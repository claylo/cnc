#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "wiretap" || exit 0

# Log undocumented/interesting hook events to see what's in the payload

log_dir="${HOME}/.local/share/cnc"
log_file="${log_dir}/wiretap.jsonl"
mkdir -p "$log_dir"

input=$(cat)

# Stamp every captured record with ts and cc_version. The version comes from
# CLAUDE_CODE_EXECPATH, which Claude Code sets to a versioned install path
# like /Users/x/.local/share/claude/versions/2.1.101 — zero-subprocess, and
# gives us a reliable axis for schema drift detection later.
jq_filter='. + {ts: now | todate, cc_version: ((env.CLAUDE_CODE_EXECPATH // "unknown/unknown") | split("/") | last)}'

# Serialize appends across concurrent Claude sessions. POSIX O_APPEND is
# atomic only for writes ≤ PIPE_BUF (4096 on macOS); larger payloads like
# InstructionsLoaded with CLAUDE.md contents can interleave when two
# sessions append at the same time, producing unparseable JSONL.
if command -v flock >/dev/null 2>&1; then
  (
    flock -x -w 5 9 || exit 0
    echo "$input" | jq -c "$jq_filter" >&9 2>/dev/null || echo "$input" >&9
  ) 9>>"$log_file"
else
  echo "$input" | jq -c "$jq_filter" >> "$log_file" 2>/dev/null || echo "$input" >> "$log_file"
fi
