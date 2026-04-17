#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "context-warn" || exit 0

# UserPromptSubmit hook: warn once per session when the context window crosses
# a wrap-up threshold. Hooks don't get token data in their payload, so we rely
# on ~/.claude/statusline.sh to drop fresh context state at the per-session
# bridge path below on every statusline tick (after each assistant message).
#
# Threshold picks:
#   window >= 500k → 25%  (1M "extended" contexts: wrap early, they bloat fast)
#   otherwise     → 40%  (200k default: wrap at the classic autocompact range)

input=$(cat)
session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)
[[ -n "$session_id" ]] || exit 0

state="/tmp/cnc-context-${session_id}.json"
[[ -f "$state" ]] || exit 0

marker="/tmp/cnc-wrap-warned-${session_id}"
[[ -f "$marker" ]] && exit 0

pct=$(jq -r '.pct // 0' "$state" 2>/dev/null || echo 0)
size=$(jq -r '.size // 0' "$state" 2>/dev/null || echo 0)
exceeds=$(jq -r '.exceeds // false' "$state" 2>/dev/null || echo false)
[[ "$pct" =~ ^[0-9]+$ ]] || exit 0
[[ "$size" =~ ^[0-9]+$ ]] || exit 0

# Tier 1 (earlier, 1M sessions only): model has crossed into extended-context
# territory. Not a wrap-up signal — a "work differently now" signal. Separate
# marker so it doesn't cross-mute with the hard threshold below.
tier1_marker="/tmp/cnc-extended-warned-${session_id}"
if (( size >= 500000 )) && [[ "$exceeds" == "true" ]] && [[ ! -f "$tier1_marker" ]]; then
  touch "$tier1_marker"
  cat <<EOF
[cnc context guard] Session crossed 200k tokens — extended-context territory on a ${size}-token window. Attention stretches past this point. Prefer subagents for any research ≥3 queries, write reference material to files instead of inline, and use TaskCreate to track state rather than restating it each turn.
EOF
fi

# Tier 2 (wrap-up): percent-of-window threshold. 25% on 1M, 40% elsewhere.
if (( size >= 500000 )); then
  threshold=25
else
  threshold=40
fi

if (( pct >= threshold )); then
  touch "$marker"
  cat <<EOF
[cnc context guard] Context window is at ${pct}% of a ${size}-token session (threshold ${threshold}%). Start wrapping up: finalize the current task, draft a handoff with curating-context, and suggest a fresh session once the handoff lands. This warning fires once per session.
EOF
fi

exit 0
