# cnc — Clay's Claude Code Guardrails

These are the hooks I use to keep Claude Code sessions from going off the rails. They enforce the small stuff I got tired of correcting manually.

**This is my workflow. YMMV.** I'm publishing it because the patterns might be useful, not because I think everyone should adopt them. Take what works, ignore the rest.

## Hooks

### Handoff Filename Guard
**Event:** `PreToolUse` on `Write|Edit`

Sub-agents love to hand-wave timestamps on handoff documents. They'll round to `:00`, use six-digit timestamps, or just make something up. This hook intercepts writes and edits to `.handoffs/` and enforces `YYYY-MM-DD-HHMM-description.md` naming with the **actual current time** — not whatever the agent hallucinated.

If the timestamp is wrong, the operation is blocked and the agent gets the correct filename back. If it's right, it passes through.

For Edit operations, there's a **30-minute mtime window**: editing a handoff older than 30 minutes is always allowed (that's legitimate maintenance on historical documents). Only fresh handoffs get the naming enforcement — catching agents that create a file and immediately try to edit it under the wrong name.

### Handoff File Auto-Allow
**Event:** `PreToolUse` on `Read|Write|Edit`

Auto-allows reads, writes, and edits to `.handoffs/` so the agent doesn't need to ask permission for every handoff file operation.

### For the Record
**Event:** `PreToolUse` on `Read|Write|Edit`

Plugins like superpowers write internal documents to `docs/` subdirectories. I use `docs/` only for user-facing docs, so internal project records go under `record/`:

```
docs/        # user-facing documentation
record/      # internal project record
├── adrs/
├── decisions/
├── plans/
├── reviews/
├── specs/
├── diagrams/
└── superpowers/
```

Behavior depends on the operation and whether the file exists:

- **Write** — always blocked with the corrected `record/` path. New files go in the right place.
- **Read/Edit on a missing file** — blocked with the corrected `record/` path. The file is probably already there.
- **Read/Edit on an existing file** — allowed, but the agent is told this is a legacy location and asked to suggest moving the files to `record/`. This handles the case where cnc is installed after superpowers has already created files in `docs/`.

Operations on other `docs/` paths (e.g. `docs/api-reference.md`) pass through untouched.

### Session Start Reminders
**Event:** `SessionStart`

Conditionally reminds the agent about available context sources — `.handoffs/` and `MEMORY.md` files — so it checks before asking questions. Warns when auto memory files approach the 200-line truncation limit (fires at 170). Checks `$CLAUDE_PLUGIN_DATA/*.jsonl` log files and flags any over 10MB.

Also resolves the current Claude Code version and caches it to `$CLAUDE_PLUGIN_DATA/cc_version`. Wiretap stamps every captured record with that version so drift analysis has a reliable axis. `CLAUDE_CODE_EXECPATH` gets stripped from hook subprocesses by `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`, so this cache is how wiretap knows which version produced which record.

Finally, runs the wiretap drift detector (see `/cnc-logs drift`) to catch silent breakage from Claude Code hook payload schema changes — the kind of thing that caused `clippy-harvest.sh` to fail quietly for a month after `.tool_output` became `.tool_response`.

### MCP Probe
**Event:** `SessionStart` (async)

Calls `claude mcp list` in the background at session start and caches connected/disconnected status per MCP server to `/tmp/cnc-mcp-$SESSION_ID.json`. Other hooks read this cache to decide whether to engage with MCP-dependent tooling, without paying the ~30s health-check cost themselves.

Runs with `"async": true, "timeout": 60` so SessionStart is never blocked. By the time later hooks need the cache (the earliest one is `SessionEnd`), the probe has long since completed.

Used by: `vent.sh` (only prompts to journal if `private-journal` is actually connected).

### Context Guard
**Event:** `UserPromptSubmit`

Warns the agent when context is filling up, so work wraps cleanly before model performance starts degrading in the late-context tail. Two tiers, each fires once per session via marker files in `/tmp`:

- **Extended-context entry.** On sessions with ≥500k-token context windows, when `exceeds_200k_tokens` goes true, injects a prescriptive nudge: prefer subagents for multi-query research, write reference material to files instead of inline, use `TaskCreate` to track state rather than restating it each turn.
- **Wrap-up threshold.** When `context_window.used_percentage` crosses **25%** on ≥500k windows or **40%** on smaller ones, tells the agent to finalize the current task, draft a handoff, and suggest a fresh session.

Hooks don't receive token data in their payloads. Context Guard reads `/tmp/cnc-context-$SESSION_ID.json`, which the statusline must write on each tick — see **Statusline bridge** under Installation.

### Rust Format on Save
**Event:** `PostToolUse` on `Write|Edit`

Runs `rustfmt` on `.rs` files after any write or edit. Fails silently if rustfmt isn't installed — so this won't break anything in non-Rust projects.

### Clippy Harvest
**Event:** `PostToolUse` on `Bash`

Watches for `cargo` commands and parses clippy lint warnings from their actual output — no parallel compile, no extra CPU. Appends structured lint data to `$CLAUDE_PLUGIN_DATA/clippy-harvest.jsonl`. Matches any `cargo` command (not just `cargo clippy`), so it captures lints from whatever flags were actually used (`--all-targets`, `--all-features`, etc.).

The companion script `hooks/clippy-analyze.sh` reads the harvest data and identifies which lints are purely syntactic (good ast-grep candidates) vs. which need type info (clippy-only).

### Oops
**Event:** `PostToolUseFailure`

Logs the full payload of every tool failure to `$CLAUDE_PLUGIN_DATA/oops.jsonl`. Useful for spotting patterns in what goes wrong across sessions — recurring permission denials, flaky commands, etc.

### Wiretap
**Event:** all 27 Claude Code hook events

Captures each event's full payload to `$CLAUDE_PLUGIN_DATA/wiretap.jsonl`, stamped with `ts` and `cc_version`. This is the observability surface for what Claude Code actually sends hooks — payload shapes, which fields are populated, undocumented events, schema changes across Claude Code versions.

**Which events log is config-controlled, not hooks.json-controlled.** `hooks.json` wires wiretap to every event; a per-event toggle decides what actually writes to the log. Default is all on. Turn off noisy events via `/cncflip wiretap:<Event>` or by editing config directly:

```json
{ "cnc": { "wiretap": { "events": { "FileChanged": false } } } }
```

Project config overrides global defaults, same cascade as hook toggles.

The log grows — a full day of active use can add 50–100 MB. Session-start flags any wiretap.jsonl over 10 MB; archive or truncate when it nags you. Append-safety: uses `flock -x -w 5` so concurrent Claude sessions don't corrupt each other's writes.

### Vent
**Event:** `SessionEnd`

Reminds the agent to journal anything that should change how future sessions work. Only fires when the `private-journal` MCP server is actually connected in this session — not when the `.private-journal/` directory merely exists. Runtime connectivity comes from the cache written by `mcp-probe.sh`; if the probe is disabled, failed, or hadn't finished before `SessionEnd` (unusual for real sessions), the hook stays silent. Safe default.

## AST-grep Rules

10 syntactic Rust lint rules under `rules/rust/`, configured via `sgconfig.yml`. These catch patterns that don't need type information — purely structural matches that run in ~10ms/file:

| Rule | Pattern |
|------|---------|
| `bool-comparison` | `x == true` → `x` |
| `bool-comparison-neg` | `x == false` → `!x` |
| `len-zero` | `.len() == 0` → `.is_empty()` |
| `len-not-zero` | `.len() != 0` → `!.is_empty()` |
| `iter-nth-zero` | `.iter().nth(0)` → `.iter().next()` |
| `string-lit-as-bytes` | `"foo".as_bytes()` → `b"foo"` |
| `double-parens` | `((expr))` → `(expr)` |
| `manual-is-nan` | `x != x` → `x.is_nan()` |
| `manual-is-infinite` | `x == f64::INFINITY` → `x.is_infinite()` |
| `use-types-before-values` | `use foo::{bar, Baz}` → `use foo::{Baz, bar}` |

The `use-types-before-values` rule reorders grouped imports so types (PascalCase) precede values (snake_case), preserving relative order within each group. It safely skips imports containing `self`, `as` renames, or nested paths — only fires on simple identifier lists where both groups are present and out of order. This catches something rustfmt skips.

These run via the `rustfmt-on-save` hook cycle — fast enough to check on every save. Full clippy stays in CI.

## Commands

### `/cncflip [--global] [hook-name | wiretap:event-name]`
Toggle hooks on/off. No argument lists current state. All hooks default to on — only an explicit flip disables them.

**Hook toggles:**
- `/cncflip` — list effective state (project > global > default)
- `/cncflip vent` — flip vent at project level
- `/cncflip --global wiretap` — flip the wiretap hook entirely, globally
- `/cncflip --global` — list global defaults only

**Wiretap per-event toggles:**
- `/cncflip wiretap:` — list all 27 events and their state
- `/cncflip wiretap:FileChanged` — stop logging `FileChanged` events (project)
- `/cncflip --global wiretap:PreToolUse` — same, global default
- `/cncflip --global wiretap:` — list global wiretap event defaults only

Project settings override global defaults. Global defaults apply across all projects.

### `/cnc-logs [oops|wiretap|rustfmt|harvest|drift] [--tail]`
Quick dashboard for cnc's log files (`$CLAUDE_PLUGIN_DATA/*.jsonl` — typically `~/.claude/plugins/data/cnc-*/`).

- `/cnc-logs` — summary: entry counts, sizes, top failures, event breakdown, rustfmt and lint totals
- `/cnc-logs oops` — tool failure drill-down: by tool, common errors, last 5
- `/cnc-logs wiretap` — hook event breakdown: by event type, last 5
- `/cnc-logs rustfmt` — rustfmt-on-save runs, reformat count, ast-grep rules that fired
- `/cnc-logs harvest` — clippy lint analysis (runs `clippy-analyze.sh`)
- `/cnc-logs drift` — schema drift detector: flags hook scripts that read payload fields never observed in wiretap for their matching event
- `/cnc-logs oops --tail` — last 10 raw entries as JSON

## Testing

```
just test
```

Uses [ShellSpec](https://shellspec.info/). Specs live in `spec/`.

## Installation

This is a Claude Code plugin. Drop it into your plugins directory or symlink it — the `hooks/hooks.json` file handles registration.

### Statusline bridge (optional — enables Context Guard)

Context Guard depends on the current context window percentage, which hooks don't receive in their payload. Your statusline **does** get it. Add this to the bottom of `~/.claude/statusline.sh` so each statusline tick writes fresh state to a bridge file the hook can read:

```bash
# Bridge fresh context state to the cnc Context Guard hook. Keyed by session
# so concurrent Claude sessions don't clobber each other.
bridge="/tmp/cnc-context-$SESSION_ID.json"
jq -c '{
  pct:        (.context_window.used_percentage // 0 | floor),
  size:       (.context_window.context_window_size // 0),
  exceeds:    (.exceeds_200k_tokens // false),
  session_id: .session_id,
  model:      .model.id,
  cc_version: .version
}' <<<"$input" > "$bridge.tmp" 2>/dev/null && mv -f "$bridge.tmp" "$bridge" || true
```

The snippet assumes your statusline already captures the JSON input to `$input` and parses `$SESSION_ID` from it — adjust variable names to match your script. Without the bridge file, Context Guard stays silent rather than firing on stale data.
