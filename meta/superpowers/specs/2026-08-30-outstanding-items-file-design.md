# Design: a standalone OUTSTANDING_ITEMS.md

Status: approved (brainstorming complete) — awaiting implementation plan.

## Problem

`.session-continuity/SESSION_PRIMER.md`'s "Outstanding items" section has
become the plugin's single biggest source of avoidable token cost and
process confusion:

1. **No stable identity.** Nothing in `SKILL.md`, `primer.md`, or
   `end-session.md` says item numbers are permanent. If item 3 closes,
   nothing prevents items 4-9 from being renumbered 3-8 — silently
   invalidating any cross-reference written while an earlier item was open
   (a real instance exists today: item 6 says "overlaps outstanding item 3").
   LEARNINGS.md already solved this ("new entries take the next available
   number; old entries keep theirs") but the fix was never generalized to
   outstanding items.
2. **Unbounded item length.** Some items have grown into inline
   mini-design-docs — item 4 in this repo's own primer carries a design
   sketch, an invariant statement, and a rejected-alternative note inline.
   Every session-start injection and every `end-session` verification pass
   re-reads the full text of every item, so this bloat is paid every
   session, not once.
3. **Mixed volatility.** The backlog (slow-changing decisions/follow-ups)
   lives inside the same section of the same file as "Current state" (the
   fastest-changing content in the whole system — regenerated `git log`
   blocks, per-commit notes). The file the primer/PROJECT_CONTEXT split was
   designed to keep short keeps growing anyway, because the backlog rides
   along.
4. **Heading-text coupling.** `session-start.sh` (awk range-scan) and
   `end-session.md` (the entire `appears-DONE`/`still-open`/`manual`
   verification pipeline) both locate items by grepping the literal
   `## Outstanding items` heading inside `SESSION_PRIMER.md`. There is no
   file-level seam — behavior and storage are welded together.

## Decisions (from brainstorming)

- **Close behavior: delete outright.** No archive section. The closing
  commit's message is the historical record; LEARNINGS already covers
  "wisdom worth keeping," outstanding items don't need a second archive.
- **Numbering: permanent, LEARNINGS-style.** New items take the next
  unused number. Closed items are deleted, never renumbered, never reused.
- **Scope: only the backlog moves.** SESSION_PRIMER.md's "In flight this
  session" bullets (uncommitted/staged work, genuinely volatile) stay in
  the primer. Only the slower-changing "Outstanding items" list moves.
- **Length: capped, with an escape valve.** Each item is a title + 1-3
  sentences. Anything needing a design sketch, an invariant, or a
  rejected-alternatives discussion goes into a spec/recommendation file
  under `meta/superpowers/` and gets linked, not inlined.

## File: `.session-continuity/OUTSTANDING_ITEMS.md`

Peer to the other three files. Intro block:

```markdown
# Outstanding Items — <project>

Backlog of explicitly deferred follow-ups and decisions — not bugs (those
go in LEARNINGS.md), not current state (that's SESSION_PRIMER.md). An item
lives here from the moment it's flagged until the moment the code proves
it resolved, then it's deleted outright — the closing commit is the
historical record, not this file.

**Numbering is permanent.** A new item takes the next unused number;
closed items are deleted, never renumbered, never reused. Cross-references
("see item 4") stay valid as long as item 4 exists.

**Length cap.** Each item is a title plus 1-3 sentences. If it needs a
design sketch, an invariant, or a rejected-alternatives discussion, put
that in a spec under `meta/superpowers/...` and link it here — this file
stays a scannable list, not a second spec repository.
```

### Item shape

Reuses LEARNINGS' exact heading pattern — `^### [0-9]+\.` — so every
consumer that already parses LEARNINGS this way (`session-start.sh`'s
`grep -cE '^### [0-9]+\.'` for the learnings count) can parse this file
identically. No new regex, no new parsing convention.

Self-contained item:

```markdown
### 8. `/session-continuity:doctor` command

No way today for a project to ask "is this actually working" — found out
by hitting a gate denial cold. Check: hooks registered, all three files
fresh, `CLAUDE_PLUGIN_ROOT` resolves, gate scripts executable.
```

Item needing detail beyond the cap (pointer, not inline):

```markdown
### 4. Global docs-current hooks check "touched," not "accurate"

Neither hook verifies a claim stays true, only that a doc was touched —
every drift in the 2026-08-13 sweep would've slipped through. Touches
machine-wide `~/.githooks`, not this repo — needs its own go-ahead.
Design: `meta/superpowers/recommendations/docguard-design-sketch.md`.
```

No `## <category>` grouping headers — the backlog is small enough (single
digits to low teens) that a flat ascending list is easier to scan than
LEARNINGS' by-layer grouping, which exists because LEARNINGS accumulates
without bound. Revisit if the list ever grows past ~20 open items.

## Consumer changes

### `hooks/session-start.sh`

Currently: awk range-scan between `^## Outstanding items` and the next
`^## ` heading inside `SESSION_PRIMER.md`, extracting first-line-only per
item.

New: if `.session-continuity/OUTSTANDING_ITEMS.md` exists, drop the
range-scan — `grep -E '^### [0-9]+\.' .session-continuity/OUTSTANDING_ITEMS.md`
gives count and title lines directly, no section to scope. Injected
reminder shows title lines verbatim (no truncation heuristic needed —
items are capped short by convention already).

**Migration bridge, not permanent dual-path.** If the new file doesn't
exist, fall back to today's awk range-scan against the primer's inline
`## Outstanding items` section, unchanged — an unmigrated project must
keep seeing its shortlist exactly as today until it runs
`/session-continuity:primer` and the new split detector migrates it.
Without this fallback, "old-format projects keep working exactly as
today" (see Backward compatibility below) would be false the moment this
ships — the hook would show zero items for every unmigrated project. Only
after the new file exists does the hook switch to reading it. This
fallback branch is a deletable bridge, not a feature to maintain forever —
worth a follow-up outstanding item once telemetry/anecdote says all known
consuming projects have migrated. If neither the new file nor an inline
section exists, zero items, same silent-degrade pattern the hook already
uses everywhere else (`|| echo '?'`).

### `commands/end-session.md`

- Outstanding-items verification section reads `OUTSTANDING_ITEMS.md`
  wholesale instead of scoping a heading inside the primer.
- **Unmigrated-project path: nudge, don't duplicate.** Unlike
  `session-start.sh` (a cheap grep swap), `end-session.md`'s verification
  pipeline (overlap gate, code-check, `appears-DONE` classification,
  close-candidate prompts) is expensive to maintain in two parallel forms.
  If the primer still has an inline `## Outstanding items` heading and
  `OUTSTANDING_ITEMS.md` doesn't exist yet, skip the whole verification
  pipeline for this run and tell the user once: "This project's outstanding
  items haven't migrated to `.session-continuity/OUTSTANDING_ITEMS.md` yet
  — run `/session-continuity:primer` first (it migrates automatically),
  then re-run `/session-continuity:end-session`." Do not attempt to
  verify/close items against the old inline format. If neither the new
  file nor an inline heading exists, "skip" means the ordinary "none
  tracked" path — this is a fresh/already-flat project, not an unmigrated
  one.
- Close-candidate edits and the staging line (`git add`) target
  `.session-continuity/OUTSTANDING_ITEMS.md` in addition to the primer.
- The existing 200-char item-truncation cap in the overlay-matching logic
  stays as defense-in-depth — harmless once the length cap makes it rarely
  trigger, but removing it buys nothing and risks a pathological long item
  blowing up tokenization.
- Step 3's checklist "Outstanding items" row re-reads the new file
  post-edit, same re-derive-don't-cache rule as today.

### `commands/primer.md`

- Refresh flow's outstanding-items ask/verify/close targets the new file
  (the verify-before-code-check rule shipped in the prior PR applies
  unchanged — it was written against "the actual code," not against
  wherever the list happens to live).
- Init mode ships a fourth template — `templates/OUTSTANDING_ITEMS.md`,
  an empty skeleton with the intro block above — alongside the existing
  three. The `{{OUTSTANDING_ITEMS}}` cold-ask placeholder still exists at
  init (a project may already know its day-one TODOs) but seeds the new
  file directly instead of a primer section.
- **New: extend Split mode.** Today's Step 3 detects "primer exists, no
  `PROJECT_CONTEXT.md` yet" and partitions stable-vs-volatile content. Add
  a parallel detector: "primer has an inline `## Outstanding items`
  section, no `OUTSTANDING_ITEMS.md` yet" → extract that section
  verbatim into the new file (items keep their current numbers — those
  become the first permanent IDs), drop the section from the primer. Runs
  once per project, same no-flag-day pattern as the existing split.

### `SKILL.md`, `templates/CLAUDE_MD_SNIPPET.md`, `README.md`

Every "three files" reference becomes four. `SKILL.md` gains:
- The new file in the opening file-list description and the "What goes
  where" decision-tree table (row: "We should follow up on X" →
  `OUTSTANDING_ITEMS.md`).
- A numbering-convention paragraph mirroring LEARNINGS': permanent IDs,
  delete-on-close, next-available-number for new items.
- The length-cap-with-pointer rule.

`CLAUDE_MD_SNIPPET.md` gets one added sentence naming the fourth file in
the read-first list.

## Backward compatibility

Old-format projects (inline `## Outstanding items` in the primer) keep
working exactly as today until they next run `/session-continuity:primer`,
which auto-migrates via the new split detector. No forced migration, no
flag day — identical posture to the existing PROJECT_CONTEXT split.

All three consumers (`session-start.sh`, `end-session.md`, `primer.md`)
treat a missing `OUTSTANDING_ITEMS.md` as zero items, never as an error —
consistent with every other best-effort fallback already in this codebase.

## Migration of this repo

This repo's own `SESSION_PRIMER.md` still carries the inline 9-item
section. The implementation plan must actually run the new split against
it — not just build the mechanism and leave the dogfood step for later.
Item 4's inline design sketch gets extracted to
`meta/superpowers/recommendations/docguard-design-sketch.md` as part of
that migration, since it's the one item that exceeds the new length cap.

## Testing

Manual scratch-repo validation via `claude --plugin-dir`, matching this
project's existing validation practice for command/hook changes — no new
automated test harness (that gap is tracked separately as outstanding
item #2). Validate at minimum:
- Fresh init produces all four files, `OUTSTANDING_ITEMS.md` well-formed.
- Split mode against a scratch primer with an inline section produces a
  correct `OUTSTANDING_ITEMS.md` and a primer with the section removed.
- `session-start.sh`'s injected reminder reflects the new file's count and
  titles.
- `/session-continuity:end-session`'s verification pipeline still
  classifies `appears-DONE`/`still-open`/`manual` correctly against the
  new file.

## Out of scope

- Automated integration tests for this or any other command flow
  (outstanding item #2, separate scope).
- Grouping outstanding items by category/layer (deferred until the flat
  list stops scaling).
- Any change to how LEARNINGS.md itself works — it's the model being
  copied, not something this design touches.
