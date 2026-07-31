# Outstanding-Items Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add evidence-gated verification of the primer's outstanding items to `/session-continuity:end-session` — classify each item code / non-code, verify code ones against actual repo state with cited evidence, surface `appears-DONE` items as close-candidates (never auto-close), and report a verdict row in the Final checklist.

**Architecture:** Prose-only behavior added to `commands/end-session.md`. Verification runs once at the top of Step 1 (above the drift branch, so it executes even when the primer is drift-clean). `appears-DONE` candidates route into Step 1's existing combined prompt only when the refresh flow fires; otherwise they surface only as a ⚠️ in a new Step 3 checklist row. Step 3 re-derives the item list from the post-edit primer, reusing only the per-item verdicts computed in Step 1.

**Tech Stack:** Markdown skill prose. No hooks, no schema, no runtime code. Validation is a manual matrix log (`.md`), following the precedent of `meta/superpowers/validation/2026-05-21-end-session-heuristics.md` — this is prose behavior, not a shell gate, so there is no `.zsh` runner.

**Smoke: N/A** — this feature ships no binary, engine, server, or container; it is prose-only skill Markdown (`commands/end-session.md`) plus a manual validation-matrix `.md`. There is no executable artifact to smoke-launch. Validation is the manual matrix walkthrough in Task 3, matching the established precedent for prose-behavior features in this repo (`2026-05-21-end-session-heuristics.md`).

## Global Constraints

- Canonical file paths use `.session-continuity/` (v0.5.0+); the legacy `docs/` fallback still exists and MUST be preserved.
- Semantic versioning: bump `plugin.json` + add a `CHANGELOG.md` `[X.Y.Z]` block in the SAME commit as the feature. This is a minor feature → next minor bump from current `0.11.0` → `0.12.0`.
- Commit messages: conventional commits (`feat:`, `docs:`, `chore:`). No trailing co-author line unless requested.
- Never commit the primer alone. Skill edits are substantive changes and commit freely; if the primer is refreshed it rides with the substantive commit.
- **Never auto-close an outstanding item.** A verdict never mutates the primer on its own — this is the load-bearing invariant (spec decision #3), consistent with `commands/primer.md` Step 5.4 and the existing Step 1 overlay "Refusal" clause.
- **Evidence before assertion.** A `still-open` or `appears-DONE` verdict MUST carry a cited artifact (`file:line`, grep count, or glob result). No evidence → `manual`.
- Spec: `meta/superpowers/specs/2026-07-30-outstanding-items-verification-design.md`.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `commands/end-session.md` | The end-session ritual prose | Modify: add verification sub-block to Step 1; add checklist row + update example/Notes in Step 3 |
| `plugin.json` | Version manifest | Modify: `0.11.0` → `0.12.0` |
| `CHANGELOG.md` | Release log | Modify: add `[0.12.0]` block |
| `meta/superpowers/validation/2026-07-30-outstanding-items-verification.md` | Manual validation matrix | Create |
| `.session-continuity/SESSION_PRIMER.md` | Project primer | Modify: refresh current-state + log block, ride with the feature commit |

Tasks are drawn so a reviewer can accept the Step 1 verification logic independently of the Step 3 reporting row, and the validation matrix independently of both.

---

## Task 1: Step 1 verification sub-block (classify + verify + route)

Add the verification behavior to `commands/end-session.md`, placed at the TOP of Step 1 (before the drift check), with routing of `appears-DONE` candidates into the existing combined prompt.

**Files:**
- Modify: `commands/end-session.md` — insert a new sub-section after the Step 1 heading (line 33 `## Step 1 — Refresh the primer (drift-gated)`), before `### Drift check` (line 37).

**Interfaces:**
- Consumes: the primer read that Step 1 already performs for the drift check; the existing `## Outstanding items` heading + numbered-item tokenization/scoping rule from the Step 1 overlay (numbered line + indented continuation up to the next top-level number; sub-bullets roll up to parent).
- Produces: a set of per-item verdicts `{still-open | appears-DONE | manual}` with cited evidence, held for reuse by Step 3 (Task 2). The `appears-DONE` subset is appended to the outstanding-items overlay candidate list consumed by Step 1's combined prompt.

- [ ] **Step 1: Write the failing check (validation walkthrough case, added to the matrix stub)**

Before editing the skill, write the expected-behavior assertion this task must satisfy, in a scratch note (folded into Task 3's log later). The two cases that MUST hold:

```
Case A (drift detected): primer has an appears-DONE item (item 4 grep hooks/ → 0 hits
  after a hypothetical removal). Refresh flow fires. Assert: item 4 appears in the
  combined prompt's candidate list as a close-candidate with cited evidence.

Case B (drift-clean): same primer, log block matches HEAD. Refresh flow skipped.
  Assert: NO prompt fires; verification still ran; item 4's appears-DONE verdict is
  held for Step 3 only.
```

- [ ] **Step 2: Verify it fails**

Read the current `commands/end-session.md` Step 1 (lines 33–79). Confirm there is NO verification of outstanding items against code today — only the drift check and the token-overlap overlay (which matches commit subjects to items, not code state). Case A and Case B both currently produce "no verification" → the behavior is absent → fails.

- [ ] **Step 3: Write the verification sub-block**

Insert immediately after the Step 1 heading and its one-line intro, before `### Drift check`:

````markdown
### Outstanding-items verification (runs first, unconditionally)

Before the drift check, verify the primer's outstanding items against actual
repo state. This runs on EVERY invocation — drift-clean or not — because a
stale item can outlive a drift-clean primer. Compute each verdict once here;
Step 3 reuses these verdicts.

**Skip conditions.** If the primer has no `^## Outstanding items` heading
(custom-modified primer), skip verification silently — the Step 3 row will
read `Outstanding items: none tracked`. Likewise if the section is empty.

**For each top-level numbered item** under `## Outstanding items` (scope the
item exactly as the overlay does: the numbered line plus indented continuation
lines until the next top-level number; sub-bullets roll up to their parent):

1. **Classify — code-verifiable or not.** An item is code-verifiable if a
   `grep`/`glob`/file-exists check *could* speak to it (it names a file, a
   hook path, a test harness, a LEARNINGS title, a code construct).
   Classification is binary: low-confidence code items (a grep exists but the
   match may be ambiguous) still classify AS code-verifiable — they resolve to
   `manual` below when evidence is insufficient. Items naming an external
   action or a parked decision (marketplace submission, rejected
   recommendations) are non-code.

2. **Verify code items** with a derived `grep`/`glob`/file-exists check via
   Bash. Assign one verdict:
   - **`still-open`** — the artifact is absent as the item expects. Cite the
     negative check (e.g. "no `*.bats` and no `test/` dir → item still open").
   - **`appears-DONE`** — the artifact is present/absent in a way that proves
     resolution. Cite the artifact (`file:line`, grep count, glob result).
   - **`manual`** — no unambiguous evidence found (ambiguous grep — a match
     inside a comment or a doc reference rather than a live code path). **Bias
     toward `manual` over a false `appears-DONE`.**

3. **Non-code items** → verdict `manual`, printed as
   `manual — not auto-verifiable`. Never assert done or open.

**Evidence rule.** A `still-open` or `appears-DONE` verdict MUST carry a cited
artifact. Absent evidence downgrades the verdict to `manual`. This is the same
gate the plugin enforces on "proven" claims elsewhere.

**Routing `appears-DONE` candidates.** These are close-candidates — **never
auto-removed**.

- **When the drift check below enters the refresh flow** (drift detected):
  append every `appears-DONE` item to the existing outstanding-items overlay
  candidate list, so it surfaces at Step 1's single combined prompt. One reply
  closes it. Cite the evidence beside the candidate.
- **When the primer is drift-clean** (refresh flow skipped, no prompt fires):
  do NOT force a prompt — that would break the "drift-clean + zero candidates =
  zero prompts" guarantee. The `appears-DONE` item surfaces only as a ⚠️ in the
  Step 3 checklist row. Across repeated drift-clean sessions the same item
  re-flags every time until a drift-bearing session (or a manual `/primer`
  refresh) gives the user a prompt to close it — intentional; the ⚠️ is a
  standing reminder, and closing is deferred, never blocked.

Removal of any item always requires explicit user confirmation. A verdict never
mutates the primer on its own.
````

Then, in the existing `### Refresh flow` overlay step (currently line ~52–70, the "Surface commits since the last primer refresh, with outstanding-items overlay" bullet), add one sentence so the two candidate sources are unified:

```markdown
   In addition to token-overlap matches from commit subjects, include any
   `appears-DONE` items from the Outstanding-items verification sub-block above
   as close-candidates in this same overlay (cite their code evidence).
```

- [ ] **Step 4: Verify it passes (walkthrough)**

Re-read the edited Step 1. Walk Case A: primer with an `appears-DONE` item + drift present → the sub-block computes the verdict, the refresh-flow overlay bullet now names it as a candidate → surfaces at the combined prompt. Walk Case B: same primer, drift-clean → sub-block runs, refresh flow skipped, no prompt, verdict held. Both assertions hold.

- [ ] **Step 5: Commit**

```bash
git add commands/end-session.md
git commit -m "feat(end-session): verify outstanding items against code (Step 1)

Classify each primer outstanding item code/non-code, verify code ones with
a cited grep/glob/file-exists check, and route appears-DONE items into the
existing combined prompt as close-candidates when the refresh flow fires.
Runs above the drift branch so it executes even when drift-clean; verdict
never mutates the primer (never-auto-close invariant)."
```

---

## Task 2: Step 3 checklist row (re-derive post-edit) + example + Notes

Add the `Outstanding items` reporting row to the Final checklist, update the checklist table, the worked example, and the Notes section.

**Files:**
- Modify: `commands/end-session.md` — the Step 3 checklist table (line ~320–328), the "Gather the facts" list (line ~299–306), the "Example output" block (line ~342–351), and the Notes list (line ~373+).

**Interfaces:**
- Consumes: the per-item verdicts computed in Task 1's Step 1 sub-block; the post-edit primer (after any Step 1 closures the user confirmed).
- Produces: one new checklist row with a ✓/⚠️ marker and per-item verdict summary.

- [ ] **Step 1: Write the failing check (validation case)**

Expected behavior to assert (folded into Task 3's matrix):

```
Case C (post-edit re-derivation): primer starts with 5 items, one appears-DONE (#4).
  Drift present → user closes #4 at the Step 1 prompt. Assert: Step 3 row re-reads
  the primer, reports 4 items (not 5), #4 absent, marker checkmark (no appears-DONE left).

Case D (stale lingering, drift-clean): 5 items, #4 appears-DONE, drift-clean → no
  prompt. Assert: Step 3 row reports 5 items, #4 flagged appears-DONE, marker warning.
```

- [ ] **Step 2: Verify it fails**

Read the current Step 3 checklist table (lines ~320–328). Confirm there is NO `Outstanding items` row today — the table has Primer refresh / New learnings / Staged / Unstaged / Untracked / Unpushed / Suggested commit rows only. Cases C and D have nowhere to report → fails.

- [ ] **Step 3: Add the checklist row**

In the Step 3 checklist table, add this row after the `New learnings` row and before `Staged files`:

```markdown
| Outstanding items | checkmark if none stale, else warning | "N tracked — <k> appears-DONE (#X, evidence), <m> still-open (#…), <j> manual (#…)" OR "none tracked" |
```

Immediately after the table, add a paragraph:

````markdown
**Outstanding-items row — re-derive, do not cache.** Step 3 re-reads the
`## Outstanding items` section from the primer AFTER any Step 1 closures the
user confirmed. The *set* of items and the counts are recomputed against the
post-edit primer; only the per-item verdicts (`still-open` / `appears-DONE` /
`manual`) computed in Step 1 are reused. If the user closed an item at the Step
1 prompt, it is gone from the primer and absent from this row. Marker: ✓ if
every remaining item is `still-open` or `manual` (nothing stale lingering);
⚠️ if any remaining item is `appears-DONE` (a resolved item still listed).
Cite the evidence for each `appears-DONE` item inline.
````

- [ ] **Step 4: Update "Gather the facts"**

In the "Gather the facts" list (line ~299), add a note that the outstanding-items verdicts come from Step 1, not a fresh git command:

```markdown
- **Outstanding-items verdicts** — reuse the per-item verdicts from Step 1's
  verification sub-block; re-read the primer's `## Outstanding items` section to
  get the post-edit item set. No new git command — the evidence was already
  gathered in Step 1.
```

- [ ] **Step 5: Update the Example output**

Replace the existing example block (lines ~342–351) so it includes the new row (self-consistent counts: 5 tracked, one appears-DONE lingering under drift-clean):

````markdown
```
✓ Primer refreshed and staged
✓ 1 LEARNINGS entry captured (#7, "awk range collapse on single-version CHANGELOG")
⚠️ Outstanding items: 5 tracked — 1 appears-DONE (#4, "drop docs/ fallback": grep hooks/ for 'docs/' → 0 hits after removal), 1 still-open (#3), 3 manual (#1, #2, #5)
✓ Staged: .session-continuity/SESSION_PRIMER.md, .session-continuity/LEARNINGS.md, .github/workflows/release.yml
✓ No unstaged modifications
⚠️ 2 untracked files: scratch.md, tmp/debug.log — ignore, add, or delete?
⚠️ Branch "main" is 3 commits ahead of origin — push before closing?
→ Suggested:
    git commit -m "fix(ci): extract CHANGELOG section with proper awk range"
```
````

- [ ] **Step 6: Update the Notes section**

Add one bullet to the Step 4 Notes list (line ~373+):

```markdown
- **Outstanding-items verdicts never mutate the primer.** The verification in
  Step 1 only classifies and reports; an `appears-DONE` item is removed only if
  the user confirms it at the Step 1 prompt. A drift-clean session surfaces a
  stale item as a standing ⚠️ in the checklist, never as a silent deletion.
```

- [ ] **Step 7: Verify it passes (walkthrough)**

Walk Case C: 5 items, close #4 at prompt → Step 3 re-reads primer → 4 items, checkmark. Walk Case D: 5 items, drift-clean, #4 appears-DONE → row shows 5 items, warning. Both hold against the edited prose.

- [ ] **Step 8: Commit**

```bash
git add commands/end-session.md
git commit -m "feat(end-session): report outstanding-items verdicts in Step 3 checklist

Add an Outstanding-items row to the Final checklist. Re-derives the item set
from the post-edit primer (reusing Step 1 verdicts, not cached counts);
checkmark when nothing stale, warning when an appears-DONE item still lists.
Updates the worked example and Notes."
```

---

## Task 3: Validation matrix + version bump + primer refresh

Write the manual validation log, bump the version, add the CHANGELOG block, refresh the primer, and run the in-repo manual check. This is the deliverable that proves the feature holds end-to-end.

**Files:**
- Create: `meta/superpowers/validation/2026-07-30-outstanding-items-verification.md`
- Modify: `plugin.json` (`0.11.0` → `0.12.0`)
- Modify: `CHANGELOG.md` (add `[0.12.0]` block)
- Modify: `.session-continuity/SESSION_PRIMER.md` (refresh current-state + log block)

**Interfaces:**
- Consumes: the edited `commands/end-session.md` from Tasks 1–2.
- Produces: a filled validation matrix covering Cases A–D plus the never-auto-close invariant case; a shipped v0.12.0.

- [ ] **Step 1: Write the validation matrix log**

Create `meta/superpowers/validation/2026-07-30-outstanding-items-verification.md`, modeled on `2026-05-21-end-session-heuristics.md`. It MUST contain these scenarios, each with Setup / Expected / Actual / Result:

```
Scenario 1 — Case A: drift detected, appears-DONE item routes to the combined prompt as a close-candidate with cited evidence.
Scenario 2 — Case B: drift-clean, verification runs, no prompt, verdict held for Step 3 only.
Scenario 3 — Case C: user closes an appears-DONE item at the prompt, then Step 3 re-derives, item absent, marker checkmark.
Scenario 4 — Case D: drift-clean stale item, Step 3 reports it, marker warning, no deletion.
Scenario 5 — never-auto-close invariant: appears-DONE item + "no changes" reply, item STILL present in primer afterward, Step 3 still warning appears-DONE. A verdict must never mutate the primer on its own.
Scenario 6 — non-code item (marketplace submission): verdict manual — not auto-verifiable, never asserted.
Scenario 7 — ambiguous grep (match inside a comment): manual, not appears-DONE (bias rule).
Scenario 8 — no Outstanding items heading: verification skipped, row reads "none tracked".
```

Fill Setup and Expected for each. Leave Actual/Result as `_(filled at validation time)_` markers, matching the precedent log's format.

- [ ] **Step 2: Run the in-repo manual check**

Run the real check the spec calls for and record it in the matrix Actual field:

```bash
grep -rn 'docs/' hooks/ | wc -l
```

Expected: `>0` (the `docs/` fallback is deliberately kept until v1.0.0) → item 4 verdict is `still-open` today, NOT `appears-DONE`. Record the actual count in the matrix.

- [ ] **Step 3: Bump version + CHANGELOG**

Edit `plugin.json`: `"version": "0.11.0"` → `"0.12.0"`. Add a `CHANGELOG.md` `[0.12.0]` block:

```markdown
## [0.12.0]

### Added
- `/session-continuity:end-session` now verifies the primer's outstanding items
  against actual repo state. Each item is classified code-verifiable or not;
  code items get an evidence-gated `grep`/`glob`/file-exists check with a
  `still-open` / `appears-DONE` / `manual` verdict. `appears-DONE` items surface
  as close-candidates at Step 1's existing combined prompt (when drift fires) or
  as a standing warning in the new Step 3 checklist row (when drift-clean).
  Verdicts never auto-close an item — removal always requires explicit user
  confirmation.
```

- [ ] **Step 4: Refresh the primer**

Update `.session-continuity/SESSION_PRIMER.md`: regenerate the `git log --oneline -5` block against the current branch, and add a v0.12.0 current-state bullet describing this feature as shipped. Stage it to ride with this commit (never a primer-only commit).

- [ ] **Step 5: Verify (self-review the matrix against the edited skill)**

Re-read Tasks 1–2 prose and confirm every Scenario 1–8 Expected is actually produced by the prose. Any mismatch → fix the prose (loop back to the relevant task), not the matrix.

- [ ] **Step 6: Commit**

```bash
git add plugin.json CHANGELOG.md meta/superpowers/validation/2026-07-30-outstanding-items-verification.md .session-continuity/SESSION_PRIMER.md
git commit -m "docs: v0.12.0 validation matrix + version bump for outstanding-items verification

Manual validation matrix (8 scenarios incl. never-auto-close invariant),
plugin.json 0.11.0 -> 0.12.0, CHANGELOG [0.12.0] block, primer refresh."
```

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| Classify code / non-code | Task 1 Step 3 (classify) |
| LLM-derived check, evidence-gated | Task 1 Step 3 (verify + evidence rule) |
| Surface as close-candidate, never auto-close | Task 1 Step 3 (routing) + Task 2 Step 6 (Notes) + Task 3 Scenario 5 |
| Verdicts (still-open / appears-DONE / manual) | Task 1 Step 3 |
| Placement above drift branch | Task 1 Step 3 (sub-block placement) |
| Drift-clean → no prompt, standing warning | Task 1 Step 3 (routing) + Task 3 Scenario 4 |
| Step 3 re-derives post-edit | Task 2 Step 3 |
| New checklist row + marker | Task 2 Step 3 + Step 5 |
| Edge: no heading / zero items | Task 1 Step 3 (skip conditions) + Task 3 Scenario 8 |
| Edge: sub-bullet scoping | Task 1 Step 3 (scope rule) |
| Edge: ambiguous grep → manual | Task 1 Step 3 (bias rule) + Task 3 Scenario 7 |
| Validation (fixture + never-auto-close + manual in-repo) | Task 3 |

No gaps.

**2. Placeholder scan:** The validation log's `Actual/Result` fields are deliberate `_(filled at validation time)_` markers matching the established precedent — these are runtime-recorded, not plan placeholders. All prose inserts contain the actual verbatim text to add. No "TBD"/"handle edge cases"/"similar to Task N".

**3. Type consistency:** Verdict labels `still-open` / `appears-DONE` / `manual` are spelled identically in Task 1 (definition), Task 2 (row + example), and Task 3 (scenarios). "Outstanding-items verification" sub-block name is consistent across Task 1 and Task 2's cross-references. Version `0.11.0 → 0.12.0` consistent in Task 3 Steps 3–6.

---

## Execution Handoff

Plan complete. Two execution options — see below.
