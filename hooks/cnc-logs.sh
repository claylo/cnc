#!/usr/bin/env bash
set -euo pipefail

# UserPromptSubmit hook: display cnc log analysis
#
# /cnc-logs                — summary dashboard
# /cnc-logs oops           — tool failure breakdown
# /cnc-logs wiretap        — hook event breakdown
# /cnc-logs harvest        — clippy lint analysis
# /cnc-logs <name> --tail  — last 10 raw entries

input=$(cat)
prompt=$(echo "$input" | jq -r '.user_prompt // empty')

# Only act on /cnc-logs commands (plain or plugin-namespaced /cnc:cnc-logs)
[[ "$prompt" == */cnc-logs* || "$prompt" == */cnc:cnc-logs* ]] || exit 0

args=$(echo "$prompt" | sed -E -n 's|.*/(cnc:)?cnc-logs[[:space:]]*||p' | xargs)

log_dir="${HOME}/.local/share/cnc"

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
    jq -r '.hook_event_name // "unknown"' "$log_dir/wiretap.jsonl" | sort | uniq -c | sort -rn | while read -r c t; do
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
  jq -r '.hook_event_name // "unknown"' "$f" | sort | uniq -c | sort -rn | while read -r c t; do
    printf "  %4s  %s\n" "$c" "$t"
  done
  echo ""

  echo "Last 5:"
  tail -5 "$f" | jq -r '
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
  *--tail*)
    name=$(echo "$args" | sed 's/--tail//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n "$name" ]] || name="oops"
    show_tail "$name"
    ;;
  *)
    echo "Usage: /cnc-logs [oops|wiretap|rustfmt|harvest] [--tail]"
    ;;
esac
