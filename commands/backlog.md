---
description: List .session-continuity/BACKLOG.md's open items. Zero args, read-only.
---

# /session-continuity:backlog

You are responding to the `/session-continuity:backlog` slash command.

**Your job: run the command below and print its output verbatim — no
reformatting, no summarizing, no added commentary.** Read-only — never
edits, stages, or commits anything.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/render.sh" backlog "$(pwd)"
```

`render.sh` already handles every failure mode (no `.session-continuity/`
directory, a missing `BACKLOG.md`, an empty backlog, a broken plugin
install) by printing its own explanatory line — do not add your own
"if the output looks wrong, do X" branch on top of it.
