# Design — split SESSION_PRIMER.md into volatile + stable files

Date: 2026-08-13
Status: approved (brainstorming), pending implementation plan

## Problem

`.session-continuity/SESSION_PRIMER.md` mixes two kinds of content: a
volatile shortlist (current state, outstanding items, `git log --oneline -5`
block) that changes with nearly every substantive commit, and stable
reference material (ground rules, repo layout, module table, workflow
conventions, "where to look for what") that changes only when the project's
shape itself changes — maybe monthly. This repo's primer is 276 lines, most
of it stable.

`meta/superpowers/recommendations/improvements_20260521.md` §6.1 proposed
splitting the file; the primer's own Outstanding item #2 previously recorded
this as **rejected** ("doubles maintenance, one file = one mental model").
That rejection is explicitly overridden in this session on direct request —
noted in the primer's Outstanding item #2 update dated 2026-08-13.

One correction to §6's original framing: the SessionStart hook does **not**
inject the full primer on every turn — it injects a cheap 4-line status
block (`hooks/session-start.sh`), and the full file is read once per
session per the user's global `~/.claude/CLAUDE.md` instruction. The
motivating cost is real but smaller than §6 claimed: a smaller one-time
per-session read, and a stable file that can benefit from prompt caching
across sessions (its content rarely changes commit-to-commit).

## Decision

Split into two canonical files under `.session-continuity/`:

- **`SESSION_PRIMER.md`** (volatile) — intro, "First things first" (gains a
  pointer to the new file), Current state (+ `git log --oneline -5` block),
  Outstanding items.
- **`PROJECT_CONTEXT.md`** (stable, new) — Ground rules, Repo layout,
  Working directory, The packages/modules, Test expectations, End-to-end
  check, Workflow conventions, Where to look for what, If you get stuck,
  Primer maintenance (renamed "Maintenance" — now covers both files).

Both live at `.session-continuity/`, mirroring the existing pairing with
`LEARNINGS.md`. Neither file is gitignored; both are checked-in artifacts,
same as today.

### Migration

`commands/primer.md`'s Step 1 detection gains a 6th state, checked only when
a canonical primer already exists at `.session-continuity/SESSION_PRIMER.md`
and there is no `.session-continuity/PROJECT_CONTEXT.md`:

- **Unsplit canonical primer** → split mode (new Step, inserted after
  today's Step 4 "Conflict mode", renumbering the rest).

Split mode: read the existing primer, partition its sections per the
boundary above, write `PROJECT_CONTEXT.md` with the stable sections, rewrite
`SESSION_PRIMER.md` to keep only the volatile sections plus a new line in
"First things first" pointing at `PROJECT_CONTEXT.md`. Stage both files.
Never delete history — this is a content move within tracked files, done via
normal `Write`, not `git mv` (no path is changing). Then fall through into
whichever of refresh/check mode would otherwise have applied, same pattern
`commands/primer.md` already uses after Migrate mode (Step 2, point 6).

This mirrors the existing `docs/` → `.session-continuity/` migration
(Step 2) in spirit — detect an old shape, one-time transform, fall through —
but moves *content between files*, not *files between directories*.

### Init mode

`commands/primer.md` Step 3 (Init mode) copies a third template,
`templates/PROJECT_CONTEXT.md`, alongside the two existing ones, and derives
its placeholders the same way (project name, working directory, packages,
etc. — everything Step 3 already derives that belongs to the stable half).
New projects are born already split; only pre-existing unsplit primers need
migration.

### Hooks

No code change to `hooks/session-start.sh` or `hooks/pre-commit-check.sh`.

- `session-start.sh` only ever reads `SESSION_PRIMER.md` for its status
  block and outstanding-items list — both stay in the volatile file, so its
  logic is untouched.
- `pre-commit-check.sh`'s staged-file allowlist already matches the whole
  `.session-continuity/` prefix (line 91: `^(docs/|\.session-continuity/|...)`),
  so `PROJECT_CONTEXT.md` is covered automatically.

### `commands/end-session.md`

- Drift-check (Step comparing `git log --oneline -5` blocks) stays scoped to
  `SESSION_PRIMER.md` only. `PROJECT_CONTEXT.md` has no mechanical drift
  signal — it's stable prose with nothing to diff against — so no drift
  check is added for it. **Explicit non-goal.**
- The staging step (`git add .session-continuity/SESSION_PRIMER.md`) also
  stages `PROJECT_CONTEXT.md` when it has unstaged changes, so an edit made
  there during the session (e.g. repo layout changed) isn't silently
  dropped: `git add .session-continuity/SESSION_PRIMER.md; git diff --quiet
  .session-continuity/PROJECT_CONTEXT.md || git add
  .session-continuity/PROJECT_CONTEXT.md`.
- Preflight (checks both files exist before proceeding) is unaffected —
  `PROJECT_CONTEXT.md` is not required for `end-session` to run; its absence
  just means an unsplit or pre-migration primer, which the primer/learning
  commands already handle on their own paths.

### `commands/learning.md`

No change. It never reads or writes `SESSION_PRIMER.md`.

### `skills/session-continuity/SKILL.md`

Doc-only updates:
- "The two files" intro becomes "the three files," with `PROJECT_CONTEXT.md`
  described alongside the existing two.
- "Quick start (new project)" mentions the third template copy.
- "Quick start (existing project with these files)" gains a check for
  `PROJECT_CONTEXT.md`'s absence, pointing at `/session-continuity:primer`
  to run split mode (parallel to the existing pre-v0.5.0 `docs/` quick
  start).
- "Where to look for what" table rows that currently point at
  `SESSION_PRIMER.md` for stable questions (repo layout, module table,
  conventions) get repointed to `PROJECT_CONTEXT.md`.

### This repo (dogfood)

The implementation plan performs the actual split on this repo's own
`.session-continuity/SESSION_PRIMER.md` as part of landing the feature —
same as the LEARNINGS.md symptoms-index/slug retrofit already done this
session.

## Out of scope

- No JSON sidecar / structured-data lock for either file (§7 of the
  recommendations doc — separately rejected, stands).
- No automated drift-check for `PROJECT_CONTEXT.md` (see above).
- No change to `hooks/learnings-surface.sh` — it only reads
  `LEARNINGS.md`, unaffected by this split.
- No caveman/cavecrew cross-plugin integration (§8 — separately deferred).

## Testing

No automated test suite exists for this plugin (manual validation only, per
this repo's own stable-file "Test expectations" section — which is itself
one of the sections moving in this change). Validation is manual:

1. In a scratch project with an **unsplit** canonical primer (the shape
   this repo's primer had before this change), run `/session-continuity:primer`
   and confirm split mode fires: `PROJECT_CONTEXT.md` is created with the
   stable sections, `SESSION_PRIMER.md` is rewritten to the volatile
   sections only plus the new pointer line, both are staged, nothing is
   silently dropped (spot-check section-by-section against the pre-split
   file).
2. In a **fresh** project, run `/session-continuity:primer` (init mode) and
   confirm all three files (`SESSION_PRIMER.md`, `PROJECT_CONTEXT.md`,
   `LEARNINGS.md`) are created and staged with no leftover `{{PLACEHOLDER}}`
   tokens.
3. Run `/session-continuity:end-session` after touching `PROJECT_CONTEXT.md`
   by hand and confirm it gets staged alongside the primer.
4. Run `/session-continuity:end-session` after touching only code (not
   `PROJECT_CONTEXT.md`) and confirm the existing behavior (primer-only
   stage, no spurious `PROJECT_CONTEXT.md` diff) is unchanged.
