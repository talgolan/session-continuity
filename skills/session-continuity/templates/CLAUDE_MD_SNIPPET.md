<!--
Copy this section into the project's CLAUDE.md verbatim (adjust only the
bracketed notes). It is what makes the session-continuity plugin actually
work for every session, not just the one that ran /session-continuity:primer.
Delete this comment block before committing.
-->

## Session continuity

Before touching anything, read `.session-continuity/SESSION_PRIMER.md`
(current state) and `.session-continuity/LEARNINGS.md` (bugs that were
expensive to diagnose — grep it when something surprises you). Read
`.session-continuity/PROJECT_CONTEXT.md` once per session for stable repo
shape, and `.session-continuity/OUTSTANDING_ITEMS.md` for the backlog of
deferred decisions and follow-ups; both change rarely.

**Refresh the primer alongside substantive commits.** Stage the update in
the same commit as the real change — never a primer-only commit (exceptions:
a one-shot catch-up, correcting a factual error, or recording a just-shipped
release). When a bug takes 15+ minutes to diagnose, append a LEARNINGS entry.

**Before marking any outstanding item DONE, verify it against the actual
code** — one grep or read per load-bearing claim, not memory and not a
commit-subject keyword match alone. A commit whose subject mentions an
item's keywords does not prove it shipped; a fix landing inside an unrelated
commit can leave an item reading OPEN when it already shipped. Both
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
