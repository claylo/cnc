#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "session-start" || exit 0

# SessionStart hook: remind agent about context sources and test etiquette

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

if [[ -d ~/.private-journal ]] || [[ -d .private-journal ]]; then
  hints="${hints}- .private-journal entries exist — search before complex tasks\n"
fi

if command -v episodic-memory &>/dev/null; then
  hints="${hints}- episodic-memory is available — search past conversations when stuck or unsure\n"
fi

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

# Always include the test warning
hints="${hints}\nDo NOT run test suites without asking first. The machine is slow and test runs can take 10+ minutes. Ask before running tests."

printf "%b" "$hints"
