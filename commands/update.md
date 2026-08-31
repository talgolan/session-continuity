---
description: Print the exact commands to update this plugin to its latest published version. Zero args, no execution — the assistant cannot invoke /plugin or /reload-plugins itself.
---

# /session-continuity:update

You are responding to the `/session-continuity:update` slash command.

**Your job: print the instructions below verbatim. Do nothing else.**

No Bash calls, no version check, no file reads. `/plugin` and
`/reload-plugins` are host-level slash commands — only the human can type
them; there is no tool that lets you invoke them on their behalf, and
checking the installed-vs-latest version first would spend a Bash round
trip on a question the three commands below answer for free (the
marketplace-update step is a no-op if already current).

Print exactly this:

```
/plugin marketplace update talgolan/session-continuity
/plugin install session-continuity@talgolan/session-continuity
/reload-plugins
```

1. `marketplace update` — refetches the catalog from GitHub so the latest release is visible.
2. `install <plugin>@<marketplace>` — installs that latest version. The `@talgolan/session-continuity` suffix is required — a bare `install session-continuity` reads the stale cached catalog instead of the one just refreshed.
3. `/reload-plugins` — activates the new version in this session without a restart. Skip it if step 2's output already says "Plugin is now active."

**Never** run these commands yourself, even if a Bash-equivalent exists (e.g. hand-editing the plugin cache directory) — that bypasses the CLI's own state tracking and can desync it from what `/plugin list` reports.
