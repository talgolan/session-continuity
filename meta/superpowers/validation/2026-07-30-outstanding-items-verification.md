# Validation log — outstanding-items verification (v0.12.0)

**Branch:** `feat/outstanding-items-verification`
**Spec:** `meta/superpowers/specs/2026-07-30-outstanding-items-verification.md`
**Plan:** `meta/superpowers/plans/2026-07-30-outstanding-items-verification.md`

This log records the manual validation matrix for the v0.12.0
outstanding-items verification feature. Each scenario is documented with:
setup, expected behavior, actual behavior, pass/fail.

---

## Scenario 1 — Case A: drift detected, appears-DONE item routes to the combined prompt as a close-candidate with cited evidence

**Setup.** Branch with a primer containing an outstanding item that describes a missing file or hook. The item's artifact now exists in the repo (verification detects it as `appears-DONE`). Drift is present (commits since last primer refresh).

**Expected.** Step 1's verification sub-block runs before the drift check. The item classifies as code-verifiable (names a file/hook/test harness). The derived grep/file-exists check finds the artifact present → verdict `appears-DONE` with cited evidence (file:line or glob result). Because drift exists, the refresh flow enters. The combined prompt surfaces two lists: (1) commits since last primer refresh (from the overlay), and (2) `appears-DONE` items with cited code evidence (from verification). Both are close-candidates. User can confirm closure of the `appears-DONE` item at this single prompt.

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 2 — Case B: drift-clean, verification runs, no prompt, verdict held for Step 3 only

**Setup.** Primer is drift-clean (git log block matches HEAD). Primer contains a code-verifiable item whose artifact is still absent (`still-open` verdict).

**Expected.** Step 1's verification sub-block runs (unconditional — it does NOT respect the drift gate). Verification computes `still-open` verdict with negative-check evidence. Because the primer is drift-clean, the refresh flow does NOT enter — no prompt fires. The verdict is held in memory for Step 3 only. Step 3's checklist row reports the item as `still-open` with cited evidence. Zero prompts total in this invocation.

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 3 — Case C: user closes an appears-DONE item at the prompt, then Step 3 re-derives, item absent, marker checkmark

**Setup.** Same as Scenario 1 (drift + `appears-DONE` item). User replies at the combined prompt to close the `appears-DONE` item. Skill removes the item from the primer and stages the file.

**Expected.** After user confirms closure, the primer no longer contains the closed item. Step 3 re-reads the `## Outstanding items` section from the primer (post-edit). The closed item is absent from the re-derived count. Step 3's checklist row reports `N tracked` (N = remaining items), with no mention of the closed item. If all remaining items are `still-open` or `manual`, marker is ✓; if any remaining item is `appears-DONE`, marker is ⚠️.

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 4 — Case D: drift-clean stale item, Step 3 reports it, marker warning, no deletion

**Setup.** Primer is drift-clean. Primer contains a code-verifiable item whose artifact now exists (`appears-DONE` verdict). No drift, so no prompt fires.

**Expected.** Step 1 verification runs and computes `appears-DONE` verdict with cited evidence. Because the primer is drift-clean, no prompt fires — the verification result is held for Step 3 only. Step 3's checklist row reports `N tracked — 1 appears-DONE (#X, <evidence>), ...` with marker ⚠️. The item is NOT deleted from the primer. Across repeated drift-clean invocations, the same ⚠️ repeats every time until a drift-bearing session or manual `/primer` refresh gives the user a chance to close it.

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 5 — never-auto-close invariant: appears-DONE item + "no changes" reply, item STILL present in primer afterward, Step 3 still warning appears-DONE

**Setup.** Drift detected + `appears-DONE` item surfaces at the combined prompt. User replies "no changes" (or equivalent).

**Expected.** Skill does NOT remove the item from the primer. The item remains present in `## Outstanding items`. Step 3 re-reads the primer, finds the item still there, and reports it with marker ⚠️ as `appears-DONE`. A verdict never mutates the primer on its own — removal always requires explicit user confirmation.

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 6 — non-code item (marketplace submission): verdict manual — not auto-verifiable, never asserted

**Setup.** Primer contains an outstanding item describing an external action (e.g., "Submit to the Anthropic marketplace").

**Expected.** Step 1's classification logic identifies the item as non-code (no file/hook/test harness named). Verdict is `manual — not auto-verifiable`. No grep/file-exists check is run. Step 3's checklist row reports the item as `manual (#N)`, never as `still-open` or `appears-DONE`.

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 7 — ambiguous grep (match inside a comment): manual, not appears-DONE (bias rule)

**Setup.** Primer contains a code-verifiable item. The derived grep finds matches, but all matches are inside comments or doc references (not live code paths).

**Expected.** Verification's evidence rule and bias-toward-manual logic apply. The grep result is inspected; if the match is ambiguous (comment, doc block, test fixture string), the verdict is `manual`, NOT `appears-DONE`. Evidence rule: a verdict without unambiguous evidence downgrades to `manual`. Step 3's checklist row reports the item as `manual (#N)`.

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 8 — no Outstanding items heading: verification skipped, row reads "none tracked"

**Setup.** Primer has been custom-modified and lacks a `^## Outstanding items` heading (or the section exists but is empty).

**Expected.** Step 1's verification sub-block skips silently (matching the overlay's existing skip clause). No verdicts are computed. Step 3's checklist row reads `Outstanding items: none tracked` (marker ✓).

**Actual.** _(filled at validation time)_

**Result.** _(pass / fail / note)_

---

## In-repo manual check — real grep count

**Command:** `grep -rn 'docs/' hooks/ | wc -l`

**Actual count:** 18

**Interpretation:** The `docs/` fallback is still present in hooks (>0 hits). Outstanding item #4 ("Plan to drop the `docs/` fallback in hooks") should resolve to verdict `still-open`, NOT `appears-DONE`, as of this validation run. Matches expectation — the fallback is deliberately kept until v1.0.0.

---

## Acceptance gate

Per the spec's acceptance criteria:
- All 8 scenarios cover the Cases A–D routing logic, the never-auto-close invariant, edge cases (no heading, ambiguous grep, non-code items), and the Step 3 re-derivation flow.
- The in-repo manual check confirms the `docs/` fallback is still present (verdict `still-open`).
- Each scenario's Expected matches the prose in `commands/end-session.md` Step 1 (Outstanding-items verification sub-block) and Step 3 (Outstanding-items row).
- `Actual` and `Result` fields are deliberate `_(filled at validation time)_` markers, matching the established precedent format from `2026-05-21-end-session-heuristics.md`.

**Verdict.** Matrix complete. Ready for runtime validation against fixture repo.
