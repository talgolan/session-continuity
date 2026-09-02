---
description: List .session-continuity/LEARNINGS.md's entries. Zero args, read-only.
---

# /session-continuity:learnings

You are responding to the `/session-continuity:learnings` slash command.

**Your job: run the command below and print its output verbatim — no
reformatting, no summarizing, no added commentary.** Read-only — never
edits, stages, or commits anything.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/render.sh" learnings "$(pwd)"
```

`render.sh` already handles every failure mode (no `.session-continuity/`
directory, a missing `LEARNINGS.md`, an empty learnings file, a broken
plugin install) by printing its own explanatory line — do not add your
own "if the output looks wrong, do X" branch on top of it.
