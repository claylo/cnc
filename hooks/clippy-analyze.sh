#!/usr/bin/env bash
set -euo pipefail

# Analyze clippy harvest data to identify ast-grep candidates.
# Lints that are purely syntactic (no type info needed) are flagged.

log_file="${HOME}/.local/share/cnc/clippy-harvest.jsonl"

if [[ ! -f "$log_file" ]]; then
  echo "No harvest data yet. Run clippy-harvest.sh against some projects first." >&2
  exit 1
fi

# Known syntactic-only lints expressible as ast-grep patterns.
# These need NO type info — just code structure.
syntactic_lints=(
  "clippy::len_zero"                    # .len() == 0 → .is_empty()
  "clippy::manual_is_ascii_check"       # hand-rolled ASCII checks
  "clippy::bool_comparison"             # x == true → x
  "clippy::needless_return"             # explicit return at end of fn
  "clippy::redundant_closure"           # |x| foo(x) → foo
  "clippy::single_match"               # match with one arm → if let
  "clippy::collapsible_if"             # nested if → combined condition
  "clippy::collapsible_else_if"        # } else { if → } else if
  "clippy::manual_map"                 # match Some/None → .map()
  "clippy::manual_unwrap_or"           # match Some/None → .unwrap_or()
  "clippy::needless_borrow"            # &String where &str works (partial)
  "clippy::clone_on_copy"              # .clone() on Copy types (partial)
  "clippy::option_map_unwrap_or"       # .map().unwrap_or() → .map_or()
  "clippy::expect_fun_call"            # .expect(&format!()) → .expect()
  "clippy::string_lit_as_bytes"        # "foo".as_bytes() → b"foo"
  "clippy::manual_range_contains"      # x >= lo && x < hi → (lo..hi).contains(&x)
  "clippy::match_bool"                 # match true/false → if/else
  "clippy::needless_pass_by_value"     # (partial — pattern only)
  "clippy::unnecessary_unwrap"         # check is_some() then unwrap()
  "clippy::single_component_path_imports" # use std; style
  "clippy::double_parens"              # ((expr))
  "clippy::needless_continue"          # continue at end of loop
  "clippy::manual_filter_map"          # .filter().map() → .filter_map()
  "clippy::manual_find_map"            # .find().map() → .find_map()
  "clippy::iter_nth_zero"              # .iter().nth(0) → .iter().next()
  "clippy::match_like_matches_macro"   # match → matches!()
)

echo "=== Clippy Harvest Analysis ==="
echo ""
echo "Total entries: $(wc -l < "$log_file" | tr -d ' ')"
echo ""

echo "--- All lints by frequency ---"
jq -r '.lint' "$log_file" | sort | uniq -c | sort -rn | head -30
echo ""

echo "--- AST-GREP CANDIDATES (syntactic, no type info needed) ---"
for lint in "${syntactic_lints[@]}"; do
  count=$(jq -r ".lint" "$log_file" | grep -c "^${lint}$" 2>/dev/null || echo 0)
  if [[ "$count" -gt 0 ]]; then
    printf "  %4s  %s\n" "$count" "$lint"
  fi
done
echo ""

echo "--- NEEDS TYPE INFO (clippy-only, skip for ast-grep) ---"
# Everything in the harvest that's NOT in the syntactic list
syntactic_pattern=$(printf "%s\n" "${syntactic_lints[@]}" | paste -sd'|' -)
jq -r '.lint' "$log_file" | sort | uniq -c | sort -rn | while read -r count lint; do
  if ! echo "$lint" | grep -qE "^(${syntactic_pattern})$"; then
    printf "  %4s  %s\n" "$count" "$lint"
  fi
done | head -20
