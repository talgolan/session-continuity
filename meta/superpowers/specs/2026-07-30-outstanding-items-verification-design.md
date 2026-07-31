# Design — outstanding-items code verification in `/session-continuity:end-session`

Date: 2026-07-30
Status: approved (brainstorming), pending implementation plan

## Problem

`/session-continuity:end-session`'s Final checklist reports staged/unstaged/
untracked files and unpushed commits, but never checks whether the primer's
**outstanding items** still reflect reality. A stale item — one the code has
already resolved — lingers indefinitely, and a genuinely-open item gets no
confirmation it's still open. The user wants the close-out ritual to verify
outstanding items against actual repo state.

## Constraint that shapes the design

Outstanding items are hand-written prose. Roughly half are **not**
code-verifiable — they name external actions or parked decisions with no
artifact to grep for:

| # (current primer) | Item | Code-checkable? |
|---|---|---|
| 1 | Submit to Anthropic marketplace | ❌ external, no artifact |
| 2 | Deferred recommendations (rejected/parked) | ❌ decisions, not code |
| 3 | Automated integration tests | ✅ does a bats/test harness exist? |
| 4 | Drop `docs/` fallback in hooks | ✅ grep `hooks/` for `docs/` |
| 5 | Capture v0.4.0 learnings | ⚠️ grep LEARNINGS for those titles |

A blanket "verify all items" would force fabricated verdicts on items with no
footprint. So verification must **classify first**, then verify only the
code-shaped items, and mark the rest `manual` rather than assert anything.

## Decisions (from brainstorming)

1. **Classify, verify only code ones.** Each item is tagged code-verifiable or
   not. Non-code items are reported `manual — not auto-verifiable`, never
   asserted done or open.
2. **LLM-derived check, evidence-gated.** No structured `Verify:` field is
   added to items (zero schema change). end-session reads each item, derives a
   `grep`/`glob`/file-exists check, and reports a verdict **only with cited
   evidence** (`file:line` or grep output/count). No evidence → `manual`. This
   reuses the plugin's own proven-gate / evidence-gate discipline: no "done"
   claim without a real-path artifact.
3. **Surface as close-candidate, never auto-close.** An `appears-DONE` verdict
   flags the item as a close-candidate; removal still requires explicit user
   confirmation. This honors the existing invariant in `commands/primer.md`
   (Step 5.4) and `commands/end-session.md` (Step 1 overlay, "Refusal"):
   *"Never close an outstanding item without explicit user confirmation."*
   Auto-close was explicitly reconsidered and rejected — a fuzzy LLM grep
   false-positive would silently delete a real deferred item, a destructive
   hard-to-notice edit on soft evidence.
4. **New checklist row in Step 3** reports the verdict, and the `appears-DONE`
   candidates feed **Step 1's existing combined prompt** (no new prompt).

## Verdicts

Per top-level item under the primer's `## Outstanding items` heading:

- **`still-open`** — artifact absent as expected. Cite the negative check
  (e.g. "no `*.bats` and no `test/` dir → item 3 still open").
- **`appears-DONE`** — artifact present/absent in a way that proves resolution
  (e.g. "grep `hooks/` for `docs/` → 0 hits → item 4 resolved"). Cited
  evidence required. **Close-candidate — never auto-removed.**
- **`manual`** — non-code item (external action / decision), OR a code item
  where no unambiguous evidence was found. Printed as
  `manual — not auto-verifiable`. Never asserted done or open.

**Evidence rule:** any verdict of `still-open` or `appears-DONE` MUST carry a
cited artifact (`file:line`, grep count, or glob result). Absent evidence
downgrades to `manual`. This is the same gate the plugin enforces on "proven"
claims elsewhere.

## Placement — inside Step 1, reported in Step 3 (no standalone step)

Verification is NOT a new standalone step. It splits across the two existing
touch-points so it adds zero prompts and needs no reordering:

- **Runs inside Step 1's refresh flow.** After the drift check enters the
  refresh flow, classify + verify each outstanding item. Any `appears-DONE`
  candidate is appended to the existing outstanding-items overlay and surfaced
  at Step 1's single combined prompt ("close any from the overlay, add new
  follow-ups, or no changes?"). One reply closes it.
  - **Drift-clean case:** when the drift check finds the primer already
    current, Step 1's refresh flow is skipped entirely. Verification still runs
    (it does not depend on drift) but produces no prompt — its results flow
    only to the Step 3 row. This keeps the "drift-clean + zero candidates =
    zero prompts" guarantee: a stale outstanding item surfaces as a ⚠️ in the
    checklist, not as a blocking prompt.
- **Reported in Step 3.** A new `Outstanding items` checklist row reports the
  post-edit state (after any Step 1 closures the user confirmed):

  ```
  ⚠️ Outstanding items: 5 tracked — 1 appears DONE (#4, "drop docs/ fallback":
     grep hooks/ for 'docs/' → 0 hits), 2 still-open (#3, #5), 2 manual (#1, #2)
  ```

  Marker: ✓ if every item is `still-open` or `manual` (nothing stale lingering);
  ⚠️ if any item is `appears-DONE` (a resolved item still listed).

## Edge cases

- **No `## Outstanding items` heading** (custom-modified primer) → skip
  verification silently; Step 3 row reads `Outstanding items: none tracked`.
- **Zero outstanding items** → row reads `✓ Outstanding items: none tracked`.
- **Item spans sub-bullets** — tokenize/scope the item the same way the
  existing Step 1 overlay does (numbered line + indented continuation up to the
  next top-level number; sub-bullets roll up to their parent).
- **Ambiguous grep** (a match inside a comment, a doc reference rather than a
  live code path) → treat as insufficient evidence → `manual`, not
  `appears-DONE`. Bias toward `manual` over a false `appears-DONE`.

## Scope

- Prose-only edit to `commands/end-session.md`. No hooks, no schema, no new
  runtime files.
- Zero added user prompts (folds into Step 1's existing combined ask).
- Consistent with the plugin's never-auto-close and evidence-before-assertion
  invariants.

## Validation

Hermetic fixture: a primer with known-state outstanding items (one provably
DONE, one provably open, one non-code) in a scratch repo; assert the
classification + verdicts + Step 3 row marker. Manual: run end-session in this
repo and confirm item #4 (`docs/` fallback) verdict matches an actual
`grep hooks/` result.
