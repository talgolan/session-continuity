---
description: Explain what this plugin does, why, and what each `.session-continuity/` file is for. Zero args, read-only, no state mutation.
---

# /session-continuity:help

You are responding to the `/session-continuity:help` slash command.

**Your job: run the command below and print its output verbatim — no
reformatting, no summarizing, no added commentary.** Read-only — never
edits, stages, or commits anything.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/render.sh" help
```

`render.sh help` derives the version, the fixed reference text, and the
`COMMANDS` listing (one line per `commands/*.md` file's own frontmatter
`description:`) itself — do not re-derive any of that from `SKILL.md` or
hand-copy command descriptions into this file, and do not invent a
description for a command file that has none.
