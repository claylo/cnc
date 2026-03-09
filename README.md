# cnc — Clay's Claude Code Guardrails

These are the hooks I use to keep Claude Code sessions from going off the rails. They enforce the small stuff I got tired of correcting manually.

**This is my workflow. YMMV.** I'm publishing it because the patterns might be useful, not because I think everyone should adopt them. Take what works, ignore the rest.

## Hooks

### Handoff Filename Guard
**Event:** `PreToolUse` on `Write`

Sub-agents love to hand-wave timestamps on handoff documents. They'll round to `:00`, use six-digit timestamps, or just make something up. This hook intercepts writes to `.handoffs/` and enforces `YYYY-MM-DD-HHMM-description.md` naming with the **actual current time** — not whatever the agent hallucinated.

If the timestamp is wrong, the write is blocked and the agent gets the correct filename back. If it's right, it passes through.

### Handoff File Auto-Allow
**Event:** `PreToolUse` on `Read|Write`

Auto-allows reads and writes to `.handoffs/` so the agent doesn't need to ask permission for every handoff file operation.

### For the Record
**Event:** `PreToolUse` on `Write`

Plugins like superpowers dump documents into `docs/` subdirectories. I don't want that — `docs/` is for users. Internal project records go under `record/`:

```
docs/        # user-facing documentation
record/      # internal project record
├── adrs/
├── decisions/
├── plans/
├── reviews/
├── specs/
└── diagrams/
```

This hook intercepts writes to `docs/{adrs,decisions,plans,reviews,specs,diagrams}/` and blocks them with the corrected `record/` path. Writes to other `docs/` paths pass through untouched.

### Session Start Reminders
**Event:** `SessionStart`

Conditionally reminds the agent about available context sources — `.handoffs/`, `MEMORY.md` files, `.private-journal`, `episodic-memory` — so it checks before asking questions. Also reminds agents **not to run test suites without asking first**. Warns when auto memory files approach the 200-line truncation limit (fires at 170). Checks `~/.local/share/cnc/*.jsonl` log files and flags any over 10MB.

### Rust Format on Save
**Event:** `PostToolUse` on `Write|Edit`

Runs `rustfmt` on `.rs` files after any write or edit. Fails silently if rustfmt isn't installed — so this won't break anything in non-Rust projects.

### Clippy Harvest
**Event:** `PreToolUse` on `Bash`

Watches for `cargo clippy` invocations. When one fires, it silently runs a parallel clippy with `--message-format=json` in the background and appends structured lint data to `~/.local/share/cnc/clippy-harvest.jsonl`. Zero overhead on the actual clippy run — just observes.

The companion script `hooks/clippy-analyze.sh` reads the harvest data and identifies which lints are purely syntactic (good ast-grep candidates) vs. which need type info (clippy-only).

### Oops
**Event:** `PostToolUseFailure`

Logs the full payload of every tool failure to `~/.local/share/cnc/oops.jsonl`. Useful for spotting patterns in what goes wrong across sessions — recurring permission denials, flaky commands, etc.

### Wiretap
**Event:** `Elicitation`, `ElicitationResult`, `InstructionsLoaded`, `Notification`

Logs payloads from undocumented/under-documented hook events to `~/.local/share/cnc/wiretap.jsonl`. These events aren't covered in official docs yet, so wiretap captures their schemas for later analysis.

### Vent
**Event:** `Stop`

When a session ends, reminds the agent to write honestly about how the session went to `.private-journal`. Not a status report — feelings. What was frustrating, what clicked, what they'd do differently. Only fires if `.private-journal` exists.

## AST-grep Rules

9 syntactic Rust lint rules under `rules/rust/`, configured via `sgconfig.yml`. These catch patterns that don't need type information — purely structural matches that run in ~10ms/file:

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

These run via the `rustfmt-on-save` hook cycle — fast enough to check on every save. Full clippy stays in CI.

## Commands

### `/cncflip [--global] [hook-name]`
Toggle hooks on/off. No argument lists current state. All hooks default to on — only an explicit flip disables them.

- `/cncflip` — list effective state (project > global > default)
- `/cncflip vent` — flip vent at project level
- `/cncflip --global wiretap` — flip wiretap globally (`~/.config/cnc/defaults.json`)
- `/cncflip --global` — list global defaults only

Project-level settings override global defaults. Global defaults apply across all projects.

## Testing

```
just test
```

Uses [ShellSpec](https://shellspec.info/). Specs live in `spec/`.

## Installation

This is a Claude Code plugin. Drop it into your plugins directory or symlink it — the `hooks/hooks.json` file handles registration.
