# Backlog — {{PROJECT_NAME}}

Explicitly deferred follow-ups and decisions — not bugs (those
go in `.session-continuity/LEARNINGS.md`), not current state (that's
`.session-continuity/SESSION_PRIMER.md`). An item lives here from the
moment it's flagged until the moment the code proves it resolved, then
it's deleted outright — the closing commit is the historical record, not
this file.

**Heading format: `### <position>. [<tag>] [<YYYY-MM-DD>] <Title>`.**
`<position>` is ephemeral display order only — always 1..N, no gaps,
recomputed fresh every time the list renders. It carries no permanent
meaning and is never grepped or cross-referenced. `<tag>` is a permanent
4-hex-character ID minted once when the item is filed (e.g. `a3f9`) —
check it's unused in this file, then never change or reuse it. `<date>`
is the filing date. Cross-references ("see item `a3f9`") use the tag,
never the position. Before deleting a closed item, grep the whole repo
for its tag (e.g. `\[a3f9\]`, `item a3f9`) — a hit means fix the
referencing text or leave the closed item as a one-line "closed" stub
instead of deleting it. When telling the user about a specific item,
always show both position and tag together, e.g. `1 [a3f9]`.

**Length cap.** Each item is a title plus 1-3 sentences. If it needs a
design sketch, an invariant, or a rejected-alternatives discussion, put
that in a spec under `meta/superpowers/...` and link it here — this file
stays a scannable list, not a second spec repository.

{{BACKLOG}}

<!-- Example:
### 1. [a3f9] [2026-09-01] `/session-continuity:doctor` command

No way today for a project to ask "is this actually working" — found out
by hitting a gate denial cold. Check: hooks registered, all files fresh,
CLAUDE_PLUGIN_ROOT resolves, gate scripts executable.
-->
