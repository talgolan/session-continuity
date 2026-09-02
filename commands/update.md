---
description: Print the exact commands to update this plugin to its latest published version. Zero args, no execution — the assistant cannot invoke /plugin or /reload-plugins itself.
---

# /session-continuity:update

You are responding to the `/session-continuity:update` slash command.

**Your job: run the command below and print its output verbatim — no
reformatting, no summarizing, no added commentary.** Read-only — never
edits, stages, or commits anything.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/render.sh" update
```

**Never** run the `/plugin`/`/reload-plugins` commands the output
describes yourself, even if a Bash-equivalent exists (e.g. hand-editing
the plugin cache directory) — that bypasses the CLI's own state tracking
and can desync it from what `/plugin list` reports. `/plugin` and
`/reload-plugins` are host-level slash commands; only the human can type
them.
