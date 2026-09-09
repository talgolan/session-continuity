# Determinism program — Design

**Status:** approved scope. Phases 0 and 1 have plans, Phase 2 has a design
and needs a plan, phases 3-7 have neither.

Each phase is filed as its own GitHub Issue labeled `backlog`, identified
below by `#N`. Phase *ordering* lives in
`.session-continuity/ROADMAP.md`, not in those issues.

**Problem:** this plugin spends model turns computing values that are pure
functions of files, git state, and transcript data. It ships 94,350 bytes of
prompt text across seven command files, every byte of which is sent to a model
on invocation, and a large fraction of it is either reference documentation the
prompt itself marks as non-instructional, or mechanical work a shell script
would do faster and correctly.

**Goal:** the plugin consumes model turns only for irreducible judgment. Every
count, comparison, renumbering, duration, and list rendering is produced by a
script and passed through unchanged.

## The invariant

> No command prompt asks a model to compute a value that is a pure function of
> files, git state, or transcript data.

Enforced where new prompt text enters the repo, not by review discipline: a
commit-time content gate on staged `commands/*.md` (Phase 7), joining the six
gates already in `hooks/hooks.json`. Without that, this program's result decays
the first time someone adds a step that says "count the entries."

Corollary constraints:

- A script owns each derived value, and the prompt's instruction is "run this,
  print the output" — not "run this, then format it as follows."
- Reference documentation about how a script behaves lives in
  `skills/session-continuity/REFERENCE.md` or a spec, never in a command body.
- Fixed output text is emitted by the script that computes the values around
  it, so it cannot be paraphrased.

## Evidence

Real path: the audit read all seven files in `commands/` end to end, plus
`hooks/session-start.sh`, `hooks/lib/candidate-extract.{sh,jq}`,
`hooks/lib/learnings-index.sh`, `hooks/lib/agent-active.sh`,
`hooks/lib/perf-log.sh`, `hooks/lib/require-script.sh`, and the five files in
`skills/session-continuity/templates/`. The two count defects in Phase 0 were
reproduced by running the plugin's own `grep -cE` against the shipped template
files and against a no-match fixture on this machine.

Stubbed: nothing for the two reproduced defects. Everything else in this spec
is classification from reading source, not a measured behavior claim — the
per-phase token savings are unmeasured estimates and are labeled as such.

### Prompt bytes by command

- `commands/end-session.md` — 45,284
- `commands/primer.md` — 24,323
- `commands/learning.md` — 9,934
- `commands/doctor.md` — 7,482
- `commands/help.md` — 3,236
- `commands/spike-check.md` — 2,730
- `commands/update.md` — 1,361

### Six categories of avoidable work

**1. Fixed reference text shipped as prompt.** `end-session.md:392-489` — about
98 lines documenting the four extraction heuristics — opens by stating that
`candidate-extract.jq` "decides all of this… they are **not instructions to
you**." Also the 18-line presentation example at 514-532 and the "Illustrative
only" block at 687-701. `help.md` and `update.md` are constants whose own
prose tells the model not to re-derive them.

**2. Arithmetic and counting handed to a model.** A majority-of-three vote over
test counts with a spread message (`end-session.md:193-199`, restated
`primer.md:264-278`); token-set intersection cardinality against a threshold
(`end-session.md:100-112`, restated at 253-279 with the stopword list printed
verbatim); four separate tallies in one checklist row (654); an `ITEMS` count
(128-131); a `RETRIES` counter; renumbering backlog positions 1..N on every
refresh (`primer.md:315-316`); 4-hex tag minting with a uniqueness check
(`primer.md:118-121`, 313-315); sentence-counting against a 1-3 cap
(`primer.md:189-191`); a 72-character subject length check
(`end-session.md:682`).

**3. The same shell inlined four times.** Four near-identical 14-line
epoch-subtraction blocks carrying a BSD-then-GNU `date` fallback pair:
`end-session.md` 228-241, 295-308, 579-592, 715-729. `perf-log.sh` has only a
`record` subcommand, so the arithmetic has nowhere to live but the prompt, and
one instruction (line 209) asks the model to reconstruct the pattern from "the
same pattern used elsewhere in this file."

**4. Logic that already exists in shell, restated as prose.** `primer.md`'s
whole check mode (322-346) recomputes the four values `session-start.sh:63-93`
already computes and prints in the same four-line shape.
`end-session.md:74-91` duplicates the three-way migration branch at
`session-start.sh:76-93`. `end-session.md:561` tells the model to count
entries for the next LEARNINGS number while `learnings-index.sh report`
already prints `MAX <n>` — and `learning.md` Step 4 calls that script
correctly, so the right pattern is in the repo, unused by its sibling.

**5. Claimed-vs-actual comparisons done by eye.** The primer's embedded
`git log --oneline -5` block against live output is requested by both
`primer.md:34` and `doctor.md:66`, in both cases by reading the file and
comparing mentally. It is an awk range extract and a `diff`, and it gates
whether `end-session.md`'s entire refresh flow runs (172-179).

**6. Instructions that exist only because models render unreliably.**
"List every file… do not summarize, filter, or pick a 'primary' one"
(`end-session.md:646`, `doctor.md:73`). "Never omit it. Never replace it with
paraphrased prose" (773). "Enumerate every entry… never summarize multiple
candidates into one line" (533-536). Each compensates for a failure mode a
formatter cannot have. They are the clearest signal available of which steps
belong in a script: the prompt is arguing with the model about determinism.

## What stays model work

Five to seven judgment calls in the whole plugin. Naming them is half the
point of this spec — the program's success condition is that these are all
that is left, not that turns approach zero.

- Drafting a LEARNINGS entry's trap, symptom, fix, and diagnostic signal from
  session context (`end-session.md:557-559`, `learning.md` Step 2).
- Deciding whether a backlog item's claim is still true against real code,
  including the case where a grep hit is a comment rather than a live path
  (`primer.md:304-310`, `end-session.md:145-147`). This is where tokens
  *should* go.
- Classifying an item as an overflow that belongs in a linked spec rather than
  in the list (`primer.md:189-196`).
- Drafting `{{WORKFLOW_CONVENTIONS}}` and `{{REPO_LAYOUT_SUMMARY}}`'s one
  inferred sentence from arbitrary project prose (`primer.md:110-112`).
- Writing a conventional-commit subject when code is staged
  (`end-session.md:677-685`); the `.session-continuity/`-only case is already
  a constant.
- Partitioning an unsplit primer's sections into stable and volatile
  (`primer.md:142-151`) — but both heading lists are enumerated in the prompt,
  so this reduces to fuzzy-matching a heading against a table, and the genuine
  unknown case already escalates to the user.
- Interpreting a free-text reply to an interactive prompt.

`spike-check.md` is a special case: its body is a five-question constant, but
its purpose is to make a model demand and evaluate answers before a spike is
built. Printing the checklist deterministically would remove the mechanism, so
it stays a prompt. Noted here so a later phase does not "optimize" it.

## Phases

Each phase is independently shippable and independently useful. Phase order is
driven by dependency and by risk, not by size.

**Ownership rule for borderline mechanics.** A mechanism belongs to the phase
that rewrites the file it lives in, unless it has consumers in more than one
command file — then it belongs to Phase 3. This is what settled the transcript
resolver, which started in Phase 3 and moved to Phase 2.

**Entry format.** Once a phase has its own design or plan, its entry here
collapses to a pointer: what it does, what it depends on, and the link. Design
reasoning, rejected alternatives, schema detail, and testing live in that
artifact, so that changing a decision touches one file rather than two. A
phase with no artifact yet keeps a scope sketch here, because there is
nowhere else for it.

**Phase 0 `[3b71]` — fresh-install count defects.** Two reproduced bugs affecting every
new project. Patch release, depends on nothing. Plan:
`meta/superpowers/plans/2026-09-02-fresh-install-count-defects.md`.

**Phase 1 `[5c2d]` — zero-turn read-only lists.** Retires the model from `/backlog`,
`/learnings`, `/help`, and `/update`; the only phase that reaches literally
zero model calls, where the rest reduce turns and remove error modes. Depends
on nothing. Plan:
`meta/superpowers/plans/2026-09-02-zero-turn-read-only-commands.md`.

**Phase 2 `[8e4a]` — `end-session` Step 2 rendering and reference relocation.** Largest
single token reduction available. Depends on nothing. Design:
`meta/superpowers/specs/2026-09-02-end-session-step2-rendering-design.md`;
needs a plan.

**Phase 3 `[a17f]` — shared mechanics library.** `perf-log.sh mark`/`since`,
plus `primer-status.sh` shared by `session-start.sh` and `primer.md`'s
check mode. Unblocks phases 4 and 6 and closes `52dc` as a side effect.
`doctor.md`'s drift verdict was scoped out — deferred to #45, once `4a9d`
is decided. Plan:
`meta/superpowers/plans/2026-09-03-shared-mechanics-library.md`.

**Phase 4 `#41` — `end-session` Step 3 checklist assembly.** `checklist-assemble.sh`
consumes the (now seven — a `git rev-parse --short HEAD` was added for the
detached-HEAD row) git outputs plus a `tag<TAB>verdict<TAB>citation` scratch
file, emitting all eight finished rows, the backlog tallies, every marker,
and the terminal sign-off line as one block — Step 4 no longer prints
anything of its own. Removes the "list every file, do not summarize"
instruction and the illustrative example entirely; the script's own output
is the contract. Plan:
`meta/superpowers/plans/2026-09-08-determinism-phase-4-checklist-assembly.md`.

**Phase 5 `#42` — token-overlap gate (re-scoped 2026-09-08).** Original framing
above was stale on two counts: item bookkeeping (hex-tag mint/renumber/
grep-delete) is gone with the GitHub Issues migration, and `primer.md` no
longer carries its own copy of the gate — only `end-session.md` does, in
two spots (the "Overlap gate" in Backlog verification and the refresh
flow's "backlog overlay"). `candidate-extract.jq`'s `overlap()` is a
Jaccard *ratio* for LEARNINGS-candidate dedup, not the same algorithm as
this cardinality-threshold gate; lifting it here would have been wrong
(already fixed and closed as #40 in the prior session, unrelated to this
change). Shipped as `hooks/lib/token-overlap.sh`/`.jq`:
tokenize, drop short tokens and stopwords, intersect, threshold at 3 —
computed once per `end-session` run, reused by both call sites. Set-
intersection cardinality is a task models get wrong silently.

**Phase 6 `#43` — `primer` detect, migrate, init, drift.** Decomposed into
five sub-projects (see `meta/superpowers/specs/2026-09-08-primer-detect-design.md`'s
Context section for the full breakdown and why): **sub-project A shipped**
— Step 1's mode detection plus all three migration triggers, now
`hooks/lib/primer-detect.sh`/`.jq`. Plan:
`meta/superpowers/plans/2026-09-08-primer-detect.md`. **Sub-project B
shipped** — Step 4's test-count majority-vote rerun (the
compare-a-claimed-value-against-an-actual-one class Phase 7 is being
built to gate against), now `hooks/lib/test-count-rerun.sh`/`.jq`. Spec:
`meta/superpowers/specs/2026-09-09-test-count-rerun-design.md`. Plan:
`meta/superpowers/plans/2026-09-09-test-count-rerun.md`. **Sub-project D
shipped** — Step 2's placeholder derivation (`{{PROJECT_NAME}}`, commit
hash/subject pairs, `{{TEST_COMMAND_SUMMARY}}`), now
`hooks/lib/primer-init-derive.sh`/`.jq`. Spec:
`meta/superpowers/specs/2026-09-09-primer-init-derive-design.md`. Plan:
`meta/superpowers/plans/2026-09-09-primer-init-derive.md`. **Sub-project C
deprioritized, not scoped** — Step 3c/3d's `git mv`/`git rm` migration
mechanics (sub-project A only scripted *whether* they run, not *what* they
do) have zero real audience today: this repo's own `BACKLOG.md` is already
gone, and to the maintainer's knowledge no other installs of this plugin
exist yet (no marketplace submission — `#35`). The step only matters for a
project on a pre-v0.29 install that hasn't run `/session-continuity:primer`
since, a population that's currently empty. Scoping it now would be
speculative work for a hypothetical future user, not a real one — see
`#59`, which also documents a real format mismatch found while scoping this
(Step 3b's `OUTSTANDING_ITEMS.md` headings carry no hex tag/date; Step 3d's
`BACKLOG.md` parser assumes both are present) to fix whenever this is
revisited. **Sub-project E deprioritized, not scoped, same reasoning** —
Step 3/3b's section-bucketing (pre-v0.13/v0.22 split-mode migrations) is the
same category as C: legacy-migration-only, zero real audience today, and
the most judgment-heavy of the five besides. Phase 6 is done for now: A, B,
and D shipped; C and E stay parked until this plugin actually has external
installs old enough to hit either path (tracked via `#35`, not reopened
here speculatively).

**Phase 7 `#44` — the gate that keeps it true.** Shipped as
`hooks/derived-value-gate.sh`, covering four of the five originally-scoped
classes (renumber dropped — no grounded removal exists to anchor it on).
Also fixed `#54` (an un-migrated duplicate of Phase 6-B's majority-vote logic
that the gate's own count pattern would otherwise have immediately flagged).
Plan: `meta/superpowers/plans/2026-09-09-determinism-phase-7-derived-value-gate.md`.

## Non-goals

- Reducing turns in the judgment calls listed above. A shorter prompt that
  makes the "verify this claim against real code" step cheaper is a
  regression, not a win.
- Eliminating `spike-check.md`, for the reason given above.
- A general prompt-compression pass. Every reduction here is justified by a
  named script that takes over a named computation.

## Open questions

- Phase 1's plan records four unmeasured hook behaviors that must be probed
  before it codes. Phase 7's gate design depends on nothing from that probe,
  but Phase 1's outcome determines whether a zero-turn path exists at all for
  future read-only additions.
- Whether `doctor.md` should become a script that prints its own report
  (making it a second zero-turn command via Phase 1's mechanism) or stay a
  prompt that interprets probe output. Its five rows are deterministic, but
  its install-mode branching reads environment rather than repo files. Decide
  during Phase 3, when the shared status function forces the question. Filed
  as backlog item `4a9d`.
