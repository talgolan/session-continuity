# Outstanding Items — {{PROJECT_NAME}}

Backlog of explicitly deferred follow-ups and decisions — not bugs (those
go in `.session-continuity/LEARNINGS.md`), not current state (that's
`.session-continuity/SESSION_PRIMER.md`). An item lives here from the
moment it's flagged until the moment the code proves it resolved, then
it's deleted outright — the closing commit is the historical record, not
this file.

**Numbering is permanent.** A new item takes the next unused number;
closed items are deleted, never renumbered, never reused. Cross-references
("see item 4") stay valid as long as item 4 exists. Before deleting a
closed item, grep the whole repo for references to its number (e.g.
`\bitem #?4\b`, `outstanding item(s)? 4`) — a hit means fix the
referencing text or leave the closed item as a one-line "closed" stub
instead of deleting it.

**Length cap.** Each item is a title plus 1-3 sentences. If it needs a
design sketch, an invariant, or a rejected-alternatives discussion, put
that in a spec under `meta/superpowers/...` and link it here — this file
stays a scannable list, not a second spec repository.

{{OUTSTANDING_ITEMS}}

<!-- Example:
### 1. `/session-continuity:doctor` command

No way today for a project to ask "is this actually working" — found out
by hitting a gate denial cold. Check: hooks registered, all files fresh,
CLAUDE_PLUGIN_ROOT resolves, gate scripts executable.
-->
