#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "rustfmt-on-save" || exit 0

# PostToolUse hook: rustfmt + ast-grep scan on .rs files after Write/Edit.
# Logs per-run outcome to rustfmt.jsonl so the hook's work is observable
# via /cnc-logs rustfmt.

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[[ "$file_path" == *.rs ]] || exit 0
[[ -f "$file_path" ]] || exit 0

# rustfmt pass — capture sha256 before/after to detect whether it reformatted
rustfmt_ran=false
changed=false
if command -v rustfmt &>/dev/null; then
  rustfmt_ran=true
  before=$(shasum -a 256 "$file_path" | awk '{print $1}')
  rustfmt --edition 2024 --style-edition 2024 "$file_path" 2>&1 || true
  after=$(shasum -a 256 "$file_path" | awk '{print $1}')
  [[ "$before" != "$after" ]] && changed=true
fi

# ast-grep lint pass (clippy-lite, no compilation)
sg_scanned=false
sg_hits=0
sg_rules='[]'
sg_config="$(dirname "$0")/../sgconfig.yml"
if command -v sg &>/dev/null && [[ -f "$sg_config" ]]; then
  sg_scanned=true
  # Human-readable output to stdout — the agent reads this to self-correct
  sg scan --config "$sg_config" "$file_path" 2>/dev/null || true
  # Structured JSON to harvest rule-hit counts for the log
  sg_json=$(sg scan --config "$sg_config" --json=stream "$file_path" 2>/dev/null || true)
  if [[ -n "$sg_json" ]]; then
    sg_hits=$(echo "$sg_json" | jq -s 'length')
    sg_rules=$(echo "$sg_json" | jq -cs '[.[].ruleId] | unique')
  fi
fi

# Log the run — best-effort, never fail the hook
log_file="${CNC_LOG_DIR}/rustfmt.jsonl"
mkdir -p "$CNC_LOG_DIR"

line=$(jq -c -n \
  --arg file "$file_path" \
  --argjson rustfmt_ran "$rustfmt_ran" \
  --argjson changed "$changed" \
  --argjson sg_scanned "$sg_scanned" \
  --argjson sg_hits "$sg_hits" \
  --argjson sg_rules "$sg_rules" \
  '{
    ts: (now | todate),
    file: $file,
    rustfmt_ran: $rustfmt_ran,
    changed: $changed,
    sg_scanned: $sg_scanned,
    sg_hits: $sg_hits,
    sg_rules: $sg_rules
  }' 2>/dev/null || true)

[[ -n "$line" ]] || exit 0

# Serialize appends across concurrent Claude sessions (see wiretap.sh for
# the PIPE_BUF race this prevents).
if command -v flock >/dev/null 2>&1; then
  (
    flock -x -w 5 9 || exit 0
    printf '%s\n' "$line" >&9
  ) 9>>"$log_file"
else
  printf '%s\n' "$line" >> "$log_file"
fi
