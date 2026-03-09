#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "rustfmt-on-save" || exit 0

# PostToolUse hook: runs rustfmt on .rs files after Write/Edit

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[[ "$file_path" == *.rs ]] || exit 0
[[ -f "$file_path" ]] || exit 0

if command -v rustfmt &>/dev/null; then
  rustfmt "$file_path" 2>&1 || true
fi

# ast-grep lint pass (clippy-lite, no compilation)
sg_config="$(dirname "$0")/../sgconfig.yml"
if command -v sg &>/dev/null && [[ -f "$sg_config" ]]; then
  sg scan --config "$sg_config" "$file_path" 2>/dev/null || true
fi
