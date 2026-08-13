# Anthropic plugin marketplace submission

## What does it do / why would I install it?

Claude Code sessions start cold — Claude doesn't remember yesterday's debugging, last week's refactor, or the three-hour bug you eventually cornered. Most fixes reach for clever infrastructure (vector databases, MCP memory servers, vendor-specific notes stores) that hides the knowledge outside the repo, away from human eyes.

session-continuity takes a different route: plain Markdown files, committed to git, alongside the code they describe. `.session-continuity/SESSION_PRIMER.md` holds current state (the last five commits, what's outstanding, what's in flight) and refreshes with every substantive change. `.session-continuity/PROJECT_CONTEXT.md` holds stable repo context (layout, conventions, module table) that changes only when the project's shape itself changes. `.session-continuity/LEARNINGS.md` holds append-only wisdom — numbered entries for bugs that took 15+ minutes to diagnose, kept stable so cross-references don't rot.

Four slash commands keep the habit cheap: `/session-continuity:primer` initializes, splits, refreshes, or checks the primer; `/session-continuity:learning` appends a LEARNINGS entry interactively; `/session-continuity:end-session` runs a close-out ritual that refreshes the primer, surfaces LEARNINGS candidates from the session's context, and reports a checklist of staged / unstaged / untracked / unpushed state; `/session-continuity:spike-check` forces a spike to be designed against the real load-bearing path before it's built. A handful of hooks nudge or gate when the habit slips — a `SessionStart` hook reminds Claude to read the primer on new sessions, a non-blocking `PreToolUse` hook flags `git commit` calls that land without a primer refresh staged, and several blocking `PreToolUse` gates enforce evidence/invariant discipline in specs, plans, and LEARNINGS entries (each with an explicit skip-with-reason escape hatch).

Install this when you work on the same project across many sessions and want Claude to pick up context in seconds instead of rebuilding it each time.

---

## Who's the target user?

Developers using Claude Code on projects they'll come back to across many sessions — anything from a solo side project to a long-running production codebase. Particularly useful when sessions span days or weeks, when multiple Claude instances share a repo (subagents, parallel worktrees, team members), or when a project has accumulated enough non-obvious bugs that "I forgot why we did it that way" becomes a recurring cost. Not a fit for one-shot scripts, throwaway prototypes, or users who prefer automatic memory capture over deliberate commits.

---

## Any telemetry / external calls?

One external call: a weekly unauthenticated GET to the GitHub Releases API to check for new versions and nudge the user when an update is available. The URL is derived from the `repository` field in `.claude-plugin/plugin.json` (falling back to `https://api.github.com/repos/talgolan/session-continuity/releases/latest` if parsing fails), so renaming the repo doesn't silently break the check. The request runs at most once per 7 days per machine (mtime-cached to `~/.cache/session-continuity/last-check`), has a 3-second timeout, fails silently on network errors, and can be disabled entirely by setting `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`. No analytics, no identifiers, no PII sent. All other functionality (primer files, LEARNINGS, slash commands, hooks) runs entirely locally against the user's own repo.

---

## Pre-filled from `.claude-plugin/plugin.json`

For reference, the form likely pulls these directly from the manifest:

- **Name:** `session-continuity`
- **Repository:** `https://github.com/talgolan/session-continuity`
- **Description:** `Cross-session memory for Claude Code projects via three in-repo docs: SESSION_PRIMER.md (current state), PROJECT_CONTEXT.md (stable repo context), and LEARNINGS.md (hard-won bugs).`
- **Author:** Tal Golan
- **License:** MIT
- **Homepage:** `https://github.com/talgolan/session-continuity`
- **Keywords:** memory, session, handoff, continuity, documentation, onboarding, post-mortem
- **Version at submission:** 0.14.0 (re-check against `.claude-plugin/plugin.json` at actual submission time — this field drifts with every release and was last synced 2026-08-13)
