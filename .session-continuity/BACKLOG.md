# Backlog — session-continuity

Explicitly deferred follow-ups and decisions — not bugs (those
go in `.session-continuity/LEARNINGS.md`), not current state (that's
`.session-continuity/SESSION_PRIMER.md`). An item lives here from the
moment it's flagged until the moment the code proves it resolved, then
it's deleted outright — the closing commit is the historical record, not
this file.

**Numbering is permanent.** A new item takes the next unused number;
closed items are deleted, never renumbered, never reused. Cross-references
("see item 4") stay valid as long as item 4 exists. Before deleting a
closed item, grep the whole repo for references to its number (e.g.
`\bitem #?4\b`, `outstanding item(s)? 4`) — a hit means fix the
referencing text or leave the closed item as a one-line "closed" stub
instead of deleting it.

**Length cap.** Each item is a title plus 1-3 sentences. If it needs a
design sketch, an invariant, or a rejected-alternatives discussion, put
that in a spec under `meta/superpowers/...` and link it here — this file
stays a scannable list, not a second spec repository.

### 1. Submit to the Anthropic marketplace

Form answers in `meta/administrative/marketplace-submission.md` (version
field synced to 0.14.0 in the docs-accuracy sweep on 2026-08-13 —
re-check against `.claude-plugin/plugin.json` at actual submission time,
this field drifts every release).

### 2. Automated integration tests

Manual validation only right now — no bats-style shell test harness
exercises the slash commands against a fixture repo. Good candidates:
Split mode in `commands/primer.md`, the `learning`-skill
duplicate-detection guard, v0.14.2's end-session fast-path/overlap-gate
logic, and v0.14.4's test-count skip/escalate logic — none exercise the
nothing-changed / touched / untouched, or no-relevant-file-changed /
changed-but-count-holds / genuinely-drifted cases beyond prose review.

### 3. Scratch-project smoke test for the primer split (deferred from this session)

The v0.13.0 implementation plan's Task 6 validated the split mechanically
against this repo's own files but explicitly deferred the spec's Testing
items 1-2 (fresh init in a scratch project, and Split mode against a
throwaway unsplit primer) since they need a directory outside this repo.
Also covers the Init-mode enrichment's test-run/`{{MODULES_TABLE}}`/
`{{WORKFLOW_CONVENTIONS}}` derivations (v0.18.0), none of which has run
end-to-end against a real fresh repo yet either. Run all of it before the
next `/session-continuity:primer` change lands.

### 4. Global docs-current hooks check "touched," not "accurate" — generalize the existing pass-count mechanism

Neither `~/.githooks/pre-commit` nor the global Claude Code `Stop` hook
checks whether a doc's claims stay *true* — both only check whether a doc
file was touched, with one hard-coded exception (the primer's `"NN pass"`
count check). Invariant (CLAUDE.md rule 4): every count or
named-entity-list claim in shipped docs must match actual repo state at
commit time, enforced at the gate that runs on every commit. Design:
`meta/superpowers/recommendations/docguard-design-sketch.md`.

### 6. `agent-active.sh` fallback + `learning.md` empty-`$REPORT` gap, plus doc staleness cleanup

Both from v0.23.0's cost-attribution work, deferred by that implementation's
final review (Ready to merge: Yes) as narrow, non-blocking edge cases:
(a) `hooks/lib/agent-active.sh`'s fallback mechanism (used only when a
transcript has zero `turn_duration` records) has an unreachable "skip if
earlier record is turn_duration" clause — it always sums unconditional
wall-clock time, silently reintroducing idle-as-compute for that minority
of transcripts. Needs a real assistant-close→gap→next-user boundary walk;
this is a **spec amendment** (the current fallback is inherited verbatim
from the approved spec), not a silent code patch — re-review before
changing it. (b) `commands/learning.md` Step 4 has no explicit "stop if
`$REPORT` is empty" instruction on a `require_script` failure (script
missing/outdated) — could compute a wrong next-entry number in that narrow
version-skew window; the existing "must not already appear in the file"
check only catches an already-used number, not an unused-but-wrong one.
(c) `commands/end-session.md`'s untouched `### Heuristics`/Step-2-intro
prose ("computed once above", agent-side dedup/cap language) still
describes the pre-refactor execution flow now living in
`candidate-extract.jq`; `CHANGELOG.md`'s `[0.23.0]` entry says the fallback
does "a timestamp turn-boundary walk," which is accurate as intent but not
as shipped behavior per (a) — reword once (a) is actually fixed.
