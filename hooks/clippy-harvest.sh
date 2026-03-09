#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "clippy-harvest" || exit 0

# PreToolUse hook on Bash: when the agent runs cargo clippy,
# silently tee the structured output to a log for later analysis.
# Does NOT interfere with the actual clippy run — just observes.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only act on cargo clippy invocations
[[ "$command" == *"cargo clippy"* ]] || exit 0

log_dir="${HOME}/.local/share/cnc"
log_file="${log_dir}/clippy-harvest.jsonl"
mkdir -p "$log_dir"

# Extract the working directory or manifest path from the command
# Run clippy with JSON output in the background, append to log
# We let the original command proceed normally — this just observes
project_dir="."
if [[ "$command" =~ --manifest-path[[:space:]]+([^[:space:]]+) ]]; then
  project_dir=$(dirname "${BASH_REMATCH[1]}")
fi

# Fire-and-forget: run a parallel clippy with JSON output to harvest
(
  cargo clippy --manifest-path "${project_dir}/Cargo.toml" \
    --message-format=json --quiet 2>/dev/null \
  | jq -c '
    select(.reason == "compiler-message")
    | .message
    | select(.code.code != null and (.code.code | startswith("clippy::")))
    | {
        lint: .code.code,
        level: .level,
        file: (.spans[0].file_name // "unknown"),
        line: (.spans[0].line_start // 0),
        message: .message,
        ts: now | todate
      }
  ' >> "$log_file" 2>/dev/null
) &

# Don't block the actual clippy run
exit 0
