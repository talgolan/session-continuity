# Anthropic plugin marketplace submission

## What does it do / why would I install it?

Claude Code sessions start cold — Claude doesn't remember yesterday's debugging, last week's refactor, or the three-hour bug you eventually cornered. Most fixes reach for clever infrastructure (vector databases, MCP memory servers, vendor-specific notes stores) that hides the knowledge outside the repo, away from human eyes.

session-continuity takes a different route: plain Markdown files, committed to git, alongside the code they describe, plus GitHub Issues labeled `backlog` for the work queue. `.session-continuity/SESSION_PRIMER.md` is a thin hard-template (Boot order / Mid-flight / Confirm / Peers) refreshed alongside substantive commits — no embedded `git log` dump; drift is `primer-freshness.sh`. `.session-continuity/PROJECT_CONTEXT.md` holds stable repo context. `.session-continuity/ROADMAP.md` holds strategic direction. `.session-continuity/LEARNINGS.md` holds append-only wisdom — numbered entries for bugs that took 15+ minutes to diagnose. Boot also expects local engrim and a committed `graphify-out/graph.json` as required peers (neither leaves the machine via this plugin).

Nine slash commands keep the habit cheap (five of them — `backlog`, `learnings`, `help`, `update`, `doctor` — zero-turn via a prompt-intercept hook in the common case). Notable: `/session-continuity:primer` initializes, splits, slim-migrates, refreshes, or checks; `/session-continuity:end-session` is freshness-gated; `/session-continuity:doctor` diagnoses shape, peers, and freshness. Hooks nudge or gate when the habit slips — SessionStart (peers + freshness), a non-blocking commit nudge, LEARNINGS retrieval before action, and seven commit-time content gates that trigger on the staged delta and satisfy against the whole staged document (each with an explicit skip-with-reason escape hatch).

Install this when you work on the same project across many sessions and want Claude to pick up context in seconds instead of rebuilding it each time.

---

## Who's the target user?

Developers using Claude Code on projects they'll come back to across many sessions — anything from a solo side project to a long-running production codebase. Particularly useful when sessions span days or weeks, when multiple Claude instances share a repo (subagents, parallel worktrees, team members), or when a project has accumulated enough non-obvious bugs that "I forgot why we did it that way" becomes a recurring cost. Not a fit for one-shot scripts, throwaway prototypes, or users who prefer automatic memory capture over deliberate commits.

---

## Any telemetry / external calls?

See [PRIVACY.md](../../PRIVACY.md). Short version: weekly unauthenticated GitHub Releases GET (disable with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`); authenticated `gh` for the backlog when origin is github.com. Engrim and graphify stay local. No analytics.

---

## Pre-filled from `.claude-plugin/plugin.json`

For reference, the form likely pulls these directly from the manifest:

- **Name:** `session-continuity`
- **Repository:** `https://github.com/talgolan/session-continuity`
- **Description:** (copy from current `.claude-plugin/plugin.json` — four docs + GitHub Issues backlog)
- **Author:** Tal Golan
- **License:** MIT
- **Homepage:** `https://github.com/talgolan/session-continuity`
- **Keywords:** memory, session, handoff, continuity, documentation, onboarding, post-mortem
- **Version at submission:** re-check against `.claude-plugin/plugin.json` at actual submission time (was last synced in prose 2026-09-10; plugin is at 0.37.0 as of that sync refresh)
