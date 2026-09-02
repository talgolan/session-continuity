# Determinism program — Design

**Status:** approved scope. Phases 0 and 1 have plans, Phase 2 has a design
and needs a plan, phases 3-7 have neither.

Each phase is filed as its own item in `.session-continuity/BACKLOG.md`, tagged
below so the reference works from either direction. Phase *ordering* lives in
`.session-continuity/ROADMAP.md`, not in those items — backlog positions are
recomputed 1..N on every render and carry no permanent meaning.

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

**Phase 3 `[a17f]` — shared mechanics library.** `perf-log.sh mark` and
`perf-log.sh since`, collapsing the four duplicated epoch blocks
(`end-session.md` 228-241, 295-308, 579-592, 715-729) to one-liners; and one
status function shared by `session-start.sh`, `primer.md` check mode, and
`doctor.md`, so the three can no longer disagree. Unblocks phases 4 and 6.

**Phase 4 `[b93c]` — `end-session` Step 3 checklist assembly.** One script consuming the
six git outputs and a `tag<TAB>verdict<TAB>citation` file, emitting the eight
finished rows, the four backlog tallies, the per-row markers, and the sign-off
boolean (612-675, 759-773), retiring the example block at 687-701. Depends on
Phase 3's `since`. Removes the file-inventory summarization failure that
line 646 exists to prevent.

**Phase 5 `[c60e]` — backlog mechanics.** Two scripts used by both `primer.md` and
`end-session.md`: item bookkeeping (mint a 4-hex tag with a uniqueness grep,
stamp the date, renumber positions 1..N, grep the repo for a tag before
deletion) and the overlap gate (tokenize, drop short tokens and stopwords,
intersect with commit subjects, threshold at 3). The overlap algorithm
currently exists as two prose copies that can drift, and
`candidate-extract.jq:96-107` already has a working token-overlap
implementation to lift. Set-intersection cardinality is a task models get
wrong silently.

**Phase 6 `[d24b]` — `primer` detect, migrate, init, drift.** Mode detection plus
migration triggers (11-60, pure boolean logic over file existence); the
backlog rename migration (209-248, forty lines of prompt with no judgment in
any of its seven items, performing a destructive `git mv`); init-mode template
copy and mechanical placeholder substitution, collapsing the ten
`{{LATEST_COMMIT_*}}` slots into one `{{GIT_LOG_BLOCK}}`; and the drift check
plus test-count rerun with modal pinning (172-210, 249-250, 264-278). Largest
phase, lowest per-invocation frequency, highest blast radius — it runs a
`git mv` and rewrites five files.

**Phase 7 `[f58a]` — the gate that keeps it true.** A commit-time content gate on
staged `commands/*.md` that blocks prompt text instructing a model to count,
tally, renumber, compute a duration, compare a claimed value against an
actual one, or print fixed text verbatim, with the usual
`<Gate-name>: N/A — <reason>` escape. This is the reconciler-level enforcement
of the invariant; every other phase is a one-time cleanup that decays without
it. Ships last because the gate's pattern list should be written from what the
earlier phases actually removed, not guessed beforehand.

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
