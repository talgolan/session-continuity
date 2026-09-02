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

### 6. [6258] — closed. Fixed in `721b287`.

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
only the command-specific portion is scored. Fix it as part of Phase 5
`[c60e]`, which lifts this exact function into a script shared by
`primer.md` and `end-session.md` — sharing it unchanged multiplies the
defect's reach across two call sites instead of one.

### 8. [3b71] [2026-09-02] Determinism Phase 0 — fresh-install count defects

Two reproduced counting bugs affecting every new project: heading examples
inside the shipped templates are counted as real entries, and
`grep -c … || echo 0` prints two zeros when a count is genuinely zero.
Depends on nothing, ships as a patch release, and closes item `6258` — its
Task 2 repairs that smoke suite. Plan:
`meta/superpowers/plans/2026-09-02-fresh-install-count-defects.md`.

### 9. [5c2d] [2026-09-02] Determinism Phase 1 — zero-turn read-only lists

Retires the model from `/backlog`, `/learnings`, `/help`, and `/update` via a
`UserPromptSubmit` interceptor and a shell renderer — the only phase that
reaches literally zero model calls, where the rest reduce turns and remove
error modes. Task 1 is a measurement gate probing four unprobed hook
behaviors, and a negative result there changes the approach before any code
lands. Plan:
`meta/superpowers/plans/2026-09-02-zero-turn-read-only-commands.md`.

### 10. [8e4a] [2026-09-02] Determinism Phase 2 — `end-session` Step 2 rendering and reference relocation

Largest single token reduction available: relocates the reference text that
`commands/end-session.md` itself marks as "**not instructions to you**" into
`skills/session-continuity/HEURISTICS.md`, and scripts the LEARNINGS-candidate
rendering. Depends on nothing; has an approved design but still needs an
implementation plan. Design:
`meta/superpowers/specs/2026-09-02-end-session-step2-rendering-design.md`.

### 11. [a17f] [2026-09-02] Determinism Phase 3 — shared mechanics library

Adds `perf-log.sh mark` and `perf-log.sh since` to collapse four
near-identical 14-line epoch-subtraction blocks inlined in
`commands/end-session.md`, plus one status function shared by
`hooks/session-start.sh`, `primer.md` check mode, and `doctor.md` so the three
can no longer disagree. Unblocks phases 4 and 6, and forces the decision filed
as item `4a9d`. Scope: the Phase 3 entry in
`meta/superpowers/specs/2026-09-02-determinism-program-design.md`; needs a plan.

### 12. [b93c] [2026-09-02] Determinism Phase 4 — `end-session` Step 3 checklist assembly

One script consuming the six git outputs and a `tag<TAB>verdict<TAB>citation`
file, emitting the eight finished rows, the four backlog tallies, the per-row
markers, and the sign-off boolean. Depends on Phase 3's `since`, and removes
the file-inventory summarization failure that `end-session.md:646` exists to
prevent. Scope: the Phase 4 entry in the program design; needs a plan.

### 13. [c60e] [2026-09-02] Determinism Phase 5 — backlog mechanics and the commit-overlap gate

Two scripts shared by `primer.md` and `end-session.md`: item bookkeeping (mint
a 4-hex tag with a uniqueness grep, stamp the date, renumber positions 1..N,
grep the repo for a tag before deletion) and the overlap gate, which today
exists as two prose copies that can drift. Must close item `c9a4` rather than
lift `candidate-extract.jq:101-107` unchanged — that function is the
asymmetric Jaccard `c9a4` documents. Scope: the Phase 5 entry in the program
design; needs a plan.

### 14. [d24b] [2026-09-02] Determinism Phase 6 — `primer` detect, migrate, init, drift

Mode detection and migration triggers (pure boolean logic over file
existence), the backlog rename migration's destructive `git mv`, init-mode
template copy and placeholder substitution, and the drift check with modal
test-count pinning. Largest phase, lowest per-invocation frequency, highest
blast radius — it rewrites five files; depends on Phase 3. Scope: the Phase 6
entry in the program design; needs a plan.

### 15. [f58a] [2026-09-02] Determinism Phase 7 — the commit gate that keeps the invariant true

A seventh gate in `hooks/hooks.json` blocking staged `commands/*.md` text that
instructs a model to count, tally, renumber, compute a duration, compare a
claimed value against an actual one, or print fixed text verbatim, with the
usual `<Gate-name>: N/A — <reason>` escape. Ships last so its pattern list is
written from what the earlier phases actually removed; it is distinct from
item `9eec`, a machine-global claimed-value gate living outside this repo, and
neither closes the other. Scope: the Phase 7 entry in the program design;
needs a plan.

### 16. [4a9d] [2026-09-02] Decide whether `/doctor` becomes a zero-turn script or stays a prompt

Its five report rows are deterministic and Phase 1 `[5c2d]` would leave a
zero-turn mechanism available to reuse, but its install-mode branching reads
environment rather than repo files. Decide during Phase 3 `[a17f]`, when the
shared status function forces the question.
