# Plan: fix evidence-gate.sh's smoke/poll false positive + the shared gate-common.sh escape-hatch reliability bug (also hits proven-gate.sh)

> **Superseded disposition — read the eval first.** Every claim below was
> reproduced against the live hooks on 2026-09-10; see
> [`../specs/2026-09-10-gate-escape-hatch-and-smoke-scope-eval.md`](../specs/2026-09-10-gate-escape-hatch-and-smoke-scope-eval.md).
> Summary: Tasks 1–2 are valid, with two corrections (drop the section-narrowing
> refinement; scope the trigger greps to the window but leave the satisfaction
> greps whole-file). Task 3 must not be executed as written — there is no
> divergence in `gate_has_escape` to find. Its Symptom A is escape-line
> separator grammar and its Symptom B is already mitigated by
> `gate_mask_escape`. The eval names the replacement work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (or lean SDD) to implement this
> plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Repo:** `session-continuity-plugin` (NOT this repo) — dev checkout at
`~/active_development/TG/session-continuity-plugin`. This plan lives on
`architect-workbench` because that is where the bug was found and
reproduced live on 2026-09-10; the actual fix commit belongs in the plugin
repo, not here. Plan-only doc — no separate spec; the fix is small and the
reproduction below stands in for a design writeup.

**Goal (two bugs, one plan):**

1. `hooks/evidence-gate.sh`'s two checks (teardown-before-diagnostic,
   dual-signal poll) currently scope on "does the WHOLE staged file mention
   `smoke` anywhere" and then independently "does the WHOLE file mention
   `poll`/`teardown` anywhere" — with no requirement that the two occur near
   each other. A doc that mentions "smoke" in one unrelated sentence and
   "poll" in another (e.g. a filename like `pollRoute.test.ts`, or a table
   row "No poll/ack WS") gets denied for a smoke-section problem it does
   not actually have. Fixed by Tasks 1–2.
2. `gate_has_escape` (`hooks/lib/gate-common.sh`) does not reliably
   short-circuit a gate check even when a correctly formatted escape line
   is present in the staged content. This is the same mechanism
   `proven-gate.sh`'s documented §4 hazard describes — "the gate can deny a
   doc whose ONLY trigger word is its own escape line" — and it was
   independently reproduced live against `evidence-gate.sh` during this
   plan's own reproduction below. Both symptoms point at the same shared
   `gate_has_escape`/`gate_load` machinery, not two unrelated bugs. Fixed by
   Task 3.

Proven-gate: N/A — this plan describes work to do, not a live-path claim.
Evidence-gate: N/A — this plan describes work to do, not a live-run claim.

**Reproduction (architect-workbench, 2026-09-10):** staging
`docs/superpowers/plans/2026-09-08-local-workbench.md` with an unrelated
one-paragraph addition was denied repeatedly, citing "the smoke section
mentions a poll/wait loop" — that file's only such-flagged word occurrences
are `pollRoute.test.ts` and a route-count table row; its "smoke" mentions
are in an unrelated file-deletion list elsewhere in the doc. No section in
that file actually describes a smoke-test poll loop. A correctly-formatted
`Evidence-gate: N/A — <reason>` escape line did not reliably suppress the
denial across several retries in the live hook process. (Real path: ran
`gate_has_escape` from the real `gate-common.sh` directly against the exact
staged git blob content in a plain bash shell — the byte sequence matched
its regex on inspection. Stubbed: the full PreToolUse hook invocation itself
— stdin JSON payload parsing and `GATE_CWD` resolution were not exercised,
only the matching function in isolation.) That second anomaly is real but
separate from the scoping bug this plan fixes; see Task 3.

**Architecture:** `hooks/evidence-gate.sh` sources `hooks/lib/gate-common.sh`
(the same escape/mask helper library `proven-gate.sh` uses). Current
`gate_check` shape:

```bash
gate_check() {
  local content="$1" path="$2"
  printf '%s' "$content" | grep -Eiq 'smoke' || return 0
  if gate_has_escape "$content" "Evidence-gate"; then return 0; fi
  if printf '%s' "$content" | grep -Eiq 'teardown|tear down|cleanup|clean up'; then
    if ! printf '%s' "$content" | grep -Eiq '<preserve-language>'; then deny "…"; fi
  fi
  if printf '%s' "$content" | grep -Eiq 'poll|wait[_-]?for|readiness check|timeout loop'; then
    if ! printf '%s' "$content" | grep -Eiq '<dual-signal-language>'; then deny "…"; fi
  fi
}
```

Both trigger checks run against `$content` — the whole file — not a window
around the actual smoke section the scope check found.

`proven-gate.sh` calls the same escape helper (relevant to Task 3, not the
smoke-scope fix):

```bash
gate_check() {
  local content="$1" path="$2"
  if gate_has_escape "$content" "Proven-gate"; then return 0; fi
  local scan; scan="$(gate_mask_escape "$content" "Proven-gate")"
  # ...bare-word scan against $scan, masked-but-not-removed escape lines...
}
```

`gate_has_escape` itself (`hooks/lib/gate-common.sh`):

```bash
gate_has_escape() {  # <text> <Label> -> true if an escape line is present
  printf '%s' "$1" \
    | sed -E 's/[`*]//g' \
    | grep -Eiq "$2:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]"
}
```

This is the shared function Task 3 investigates.

**Fix:** scope the trigger checks to text near a `smoke` mention, not the
whole file. Primary mechanism, always applied: a fixed ±20-line window
around each line matching `smoke`. Refinement on top of that: if the
nearest enclosing markdown section (nearest preceding `^#` heading to the
next heading of equal-or-shallower level) is SMALLER than the ±20-line
window, use the section bounds instead — this only ever narrows the
window, never widens it past 20 lines, so the two mechanisms never
disagree on which is authoritative. Concatenate all such windows into
`scoped`, and run every trigger check against `scoped` instead of
`content`. A file that merely mentions "smoke" and "poll" in unrelated,
non-adjacent places no longer trips either check; a file with a real
smoke section describing an unsafe teardown or a success-only poll still
does.

---

### Task 1: Add a section-scoping helper (TDD)

**Files:**
- Modify: `hooks/lib/gate-common.sh` — add `gate_window_around` (naming
  free to change). Shared helper, not evidence-gate-specific: `proven-
  gate.sh` and `smoke-gate.sh` have the same whole-file-scope shape and are
  candidates to adopt it later — landing it in `gate-common.sh` rather than
  inline in `evidence-gate.sh` avoids a second copy when that happens.
- Check first: does a test harness already exist for these hook scripts?
  (`meta/superpowers/validation/2026-08-27-gate-common-smoke.zsh` showed up
  in the plugin's cached listing — read it before inventing a new pattern.)

- [ ] **Step 1:** Write a case: given a synthetic multi-paragraph fixture
  where a "smoke" line and a far-away, unrelated "poll" line sit more than
  the window size apart, `gate_window_around "$content" 'smoke' 20` returns
  text that does NOT contain the far-away "poll" line.
- [ ] **Step 2:** Implement `gate_window_around` — line-number-based
  (`grep -n` for the pattern, `sed -n "${lo},${hi}p"` per match). Merge
  overlapping ranges: sort the `(lo, hi)` pairs by `lo`, then walk the
  sorted list coalescing any pair whose `lo` falls inside the previous
  pair's `[lo, hi]` into one wider range — so a file with many "smoke"
  mentions produces one deduplicated, gap-free windowed text, not
  duplicated or interleaved output.
- [ ] **Step 3:** Run the existing `gate-common.sh` validation script(s) —
  confirm still green before touching `evidence-gate.sh` itself.

### Task 2: Rewire `evidence-gate.sh` to scan the window, not the whole file

**Files:**
- Modify: `hooks/evidence-gate.sh`

- [ ] **Step 1:** Compute `scoped="$(gate_window_around "$content" 'smoke' 20)"`
  once, near the top of `gate_check`, right after the existing whole-file
  `smoke` scope gate. Replace both trigger checks' `$content` with
  `$scoped` — copy the exact regexes already live in `hooks/evidence-
  gate.sh` (the teardown/preserve-language pattern and the poll/dual-
  signal pattern; see the "Architecture" section above for their current
  form) rather than re-deriving them, so the only thing that changes is
  which text they scan. Keep the outer `smoke` scope gate and the
  `gate_has_escape` check against the full `$content` unchanged — an
  escape line should be allowed to sit anywhere in the file, not only
  inside the window.
- [ ] **Step 2:** Regression fixture: a doc with a REAL smoke section that
  DOES describe an unsafe teardown or a success-only poll still denies —
  confirms the fix narrows scope without defanging the real checks.
- [ ] **Step 3:** New fixture mirroring the architect-workbench
  reproduction above (unrelated far-apart "smoke" and "poll" mentions) no
  longer denies.

### Task 3: Fix the shared `gate_has_escape` reliability bug (hits both evidence-gate.sh AND proven-gate.sh)

**Two known symptoms of one suspected root cause — not fixed by Tasks 1–2.**

- **Symptom A (evidence-gate.sh, reproduced live 2026-09-10):** a byte-
  checked, correctly formatted `Evidence-gate: N/A` line did not reliably
  suppress the live denial during reproduction, even though
  `gate_has_escape` matched cleanly in isolation against the exact staged
  blob (`git show :path`, run outside the hook process).
- **Symptom B (proven-gate.sh's documented §4 hazard):** "the gate can
  deny a doc whose ONLY trigger word is its own escape line" — a
  `Proven-gate: N/A — <reason>` line contains the bare word "proven" (the
  hyphen in `Proven-gate` is a word boundary), so if `gate_has_escape`
  fails to short-circuit for the same underlying reason as Symptom A, the
  escape line becomes the file's own condemning evidence.

Both call the same `gate_has_escape`/`gate_load` machinery in
`hooks/lib/gate-common.sh`. The discrepancy points at something in the
real hook invocation — stdin JSON payload parsing, `GATE_CWD` resolution,
or interaction across the several gate hooks chained in `hooks.json` —
that a plain `git show :path` reproduction does not capture. Treat this as
ONE investigation with two regression fixtures, not two separate fixes.

- [ ] **Step 1:** Add opt-in debug logging (e.g. `GATE_DEBUG=1`) to
  `gate_scan_staged`/`gate_load` recording `GATE_CWD`, `GATE_COMMAND`, and
  the resolved staged-file list to a scratch file — silent by default.
- [ ] **Step 2:** Reproduce the original architect-workbench denial with
  `GATE_DEBUG=1` set; compare the logged `GATE_CWD`/staged content against
  what a manual `git -C <cwd> show :path` returns for the same attempt.
- [ ] **Step 3:** Once the divergence is located, fix it in
  `gate_has_escape`/`gate_load` (shared code — one fix covers both
  symptoms). Do not ship a fix that only adds more escape-line variants in
  the meantime — that was tried during reproduction and did not resolve
  Symptom A.
- [ ] **Done when:** both regression cases pass 5 times in a row with zero
  false denials, committed (not just dry-run):
  1. A staged doc for `evidence-gate.sh` carrying a correctly formatted
     `Evidence-gate: N/A — <reason>` line.
  2. A staged doc for `proven-gate.sh` whose ONLY "proven"/"verified"
     match is its own `Proven-gate: N/A — <reason>` escape line.
  If either still denies on any of the 5, the divergence isn't fixed yet —
  keep at Step 3.

---

**Cross-reference:** `proven-gate.sh`'s §4 hazard is documented separately
in `architect-workbench`'s `.session-continuity/COMMIT_HOOKS.md` §4 — that
doc's own "still open" note (added 2026-09-10, this session) should be
updated to point at Task 3 above once this plan's fix lands.
