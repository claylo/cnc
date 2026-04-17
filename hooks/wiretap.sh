#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "wiretap" || exit 0

# Log undocumented/interesting hook events to see what's in the payload

log_dir="${HOME}/.local/share/cnc"
log_file="${log_dir}/wiretap.jsonl"
mkdir -p "$log_dir"

input=$(cat)

# Per-event filter: hooks.json wires wiretap to every Claude Code event,
# but the user chooses which ones to log via config (cnc.wiretap.events.<Event>).
# Default is "log everything" so new users see full coverage out of the box.
event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null || true)
if [[ -n "$event" ]]; then
  cnc_wiretap_event_enabled "$event" || exit 0
fi

# Stamp every captured record with ts and cc_version. Version is resolved
# once at SessionStart and cached to disk; CLAUDE_CODE_EXECPATH is stripped
# from hook subprocesses by CLAUDE_CODE_SUBPROCESS_ENV_SCRUB.
cc_ver=$(cat "${log_dir}/cc_version" 2>/dev/null || echo unknown)
jq_filter='. + {ts: now | todate, cc_version: $cc_ver}'

# Serialize appends across concurrent Claude sessions. POSIX O_APPEND is
# atomic only for writes ≤ PIPE_BUF (4096 on macOS); larger payloads like
# InstructionsLoaded with CLAUDE.md contents can interleave when two
# sessions append at the same time, producing unparseable JSONL.
if command -v flock >/dev/null 2>&1; then
  (
    flock -x -w 5 9 || exit 0
    echo "$input" | jq -c --arg cc_ver "$cc_ver" "$jq_filter" >&9 2>/dev/null || echo "$input" >&9
  ) 9>>"$log_file"
else
  echo "$input" | jq -c --arg cc_ver "$cc_ver" "$jq_filter" >> "$log_file" 2>/dev/null || echo "$input" >> "$log_file"
fi
