#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"

# cnc log analysis script, invoked by skills/cnc-logs/SKILL.md via the
# skill's inline `!` block. Accepts positional args directly — no stdin
# parsing, no UserPromptSubmit wiring.
#
# ./cnc-logs.sh                — summary dashboard
# ./cnc-logs.sh oops           — tool failure breakdown
# ./cnc-logs.sh wiretap        — hook event breakdown
# ./cnc-logs.sh rustfmt        — rustfmt-on-save runs and ast-grep hits
# ./cnc-logs.sh harvest        — clippy lint analysis
# ./cnc-logs.sh <name> --tail  — last 10 raw entries

args="$*"

log_dir="$CNC_LOG_DIR"

# Helper: entry count and last timestamp for a log file
log_stats() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local count size last
    count=$(wc -l < "$f" | tr -d ' ')
    size=$(ls -lh "$f" | awk '{print $5}')
    last=$(tail -1 "$f" | jq -r '.ts // empty' 2>/dev/null | cut -c1-16 || echo "?")
    printf "%s entries  %s  (last: %s)" "$count" "$size" "$last"
  else
    echo "no data"
  fi
}

show_summary() {
  echo "=== cnc logs ==="
  echo ""
  printf "  %-22s %s\n" "oops.jsonl" "$(log_stats "$log_dir/oops.jsonl")"
  printf "  %-22s %s\n" "wiretap.jsonl" "$(log_stats "$log_dir/wiretap.jsonl")"
  printf "  %-22s %s\n" "rustfmt.jsonl" "$(log_stats "$log_dir/rustfmt.jsonl")"
  printf "  %-22s %s\n" "clippy-harvest.jsonl" "$(log_stats "$log_dir/clippy-harvest.jsonl")"
  echo ""

  if [[ -f "$log_dir/oops.jsonl" ]]; then
    echo "Top oops:"
    jq -r '.tool_name // "unknown"' "$log_dir/oops.jsonl" | sort | uniq -c | sort -rn | head -5 | while read -r c t; do
      printf "  %4s  %s\n" "$c" "$t"
    done
    echo ""
  fi

  if [[ -f "$log_dir/wiretap.jsonl" ]]; then
    echo "Wiretap events:"
    # -R + fromjson? skips any interleaved/malformed lines from concurrent
    # writers instead of halting mid-stream (see wiretap.sh for the race)
    jq -R -r 'fromjson? | .hook_event_name // "unknown"' "$log_dir/wiretap.jsonl" | sort | uniq -c | sort -rn | while read -r c t; do
      printf "  %4s  %s\n" "$c" "$t"
    done
    echo ""
  fi

  if [[ -f "$log_dir/rustfmt.jsonl" ]]; then
    local rf_total rf_changed rf_rule_hits
    rf_total=$(wc -l < "$log_dir/rustfmt.jsonl" | tr -d ' ')
    rf_changed=$(jq -s '[.[] | select(.changed == true)] | length' "$log_dir/rustfmt.jsonl" 2>/dev/null || echo 0)
    rf_rule_hits=$(jq -s '[.[].sg_rules // [] | length] | add // 0' "$log_dir/rustfmt.jsonl" 2>/dev/null || echo 0)
    echo "Rustfmt-on-save: $rf_total runs, $rf_changed reformatted, $rf_rule_hits ast-grep hits"
    echo ""
  fi

  if [[ -f "$log_dir/clippy-harvest.jsonl" ]]; then
    local harvest_count
    harvest_count=$(wc -l < "$log_dir/clippy-harvest.jsonl" | tr -d ' ')
    echo "Harvest: $harvest_count lints captured"
    if [[ "$harvest_count" -gt 0 ]]; then
      jq -r '.lint' "$log_dir/clippy-harvest.jsonl" | sort | uniq -c | sort -rn | head -5 | while read -r c t; do
        printf "  %4s  %s\n" "$c" "$t"
      done
    fi
  fi
}

show_oops() {
  local f="$log_dir/oops.jsonl"
  [[ -f "$f" ]] || { echo "No oops data."; return; }

  echo "=== oops: tool failures ==="
  echo ""
  echo "By tool:"
  jq -r '.tool_name // "unknown"' "$f" | sort | uniq -c | sort -rn | head -10 | while read -r c t; do
    printf "  %4s  %s\n" "$c" "$t"
  done
  echo ""

  echo "Common errors (first line):"
  jq -r '(.error // "unknown") | split("\n")[0] | .[0:80]' "$f" | sort | uniq -c | sort -rn | head -10 | while read -r c t; do
    printf "  %4s  %s\n" "$c" "$t"
  done
  echo ""

  echo "Last 5:"
  tail -5 "$f" | jq -r '
    [.ts[0:16] // "?", .tool_name // "?", ((.error // "?") | split("\n")[0] | .[0:80])] | join("  ")
  ' 2>/dev/null
}

show_wiretap() {
  local f="$log_dir/wiretap.jsonl"
  [[ -f "$f" ]] || { echo "No wiretap data."; return; }

  echo "=== wiretap: hook events ==="
  echo ""
  echo "By event:"
  # -R + fromjson? skips any interleaved/malformed lines from concurrent
  # writers instead of halting mid-stream (see wiretap.sh for the race)
  jq -R -r 'fromjson? | .hook_event_name // "unknown"' "$f" | sort | uniq -c | sort -rn | while read -r c t; do
    printf "  %4s  %s\n" "$c" "$t"
  done
  echo ""

  echo "Last 5:"
  tail -5 "$f" | jq -R -r 'fromjson? |
    [.ts[0:16] // "?", .hook_event_name // "?", .file_path // .load_reason // ""] | join("  ")
  ' 2>/dev/null
}

show_harvest() {
  local analyzer
  analyzer="$(dirname "$0")/clippy-analyze.sh"
  if [[ -x "$analyzer" ]]; then
    bash "$analyzer"
  else
    local f="$log_dir/clippy-harvest.jsonl"
    [[ -f "$f" ]] || { echo "No harvest data."; return; }
    echo "=== clippy harvest ==="
    echo ""
    jq -r '.lint' "$f" | sort | uniq -c | sort -rn
  fi
}

show_rustfmt() {
  local f="$log_dir/rustfmt.jsonl"
  [[ -f "$f" ]] || { echo "No rustfmt data."; return; }

  echo "=== rustfmt-on-save ==="
  echo ""

  local total reformatted with_hits
  total=$(wc -l < "$f" | tr -d ' ')
  reformatted=$(jq -s '[.[] | select(.changed == true)] | length' "$f")
  with_hits=$(jq -s '[.[] | select(.sg_hits > 0)] | length' "$f")
  echo "$total runs  ·  $reformatted reformatted  ·  $with_hits with ast-grep hits"
  echo ""

  echo "ast-grep rules that fired:"
  local rule_counts
  rule_counts=$(jq -r '.sg_rules[]?' "$f" 2>/dev/null | sort | uniq -c | sort -rn)
  if [[ -z "$rule_counts" ]]; then
    echo "  (none — rules haven't matched anything yet)"
  else
    echo "$rule_counts" | head -10 | while read -r c r; do
      printf "  %4s  %s\n" "$c" "$r"
    done
  fi
  echo ""

  echo "Last 5:"
  tail -5 "$f" | jq -r '
    [(.ts[0:16] // "?"),
     ((.file // "?") | split("/") | last),
     (if .changed then "reformatted" else "idempotent" end),
     "sg_hits=\(.sg_hits // 0)"] | join("  ")
  ' 2>/dev/null
}

show_tail() {
  local name="$1"
  local f
  case "$name" in
    oops)    f="$log_dir/oops.jsonl" ;;
    wiretap) f="$log_dir/wiretap.jsonl" ;;
    rustfmt) f="$log_dir/rustfmt.jsonl" ;;
    harvest) f="$log_dir/clippy-harvest.jsonl" ;;
    *)       echo "Unknown log: $name. Use: oops, wiretap, rustfmt, harvest"; return ;;
  esac
  [[ -f "$f" ]] || { echo "No data in $name."; return; }
  echo "=== last 10: $name ==="
  tail -10 "$f" | jq . 2>/dev/null
}

# Is this ref a payload-shaped field name (vs. e.g. a shell variable or
# a random dotted token)? Conservative whitelist of prefixes and known keys.
_cnc_is_payload_ref() {
  case "$1" in
    tool_*|hook_*|agent_*|session_*|task_*|transcript_*|trigger_*|parent_*|notification_*) return 0 ;;
    ts|cwd|error|message|source|file_path|prompt|model|reason|load_reason|memory_type|is_interrupt|permission_mode|stop_hook_active|last_assistant_message|cc_version|test_source) return 0 ;;
    *) return 1 ;;
  esac
}

show_drift() {
  local f="$log_dir/wiretap.jsonl"
  [[ -f "$f" ]] || { echo "No wiretap data."; return; }

  local hooks_dir hooks_json
  hooks_dir="$(dirname "$0")"
  hooks_json="$hooks_dir/hooks.json"
  [[ -f "$hooks_json" ]] || { echo "No hooks.json at $hooks_json"; return; }

  echo "=== cnc: hook schema drift ==="
  echo ""

  # Observation window breakdown by cc_version
  local total
  total=$(wc -l < "$f" | tr -d ' ')
  echo "Observation window: $total wiretap records"
  jq -R -r 'fromjson? | .cc_version // "legacy"' "$f" 2>/dev/null | sort | uniq -c | sort -rn | while read -r c v; do
    printf "  %6s  %s\n" "$c" "$v"
  done
  echo ""

  # Build a one-pass observation index: each line is "event<TAB>tool<TAB>key".
  # A key is observed for an (event, tool) combo if a line matches.
  local obs_index
  obs_index=$(jq -R -r '
    fromjson? |
    .hook_event_name as $event |
    (.tool_name // "_") as $tool |
    keys[] | "\($event)\t\($tool)\t\(.)"
  ' "$f" 2>/dev/null | sort -u)

  # Build hook → (event, matcher) mapping from hooks.json
  local hook_map
  hook_map=$(jq -r '
    .hooks | to_entries[] | .key as $event |
    .value[] | (.matcher // "") as $matcher |
    .hooks[] | .command |
    capture("hooks/(?<name>[a-z-]+)\\.sh") | .name | "\(.)\t\($event)\t\($matcher)"
  ' "$hooks_json" 2>/dev/null | sort -u)

  echo "Hook field refs vs. wiretap observations:"
  echo ""

  local drift_count=0 checked_count=0
  while IFS=$'\t' read -r hook event matcher; do
    [[ -n "$hook" ]] || continue
    local hook_file="$hooks_dir/$hook.sh"
    [[ -f "$hook_file" ]] || continue

    # Extract top-level payload-field refs from the hook source.
    # Match any dotted identifier chain, reduce to the first segment,
    # then filter through the payload-ref whitelist. Strip full-line
    # comments first so stale references in # comments don't false-flag.
    local payload_refs=""
    local raw_refs
    raw_refs=$(sed 's/^[[:space:]]*#.*//' "$hook_file" 2>/dev/null |
               grep -oE '\.[a-z_][a-z_0-9]*(\.[a-z_][a-z_0-9]*)*' |
               awk -F. 'NF >= 2 {print $2}' | sort -u)
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      if _cnc_is_payload_ref "$ref"; then
        payload_refs="$payload_refs $ref"
      fi
    done <<< "$raw_refs"

    [[ -z "$payload_refs" ]] && continue

    # Header line for this hook/event/matcher combo
    local label="$event"
    [[ -n "$matcher" ]] && label="$event:$matcher"
    printf "  %-30s %s\n" "$hook.sh" "$label"
    checked_count=$((checked_count + 1))

    # For each ref, check the observation index for a row matching
    # ^event<TAB>(matcher)<TAB>ref$. Empty matcher → match any tool.
    for ref in $payload_refs; do
      local pattern
      if [[ -n "$matcher" ]]; then
        pattern="^${event}	(${matcher})	${ref}$"
      else
        pattern="^${event}	[^	]+	${ref}$"
      fi
      if echo "$obs_index" | grep -qE "$pattern"; then
        printf "    .%-26s ✓\n" "$ref"
      else
        printf "    .%-26s ✗ DRIFT — never observed in this event\n" "$ref"
        drift_count=$((drift_count + 1))
      fi
    done
    echo ""
  done <<< "$hook_map"

  if [[ "$drift_count" -eq 0 ]]; then
    echo "No drift detected across $checked_count hook/event combination(s)."
  else
    echo "Summary: $drift_count drifted field reference(s) across $checked_count hook/event combination(s)."
  fi
}

# Parse args
case "$args" in
  "")
    show_summary
    ;;
  oops)
    show_oops
    ;;
  wiretap)
    show_wiretap
    ;;
  rustfmt)
    show_rustfmt
    ;;
  harvest)
    show_harvest
    ;;
  drift)
    show_drift
    ;;
  *--tail*)
    name=$(echo "$args" | sed 's/--tail//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n "$name" ]] || name="oops"
    show_tail "$name"
    ;;
  *)
    echo "Usage: /cnc-logs [oops|wiretap|rustfmt|harvest|drift] [--tail]"
    ;;
esac
