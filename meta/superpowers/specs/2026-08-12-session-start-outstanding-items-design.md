# Design — SessionStart surfaces outstanding items

Date: 2026-08-12
Status: approved (brainstorming), pending implementation plan

## Problem

`hooks/session-start.sh` already computes an `Outstanding items: N` count in
its 4-line status block, but never shows *what* those items are, and never
prompts the user to pick one. Outstanding item #5 in the primer names this
gap explicitly: SessionStart should restate the list and ask which (if any)
to work on this session, instead of leaving that entirely to the model's
judgment.

## Decision

Extend the existing `<system-reminder>` block with a new "Outstanding items"
section, appended *after* the existing 4-line status block, populated by a
new awk pass that extracts the **first line only** of each top-level
numbered item (`^[0-9]+\. `) inside `## Outstanding items` — same
section-boundary logic already used for `status_outstanding`. Full
multi-line detail (e.g. item 2's ten sub-bullets) is dropped; the first line
alone is enough for the model to relay to the user and enough to keep the
SessionStart context injection small. This mirrors the existing 4-line
status block's philosophy: compact, best-effort, never crashes the hook.

Accepted tradeoff: an item whose first line ends mid-sentence (e.g. item 2's
"...deemed high-value):" — the colon dangles into the now-dropped sub-list)
will render as a truncated-looking line. No trimming/reformatting logic is
added for this — the model relaying the list to the user can paraphrase, and
adding text-shape heuristics (detect trailing colon, etc.) is exactly the
kind of speculative complexity this hook has avoided elsewhere.

The new section is appended to the reminder text, followed by an explicit
instruction line telling Claude to ask the user which item (if any) to
tackle — closing the gap that item #5 identifies (nudge-to-read-primer
today does not equal prompt-to-pick-work).

If the primer has zero outstanding items (missing section, or section with
no numbered lines), the new block is omitted entirely — no "Outstanding
items: 0" noise, matching the silent-omit pattern already used elsewhere in
the script (e.g. exit 0 on missing primer).

## Output shape

```
<system-reminder>
This project has .session-continuity/SESSION_PRIMER.md. Read it before any work — it's the fastest path to context. Also check .session-continuity/LEARNINGS.md if anything surprises you.

Primer status (auto):
- HEAD: f9b75cd
- Last primer change: 2026-08-12 11:59
- Outstanding items: 5
- Learnings: 7

Outstanding items:
1. Submit to the Anthropic marketplace.
2. Deferred recommendations from `meta/superpowers/recommendations/improvements_20260521.md` (rejected or not-yet-prioritized — v0.5.1 + v0.6.0 shipped the items deemed high-value):
3. Automated integration tests.
4. Plan to drop the `docs/` fallback in hooks.
5. SessionStart should restate outstanding items and ask which to work on.

Ask the user which of these (if any) they want to tackle this session.
</system-reminder>
```

## Implementation notes

- New awk block runs after the existing `status_outstanding` counter, same
  section-boundary pattern (`/^## Outstanding items/ {inside=1}` /
  `inside && /^## / {exit}` / `inside && /^[0-9]+\. /`), but prints the
  matched line instead of counting it.
- Guard: only emit the "Outstanding items:" sub-block (and its trailing
  instruction line) if the extracted list is non-empty.
- No change to the existing 4-line status block, no new files, no
  `hooks.json` wiring change, no JSON — same plain-stdout contract.
- `docs/` legacy-path branch gets the same treatment as `.session-continuity/`
  (the script already branches on `primer_path`/`learnings_path` for both;
  the new awk pass reads from whichever `primer_path` was resolved, so both
  branches get the feature for free).

## Testing

No `session-start.sh` smoke runner exists yet (checked
`meta/superpowers/validation/` — none named `session-start`). This is a
**new** hermetic runner, not an extension, following the same pattern as
`*-gate-smoke.zsh`: `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh`.
Cases:

- Fixture primer at `.session-continuity/SESSION_PRIMER.md` with several
  outstanding items, including one multi-line item — assert only the first
  line is captured and the trailing instruction line is present.
- Same fixture shape at the legacy `docs/SESSION_PRIMER.md` /
  `docs/LEARNINGS.md` path — assert the feature works on that branch too,
  not just asserted true in prose.
- Primer with an empty/missing `## Outstanding items` section — assert no
  "Outstanding items:" block and no instruction line appear.

## Out of scope

- Does not change `/session-continuity:end-session`'s existing
  outstanding-items verification (v0.12.0) — that's a separate, unrelated
  code path (Step 1 of end-session, not SessionStart).
- Does not add interactivity to the hook itself — hooks only inject text;
  the actual "ask the user" step happens in the model turn that follows,
  same as today's primer-read nudge.
