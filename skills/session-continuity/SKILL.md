---
name: session-continuity
description: Establish and maintain cross-session memory for a project via two in-repo docs — docs/SESSION_PRIMER.md (current state, refreshed alongside substantive commits) and docs/LEARNINGS.md (append-only wisdom for bugs that took 15+ min). Use when starting work, before commits, or after hard-won bugs.
---

# Session Continuity

Two in-repo files act as a handoff between Claude sessions on the same project:

- **`docs/SESSION_PRIMER.md`** — current-state snapshot (latest commits, outstanding items, test counts, workflow conventions). **Refresh alongside substantive commits** (stage the update in the same commit as the real change). Always reflects "what's true right now."
- **`docs/LEARNINGS.md`** — accumulated wisdom (numbered entries, grouped by layer). Append-only log of bugs that were painful enough to not want to rediscover. **Update when a bug takes 15+ minutes to diagnose.**

The two files are complementary: primer is volatile current-state, LEARNINGS is durable wisdom. A fresh session reads the primer first to get oriented, then consults LEARNINGS when something surprising happens.

If installed as a plugin, three commands are available: `/session-continuity:primer` (init/refresh/check the primer), `/session-continuity:learning` (append a new LEARNINGS entry interactively), and `/session-continuity:end-session` (close-out ritual — refresh the primer, capture any new learnings from this session, and report a ✓/⚠️ checklist before you close the laptop). Hooks in `hooks/hooks.json` remind Claude to read the primer on session start and nudge when a `git commit` lands without a primer refresh staged.

## When to use this skill

Invoke when:

- Starting work on a project that does not yet have `docs/SESSION_PRIMER.md` and `docs/LEARNINGS.md` — initialize from the templates.
- About to commit code changes — refresh the primer's "Current state" and "Outstanding items" sections so the next session sees the truth.
- A bug has just been resolved after significant effort (15+ min, or required reading unfamiliar code, or surprised you) — add a LEARNINGS entry.
- The user says something like "help me preserve session memory," "how do I hand this off to the next session," "create a primer," or "add this to learnings."
- Picking up work on a project that already has these files — read them as the first step, before touching anything else.

## Quick start (new project)

1. Read the templates in `./templates/`:
   - [`templates/SESSION_PRIMER.md`](templates/SESSION_PRIMER.md)
   - [`templates/LEARNINGS.md`](templates/LEARNINGS.md)
2. Create `docs/` if it doesn't exist.
3. Copy both templates into the project's `docs/` directory.
4. Fill in the `{{PLACEHOLDERS}}` with project-specific content. Leave sections you don't have information for as "TBD" — don't invent.
5. Commit both files together with a message like `docs: initialize session continuity (primer + learnings)`.
6. Announce to the user: the primer needs refreshing alongside substantive commits (stage the refresh in the same commit as the real change — do not commit the primer by itself), and LEARNINGS needs an entry for every bug that took 15+ minutes to diagnose.

## Quick start (existing project with these files)

1. Read `docs/SESSION_PRIMER.md` end-to-end. It is designed for this exact moment.
2. Follow its "First things first" list.
3. Before doing ANY work, verify claimed state is still current (the primer can be stale — run its test commands, check `git log`, etc.).
4. When you commit, update the primer.

## The maintenance rules (read this before every commit)

### On every substantive commit — refresh SESSION_PRIMER.md in the same commit

**Substantive** means a real code or docs change — anything you would
commit even if the primer didn't exist. For every such commit, stage
the primer refresh alongside the real diff so they land together.

Sections most likely to be stale:

- **Current state / latest commits.** Regenerate the `git log --oneline -5` block to include the commit you are about to make.
- **Outstanding items.** Remove things you just finished. Add newly-flagged follow-ups from code review or user feedback.
- **Test expectations.** If you added, removed, or skipped tests, bump the count so it matches `<test command>` output.

Other sections (layout, packages, conventions) drift more slowly but are fair game if the repo shifted.

### Do NOT commit the primer by itself

A primer-only commit creates a self-referential chain: every primer
refresh becomes a commit that the primer itself needs to reflect,
inviting another primer-only commit, and so on. Treat the primer as
metadata that rides along with substantive commits. Exceptions — rare
but legitimate:

- A one-shot catch-up when the primer has drifted badly and no code
  change is imminent.
- Correcting factual errors (wrong test counts, wrong branch names)
  discovered during review.

Both should be marked clearly in the commit message as catch-up work.
If you find yourself making repeated primer-only commits, stop and
bundle the refresh with the next real change instead.

If you genuinely have nothing substantive to commit, that's fine —
but *check* the primer the next time you do commit, and include the
refresh in that same commit.

### On a hard-won bug — add to LEARNINGS.md

A bug qualifies when any of:

- Took more than 15 minutes to diagnose.
- Required reading code in an unfamiliar layer of the stack.
- Surprised you — the behavior did not match what the docs or the naming implied.
- Bit you twice (the second time is a sign the first didn't leave enough of a mark).

**Write entry as a recipe, not a journal.** Each entry should contain:

- **The trap.** What you tried that seemed reasonable but was wrong.
- **Symptom.** The observable behavior, including the misleading error messages.
- **Fix.** What actually works, with code or commands.
- **Diagnostic signal** *(optional but useful)*. How to recognize this bug next time — a log line, an exit code, a process pattern.

**Numbering convention.** New entries go at the **top** of the relevant section but take the **next available number** (N+1). Old entries keep their numbers. This keeps cross-entry back-references ("see #7 above") stable even as new entries arrive. The primer and other docs should cite learnings by number (`LEARNINGS.md §12`).

**Grouping by layer.** Standard sections: Runtime (one per runtime — Bun, Node, Python, etc.), Shell / scripts, Process management, Security, <project-specific layers like HTTP, DB, UI>, Git / repo layout, Anti-patterns we were tempted by. Adapt to the project; do not force structure where it doesn't fit.

## What goes where — a decision tree

| Observation | Where it goes |
|---|---|
| "The latest commit is X" | `SESSION_PRIMER.md` → Current state |
| "We should refactor Y" | `SESSION_PRIMER.md` → Outstanding items |
| "Bun replaces the CA trust store" | `LEARNINGS.md` → new numbered entry |
| "The CLI uses portless URLs" | `CLAUDE.md` (per-project config) |
| "User prefers Bun to Node" | `CLAUDE.md` (per-project) or user's global `~/.claude/CLAUDE.md` |
| "Last session tried approach X and rejected it" | `LEARNINGS.md` → Anti-patterns section |
| "API keys leaked in transcript on date Y" | `LEARNINGS.md` → Security section (names only, never values) |

**Do not put in these files:**

- Secrets. Ever. Even in "Fixed by changing `KEY=abc`" commentary — redact to `KEY=<redacted>`.
- Information that is trivially rederivable from the code (module layout, function signatures — the code itself is the source of truth).
- Narrative fluff ("We spent a long time on this and finally…"). Write recipes, not war stories.

## Customization guidance

Different projects have different shapes, but the core two-file pattern adapts well:

- **Test counts in the primer.** If you have one package, one line. If you have three packages (like SF_Tunnel: relay, tunnel, web), show three. If counts are unstable (integration tests that depend on external services), drop the exact count and document the green command instead.
- **"Workflow conventions" section.** Replace with whatever this project's disciplines are: commit message format, branch naming, code review process, required CI checks.
- **"Outstanding items" section.** Use your own taxonomy: "blocked", "deferred", "needs decision". Keep it actionable.
- **LEARNINGS section headings.** Replace "Bun", "SvelteKit", etc. with the actual layers of the project. Stack varies, structure is universal.

## For team-wide use

If multiple people are working on the same project and should all benefit from this:

1. Both files are **checked-in** artifacts, not gitignored. Commit them in the project repo under `docs/`.
2. In the project's `CLAUDE.md`, add a line like:
   > Before making changes, read `docs/SESSION_PRIMER.md`. Refresh it alongside substantive commits (in the same commit as the real change). For debug-worthy bugs, update `docs/LEARNINGS.md`.
3. Document the maintenance rules in the primer itself (last section). Templates include this.
4. Human teammates benefit too — LEARNINGS.md doubles as a living post-mortem log, and the primer is a great onboarding handoff.

## Red flags — when NOT to use

- **One-off scripts or throwaway repos.** Not worth the overhead.
- **Repos where the user explicitly prefers other memory mechanisms** (e.g., a heavily-used wiki, a confluence space). Don't duplicate.
- **Projects whose CLAUDE.md already does this** (some projects keep all session handoff in `CLAUDE.md`). Extend that approach instead of imposing a new structure.

## Complementary mechanisms

- **`CLAUDE.md`** covers "how to work in this repo" — durable, rarely changes. Primer covers "what's true right now" — changes per commit.
- **MemPalace / similar agent-memory systems** cover color that doesn't deserve a commit: user preferences, debugging narratives, session-level observations. Primer/LEARNINGS cover things the team should see.
- **Stop / pre-commit hooks** can enforce the "refresh the primer in the same commit as substantive changes" rule if drift becomes a problem. This skill does not install one — it relies on discipline. Add a hook only if you find yourself forgetting.

## Philosophy

The two files answer two different questions:

- Primer: "What is true about this project **right now**?"
- LEARNINGS: "What should I know to avoid rediscovering something painful?"

Together they compress the cost of session handoff from "re-explain everything" to "read two files." The primer stays short (a few hundred lines max); LEARNINGS grows organically. Both outlive any single session.
