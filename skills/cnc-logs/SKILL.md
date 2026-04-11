---
name: cnc-logs
description: Show cnc log analysis dashboard for oops, wiretap, rustfmt, or clippy harvest data. Use when the user wants to inspect cnc hook activity or debug tool failures.
disable-model-invocation: true
argument-hint: "[oops|wiretap|rustfmt|harvest] [--tail]"
allowed-tools: Bash
---

## Log analysis

```!
${CLAUDE_SKILL_DIR}/../../hooks/cnc-logs.sh $ARGUMENTS
```

Summarize the key findings above — highlight anything that looks like a pattern
(repeated failures, unusual events, actionable lint data). Don't reformat the
raw output, just call out what's interesting.
