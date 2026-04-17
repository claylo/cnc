#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/cnc-config.sh"
cnc_enabled "mcp-probe" || exit 0

# SessionStart async hook: probe which MCP servers are running in this
# session and cache the result for other hooks. `claude mcp list` actively
# health-checks every configured MCP server — ~30s with seven servers — so
# this MUST run with "async": true in hooks.json. Other hooks read the
# cache without spawning any probes of their own.

input=$(cat)
session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)
[[ -n "$session_id" ]] || exit 0

cache="/tmp/cnc-mcp-${session_id}.json"
tmp="${cache}.tmp"

# Parse `claude mcp list` output. Each line:
#   NAME: COMMAND_TEXT - ✓ Connected
#   NAME: COMMAND_TEXT - ✗ Failed to connect
# NAME may be "plugin:<plugin>:<server>" (plugin-provided) or bare
# (user-configured). Normalize to the last colon-separated segment so both
# forms resolve to the same key (mcp tool names use the trailing segment).
claude mcp list 2>/dev/null | awk '
  /✓ Connected|✗ Failed/ {
    idx = index($0, ": ")
    if (idx > 0) {
      full_name = substr($0, 1, idx-1)
      n = split(full_name, parts, ":")
      short = parts[n]
      connected = ($0 ~ /✓ Connected/) ? "true" : "false"
      printf "{\"name\":\"%s\",\"connected\":%s}\n", short, connected
    }
  }
' | jq -s 'map({(.name): .connected}) | add // {}' > "$tmp" 2>/dev/null

# Only promote the tmp file if we got at least one server; otherwise leave
# any pre-existing cache alone so transient `claude mcp list` failures
# don't wipe good state.
if [[ -s "$tmp" ]] && ! grep -q '^{}$' "$tmp"; then
  mv -f "$tmp" "$cache"
else
  rm -f "$tmp"
fi
