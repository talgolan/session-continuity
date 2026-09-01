# Backlog — session-continuity

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

### 1. [d7f5] [2026-08-30] Submit to the Anthropic marketplace

Form answers in `meta/administrative/marketplace-submission.md` (version
field synced to 0.14.0 in the docs-accuracy sweep on 2026-08-13 —
re-check against `.claude-plugin/plugin.json` at actual submission time,
this field drifts every release).

### 2. [8906] [2026-08-30] Automated integration tests

Manual validation only right now — no bats-style shell test harness
exercises the slash commands against a fixture repo. Good candidates:
Split mode in `commands/primer.md`, the `learning`-skill
duplicate-detection guard, v0.14.2's end-session fast-path/overlap-gate
logic, and v0.14.4's test-count skip/escalate logic — none exercise the
nothing-changed / touched / untouched, or no-relevant-file-changed /
changed-but-count-holds / genuinely-drifted cases beyond prose review.

### 3. [6176] [2026-08-30] Scratch-project smoke test for the primer split (deferred from this session)

The v0.13.0 implementation plan's Task 6 validated the split mechanically
against this repo's own files but explicitly deferred the spec's Testing
items 1-2 (fresh init in a scratch project, and Split mode against a
throwaway unsplit primer) since they need a directory outside this repo.
Also covers the Init-mode enrichment's test-run/`{{MODULES_TABLE}}`/
`{{WORKFLOW_CONVENTIONS}}` derivations (v0.18.0), none of which has run
end-to-end against a real fresh repo yet either. Run all of it before the
next `/session-continuity:primer` change lands.

### 4. [9eec] [2026-08-30] Global docs-current hooks check "touched," not "accurate" — generalize the existing pass-count mechanism

Neither `~/.githooks/pre-commit` nor the global Claude Code `Stop` hook
checks whether a doc's claims stay *true* — both only check whether a doc
file was touched, with one hard-coded exception (the primer's `"NN pass"`
count check). Invariant (CLAUDE.md rule 4): every count or
named-entity-list claim in shipped docs must match actual repo state at
commit time, enforced at the gate that runs on every commit. Design:
`meta/superpowers/recommendations/docguard-design-sketch.md`.

### 5. [e8e2] [2026-09-01] `agent-active.sh` fallback treats every transcript as if it has `turn_duration` records

From v0.23.0's cost-attribution work, deferred by that implementation's
final review (Ready to merge: Yes) as a narrow, non-blocking edge case.
The fallback mechanism (used only when a transcript has zero
`turn_duration` records) has an unreachable "skip if earlier record is
turn_duration" clause — it always sums unconditional wall-clock time,
silently reintroducing idle-as-compute for that minority of transcripts.
Needs a real assistant-close→gap→next-user boundary walk; this is a
**spec amendment** (the current fallback is inherited verbatim from the
approved spec), not a silent code patch — re-review before changing it.
(The sibling items in this entry — `learning.md`'s empty-`$REPORT` gap and
`end-session.md`'s stale Heuristics prose — were resolved by the LEARNINGS
generation hardening plan, v0.25.0.)

### 6. [6258] [2026-09-01] `2026-08-12-session-start-smoke.zsh` tests a pre-v0.22.0 contract — 7/17 assertions fail

Confirmed on a clean `main` worktree (zero diff in either the test or
`hooks/session-start.sh`): the test's fixtures write
`.session-continuity/OUTSTANDING_ITEMS.md` expecting the hook to list its
items directly, but the hook — unchanged since before this finding, so
this isn't a regression from any recent work — now treats *any*
`OUTSTANDING_ITEMS.md` presence as stale-format and always emits a
migration-to-`BACKLOG.md` nudge instead, per the v0.22.0 rename. The test
was never updated to match. Fix: rewrite the failing fixtures to use
`BACKLOG.md` (matching the hook's actual current contract), or fold this
into item 2 (automated integration tests) if that work supersedes it.

### 7. [c9a4] [2026-09-01] `overlap()` dedup in `candidate-extract.jq` is an asymmetric, multiplicity-vs-dedup-mismatched Jaccard, and over-merges distinct retry-bursts

Deferred by the LEARNINGS generation hardening plan's (v0.25.0) Task 4 and
final reviews as a real defect in verbatim, evidence-validated code —
non-blocking (conservative failure: fewer candidates shown, never wrong
data) but confirmed live, not just synthetic. The numerator counts `$wa`'s
title words with multiplicity while the denominator is the deduplicated
union, so `overlap(A;B) != overlap(B;A)` and short/similar titles score
above the 0.7 dedup threshold when they shouldn't (`vitest`/`jest` scored
0.909). The final whole-branch review sharpened this: Task 4's uniform
title suffix (`— re-run N times with M file edits in between.`) means two
retry-bursts on genuinely different commands (e.g. `bun test src/foo…` vs
`bun test src/bar…`) score 0.722 — over threshold — so the second is
silently dropped before the per-heuristic cap even applies. Fix: a
symmetric, multiplicity-free Jaccard (dedupe `$wa`/`$wb` before comparing),
and/or exclude the common title-template suffix from the comparison so
only the command-specific portion is scored.
