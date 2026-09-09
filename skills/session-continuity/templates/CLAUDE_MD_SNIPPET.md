<!--
Copy this section into the project's CLAUDE.md verbatim (adjust only the
bracketed notes). It is what makes the session-continuity plugin actually
work for every session, not just the one that ran /session-continuity:primer.
Delete this comment block before committing.
-->

## Session continuity

**Boot order (before touching anything):**
1. `.session-continuity/PROJECT_CONTEXT.md` — stable repo shape
2. `.session-continuity/LEARNINGS.md` — grep when something surprises you
3. engrim context / recall (required)
4. graphify query when the question is about code structure (`graphify-out/graph.json` is committed)
5. `.session-continuity/SESSION_PRIMER.md` — Mid-flight + Confirm
6. `/session-continuity:backlog` for deferred decisions and follow-ups
7. `.session-continuity/ROADMAP.md` for strategic direction

**Refresh the primer alongside substantive commits.** Stage Mid-flight +
Confirm updates in the same commit as the real change — never a primer-only
commit (exceptions: a one-shot catch-up, correcting a factual error, or
recording a just-shipped release). When a bug takes 15+ minutes to diagnose,
append a LEARNINGS entry.

**Before closing any backlog issue, check it against the actual
code** — one grep or read per load-bearing claim, not memory and not a
commit-subject keyword match alone. A commit whose subject mentions an
issue's keywords does not mean it shipped; a fix landing inside an unrelated
commit can leave an issue open when it already shipped. Both
directions are real drift, and both are wrong to guess at.

**Never chain `git add <file> && git commit` in one Bash call for a file
this plugin's content gates cover** (a spec, plan, or LEARNINGS entry). Each
gate matches on the whole command string containing `git commit`; if it
denies, the entire tool call is denied — the `add` never ran either, and it
won't run on a bare retry since the string still matches. Stage and commit
as two separate calls: `git add <file>`, then a plain `git commit` with no
`-a` and no pathspec.

<!-- Optional, if multiple people work on this repo:
Both `.session-continuity/` files and this CLAUDE.md section are checked-in,
not gitignored — every teammate (and every Claude session) gets the same
handoff. LEARNINGS.md doubles as a living post-mortem log.
-->
