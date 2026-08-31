---
description: Print the exact commands to update this plugin to its latest published version. Zero args, no execution — the assistant cannot invoke /plugin or /reload-plugins itself.
---

# /session-continuity:update

You are responding to the `/session-continuity:update` slash command.

**Your job: print the instructions below verbatim. Do nothing else.**

No Bash calls, no version check, no file reads. `/plugin` and
`/reload-plugins` are host-level slash commands — only the human can type
them; there is no tool that lets you invoke them on their behalf. This
plugin is distributed from the `talgolan` marketplace (repo
`talgolan/claude-plugins`), not from this plugin's own source repo —
match the README's "Updating" section, not the plugin's own repo name.

Print exactly this:

```
/plugin marketplace update talgolan
/reload-plugins
```

1. `marketplace update talgolan` — refetches the `talgolan` marketplace catalog from GitHub so the latest release of every plugin in it, including this one, is visible. No-op if already current.
2. `/reload-plugins` — activates the new version in this session without a restart.

**Never** run these commands yourself, even if a Bash-equivalent exists (e.g. hand-editing the plugin cache directory) — that bypasses the CLI's own state tracking and can desync it from what `/plugin list` reports.
