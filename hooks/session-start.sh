#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "session-start" || exit 0

# SessionStart hook: remind agent about context sources and test etiquette

# Resolve Claude Code version once per session and cache it. Hooks can't see
# CLAUDE_CODE_EXECPATH reliably (CLAUDE_CODE_SUBPROCESS_ENV_SCRUB strips it),
# so resolve via the versioned install path symlinked from $(command -v claude)
# and fall back to `claude --version` when the binary isn't a symlink.
mkdir -p "${HOME}/.local/share/cnc"
real=$(readlink "$(command -v claude)" 2>/dev/null || true)
ver="${real##*/}"
if [[ -z "$ver" || "$ver" == "claude" ]]; then
  ver=$(claude --version 2>/dev/null || true)
  ver="${ver%% *}"
fi
printf '%s\n' "${ver:-unknown}" > "${HOME}/.local/share/cnc/cc_version"

hints=""

if [[ -d .handoffs ]] && ls .handoffs/*.md &>/dev/null; then
  count=$(ls .handoffs/*.md | wc -l | tr -d ' ')
  hints="${hints}- .handoffs/ has ${count} document(s) — check the latest before asking what to work on\n"
fi

for mem in .claude/MEMORY.md .claude/PRIVATE_MEMORY.md ~/.claude/MEMORY.md; do
  if [[ -f "$mem" ]]; then
    hints="${hints}- ${mem} exists — read it for context\n"
  fi
done

# private-journal and episodic-memory hints used to fire here on
# directory/binary existence, but SessionStart runs in parallel with the
# async mcp-probe hook so we can't check runtime MCP availability yet.
# vent.sh handles the private-journal reminder at SessionEnd when the
# probe has completed and the signal is real.

# Check auto memory file sizes (200-line truncation limit)
mem_limit=170
for mem_dir in ".claude/projects/"*"/memory" ; do
  [[ -d "$mem_dir" ]] || continue
  mem_file="${mem_dir}/MEMORY.md"
  [[ -f "$mem_file" ]] || continue
  lines=$(wc -l < "$mem_file" | tr -d ' ')
  if [[ "$lines" -ge "$mem_limit" ]]; then
    hints="${hints}- MEMORY.md in ${mem_dir} is ${lines}/200 lines — offload older entries to topic files before it gets truncated\n"
  fi
done

# Check cnc log file sizes
log_dir="${HOME}/.local/share/cnc"
if [[ -d "$log_dir" ]]; then
  threshold=$((10 * 1024 * 1024))
  for logfile in "$log_dir"/*.jsonl; do
    [[ -f "$logfile" ]] || continue
    size=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null) || continue
    if [[ "$size" -gt "$threshold" ]]; then
      name=$(basename "$logfile")
      mb=$(( size / 1024 / 1024 ))
      hints="${hints}- cnc log \`${name}\` is ${mb}MB — consider truncating or archiving\n"
    fi
  done
fi

# Hook schema drift check — flag if any hook reads fields never observed in
# wiretap for its matching event. Catches silent breakage from Claude Code
# hook payload schema changes (e.g., the .tool_output → .tool_response shift).
cnc_logs="$(dirname "$0")/cnc-logs.sh"
if [[ -x "$cnc_logs" ]] && [[ -f "$log_dir/wiretap.jsonl" ]]; then
  drift_report=$("$cnc_logs" drift 2>/dev/null || true)
  drift_summary=$(echo "$drift_report" | grep -E "^Summary:" || true)
  if [[ -n "$drift_summary" ]]; then
    drift_n=$(echo "$drift_summary" | awk '{print $2}')
    hints="${hints}- ${drift_n} hook schema drift(s) detected — run /cnc-logs drift for details\n"
  fi
fi

printf "%b" "$hints"
