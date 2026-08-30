# Outstanding Items — session-continuity

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

### 1. Submit to the Anthropic marketplace

Form answers in `meta/administrative/marketplace-submission.md` (version
field synced to 0.14.0 in the docs-accuracy sweep on 2026-08-13 —
re-check against `.claude-plugin/plugin.json` at actual submission time,
this field drifts every release).

### 2. Automated integration tests

Manual validation only right now — no bats-style shell test harness
exercises the slash commands against a fixture repo. Good candidates:
Split mode in `commands/primer.md`, the `learning`-skill
duplicate-detection guard, v0.14.2's end-session fast-path/overlap-gate
logic, and v0.14.4's test-count skip/escalate logic — none exercise the
nothing-changed / touched / untouched, or changed-but-count-holds /
genuinely-drifted cases beyond prose review.

### 3. Scratch-project smoke test for the primer split (deferred from this session)

The v0.13.0 implementation plan's Task 6 validated the split mechanically
against this repo's own files but explicitly deferred the spec's Testing
items 1-2 (fresh init in a scratch project, and Split mode against a
throwaway unsplit primer) since they need a directory outside this repo.
Run both before the next `/session-continuity:primer` change lands.

### 4. Global docs-current hooks check "touched," not "accurate" — generalize the existing pass-count mechanism

Neither `~/.githooks/pre-commit` nor the global Claude Code `Stop` hook
checks whether a doc's claims stay *true* — both only check whether a doc
file was touched, with one hard-coded exception (the primer's `"NN pass"`
count check). Invariant (CLAUDE.md rule 4): every count or
named-entity-list claim in shipped docs must match actual repo state at
commit time, enforced at the gate that runs on every commit. Design:
`meta/superpowers/recommendations/docguard-design-sketch.md`.

### 5. Review `.session-continuity/performance.log`

Real timing data has been accumulating since v0.15.1 fixed the
`$CLAUDE_PLUGIN_ROOT` bracing bug — hook-side entries (`session-start.sh`,
`pre-commit-check.sh`, gate hooks) plus command-side entries from
`primer.md`/`end-session.md`, and v0.16.0's end-to-end
`step-4-ritual-complete` measurement. v0.16.0 added the end-to-end
*instrument* but never analyzed the log — look at what it actually shows
before deciding whether any hook or command-step is slow enough to
warrant more work; this is the first real data the whole feature was
built to produce.

### 6. Release the Init-mode enrichment in `commands/primer.md`

The Init-mode changes (test-run seeding of `{{TEST_COMMAND_SUMMARY}}`,
`@module`-derived `{{MODULES_TABLE}}`, `CLAUDE.md`-drafted
`{{WORKFLOW_CONVENTIONS}}`) merged to main via PR #18 but carry no
version bump. Cut the version bump + CHANGELOG entry + tag + GitHub
release per the established ritual. Also worth doing first: exercise the
enriched Init mode against a scratch project (overlaps item 3) — none of
the three new derivations has run end-to-end against a real fresh repo
yet.

### 7. Two optional follow-ups from v0.17.0's final review (non-blocking, not fixed in that session)

(a) `hooks/lib/gate-common.sh`'s `gate_scan_staged` still uses `[ -z "$f"
] && continue`/`[ -z "$content" ] && continue` — confirmed safe (non-tail
position, doesn't abort under `set -e`), but it's now the only spot in
the gate codebase still using the idiom every gate file converted to
`if/fi`. (b) Document in SKILL.md/spec that a gate's escape hatch is
file-scoped, not entry-scoped — one `Gate: N/A` line in a LEARNINGS.md
whitelists the whole file for that gate.

### 8. `/session-continuity:doctor` command

Checks: hooks actually registered (`hooks.json` wired vs `settings.json`),
all four `.session-continuity/` files exist and aren't stale,
`CLAUDE_PLUGIN_ROOT` resolves, gate scripts are executable. Right now a
project has no way to ask "is this actually working" — they find out by
hitting a gate denial cold, or by a mechanism silently never firing (the
exact class LEARNINGS already has one instance of: v0.16.0's dropped
session-start self-log). Flagged during the architect-workbench "Read
first" review session, 2026-08-30.

### 9. Trim `SKILL.md`

216 lines is a lot for every consuming session to load. Split into a
short operational quick-ref (what to read, when to refresh, the
gate-chain-commit and outstanding-item-verify traps) + push
gate-internals/customization-guidance detail into a `REFERENCE.md` the
skill links to instead of inlining. Lower urgency than item 8 — same
"cognitive load on the adopting project" problem in miniature; flagged
same session.
