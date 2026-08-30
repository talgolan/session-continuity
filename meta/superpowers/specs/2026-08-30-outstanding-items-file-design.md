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
("see item 4") stay valid as long as item 4 exists. **Before deleting a
closed item, grep the whole repo for references to its number** (e.g.
`\bitem #?4\b`, `outstanding item(s)? 4`) — an item can be safely deleted
without leaving a dangling reference elsewhere; a hit means either fix the
referencing text or leave the closed item as a one-line "closed" stub
instead of deleting it. This is the same class of bug permanent numbering
exists to prevent — deletion is where it would otherwise slip back in.

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
by hitting a gate denial cold. Check: hooks registered, all four files
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
range-scan. Two separate greps replace it (a count needs `-c`; the
verbatim title lines need plain output — one call can't give both):
`grep -cE '^### [0-9]+\.' .session-continuity/OUTSTANDING_ITEMS.md` for
the count (same pattern the hook already uses for the LEARNINGS count),
`grep -E '^### [0-9]+\.' .session-continuity/OUTSTANDING_ITEMS.md` for
the title lines to inject verbatim. No section to scope in either case —
the whole file is the list. No truncation heuristic needed on the titles
— items are capped short by convention already.

**No dual-path fallback — prompt immediate migration instead.** Only one
project consumes this plugin today, so tolerating an indefinite
old-format/new-format split buys nothing and costs a permanent second
parsing path. If the new file doesn't exist AND the primer still has an
inline `## Outstanding items` section, skip both the old and new parsing
entirely and emit instead: "Outstanding items haven't migrated to
`.session-continuity/OUTSTANDING_ITEMS.md` yet — run
`/session-continuity:primer` now to migrate before continuing." If
neither the new file nor an inline section exists, zero items, same
silent-degrade pattern the hook already uses everywhere else
(`|| echo '?'`). No awk range-scan code path survives this change at
all — it's deleted, not kept as a fallback.

### `commands/end-session.md`

- Outstanding-items verification section reads `OUTSTANDING_ITEMS.md`
  wholesale instead of scoping a heading inside the primer.
- **Unmigrated-project path: nudge, don't duplicate.** Unlike
  `session-start.sh` (a cheap grep swap), `end-session.md`'s verification
  pipeline (overlap gate, code-check, `appears-DONE` classification,
  close-candidate prompts) is expensive to maintain in two parallel forms.
  If the primer still has an inline `## Outstanding items` heading and
  `OUTSTANDING_ITEMS.md` doesn't exist yet, skip **only the
  outstanding-items verification sub-flow** (overlap gate, code-check,
  `appears-DONE` classification, close-candidate prompts) and tell the
  user once: "This project's outstanding items haven't migrated to
  `.session-continuity/OUTSTANDING_ITEMS.md` yet — run
  `/session-continuity:primer` first (it migrates automatically), then
  re-run `/session-continuity:end-session`." Do not attempt to
  verify/close items against the old inline format. **Everything else in
  Step 1 proceeds normally** — the fast path, drift check, git-log
  regeneration, and test-count rerun are all independent of outstanding
  items and are not skipped by this condition. If neither the new file
  nor an inline heading exists, "skip" means the ordinary "none tracked"
  path — this is a fresh/already-flat project, not an unmigrated one.
- Close-candidate edits and the staging line (`git add`) target
  `.session-continuity/OUTSTANDING_ITEMS.md` in addition to the primer.
- The existing 200-char item-truncation cap in the overlay-matching logic
  stays as defense-in-depth, but its boundary rule must be restated for
  the new format: today it scopes an item as "the numbered line plus
  indented continuation lines until the next top-level number" (the old
  inline-section shape). Under the new file, an item's boundary is its
  `### N.` heading line through everything up to the next `### N.`
  heading or end of file — restate the boundary in those terms, then
  apply the same 200-char cap to that span. Harmless once the length cap
  makes it rarely trigger, but removing it buys nothing and risks a
  pathological long item blowing up tokenization.
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
  file directly instead of a primer section. **Conversion rule:** the
  user's cold-ask answer is free-form prose (a list, a paragraph, however
  they typed it) — Claude splits it into one `### N.` entry per distinct
  item, numbered sequentially starting at 1, trimming each to the title +
  1-3 sentence cap (same judgment call it already makes converting
  free-form LEARNINGS drafts into that file's entry format). Never write
  the raw answer in as a single unstructured blob.
- **New: extend Split mode, sequenced after the existing split.** Today's
  Step 3 detects "primer exists, no `PROJECT_CONTEXT.md` yet" and
  partitions stable-vs-volatile content. Add a second, independent
  detector for "primer has an inline `## Outstanding items` section, no
  `OUTSTANDING_ITEMS.md` yet" → extract that section verbatim into the
  new file (items keep their current numbers — those become the first
  permanent IDs), drop the section from the primer. **When both
  conditions are true in the same invocation** (a never-split project:
  no `PROJECT_CONTEXT.md` AND an inline Outstanding items section), run
  the existing PROJECT_CONTEXT split to completion first, then run the
  outstanding-items split against the resulting primer, as two sequential
  edits in the same Step 3 — not simultaneous partitioning. They touch
  disjoint sections of the primer (stable-context headings vs. the
  Outstanding items heading), so sequencing avoids any edit conflict
  without needing to merge the two detectors' logic. Each split runs (or
  is skipped) once per project, same no-flag-day pattern as today.

### `SKILL.md`, `templates/CLAUDE_MD_SNIPPET.md`, `README.md`

Every "three files"/"three templates" reference becomes four. `SKILL.md` gains:
- The new file in the opening file-list description and the "What goes
  where" decision-tree table (row: "We should follow up on X" →
  `OUTSTANDING_ITEMS.md`).
- A numbering-convention paragraph mirroring LEARNINGS': permanent IDs,
  delete-on-close, next-available-number for new items.
- The length-cap-with-pointer rule.
- **The "Quick start (new project)" section's prose**, which today says
  the primer command "copies all three templates from
  `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/`" — update
  to "all four templates." This line goes stale the moment Task 1 (per
  the implementation plan) ships a fourth template file, independent of
  the other three bullets above.

`CLAUDE_MD_SNIPPET.md` gets one added sentence naming the fourth file in
the read-first list.

## Backward compatibility

Only one project consumes this plugin today, so there is no installed
base to protect with a tolerated transition period — every existing
installation should migrate to the new format immediately, not
eventually. Both `session-start.sh` and `end-session.md` detect the old
inline-heading format and actively prompt migration (`run
/session-continuity:primer now`) rather than silently continuing to
support it. `primer.md`'s split detector does the actual migration, same
mechanism as the existing PROJECT_CONTEXT split — the difference from
that split is urgency: this one is pushed, not merely offered.

All three consumers still treat a missing `OUTSTANDING_ITEMS.md` **and**
no inline heading (a genuinely fresh, already-flat project) as zero
items, never as an error — that's the ordinary best-effort fallback
pattern already used everywhere else in this codebase, unrelated to
migration.

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
- **Migration-nudge paths** (the one genuinely new piece of UX this spec
  adds): against a scratch primer with an inline `## Outstanding items`
  section and no `OUTSTANDING_ITEMS.md`, confirm `session-start.sh`
  prints the "run `/session-continuity:primer` now" reminder instead of
  the old shortlist, and `/session-continuity:end-session` prints its own
  nudge and skips only the outstanding-items sub-flow (drift check /
  git-log / test-count still run). Confirm both go silent on an
  already-migrated project — the detection condition must not misfire
  once `OUTSTANDING_ITEMS.md` exists.

## Out of scope

- Automated integration tests for this or any other command flow
  (outstanding item #2, separate scope).
- Grouping outstanding items by category/layer (deferred until the flat
  list stops scaling).
- Any change to how LEARNINGS.md itself works — it's the model being
  copied, not something this design touches.
