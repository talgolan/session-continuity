# Validation log — token-overlap gate consolidation (Determinism Phase 5, #42)

**Branch:** `determinism-phase-5-token-overlap`

Fixture-driven checks of `hooks/lib/token-overlap.sh` /
`hooks/lib/token-overlap.jq`, run directly (no bats/test harness exists in
this repo yet — see open issue #36). Each case is a scratch issues-file /
commits-file pair passed straight to the script.

| # | Case | Input | Result | Expected |
|---|------|-------|--------|----------|
| 1 | Real match | issue title and commit subject share `determinism`, `phase`, `5`, `overlap`, `gate` (≥3 non-stopword tokens) | one row `#42\t<subject>` | one row |
| 2 | Near-miss | only `phase`/`5`-adjacent overlap below threshold | empty | empty |
| 3 | Stopword-only overlap | shared words (`fix`, `and`, `update`, `the`, `docs`) are entirely in the stopword list | empty | empty — proves stopwords are dropped before counting, not just documented |
| 4a | Empty issues file | — | empty, exit 0 | empty |
| 4b | Empty commits file | — | empty, exit 0 | empty |
| 5 | Multiplicity | issue title repeats `overlap` 3×; only 2 *distinct* tokens (`overlap`, `gate`) are actually shared | empty (cardinality 2 < 3) | empty — proves each token set is deduped before intersecting, so multiplicity can't inflate cardinality (the class of bug split out to #40 for `candidate-extract.jq`'s unrelated Jaccard-ratio function) |
| 6 | Missing input file | nonexistent path | stderr diagnostic, exit 1 | non-zero exit, no crash |

All six matched expectation. `commands/end-session.md`'s two prose copies
(the "Overlap gate" in Backlog verification and the refresh flow's "backlog
overlay") were replaced with two reads of one `.end-session-overlap.tsv`
computed by a single script invocation; the stopword list moved out of
prose entirely into `token-overlap.jq`.

**Not exercised here:** the full `end-session.md` flow end-to-end against a
real scratch repo (that level of validation exists for other Phase work,
e.g. `2026-08-17-performance-logging.md`) — this task changes an internal
computation swapped in place of equivalent prose, with the same inputs
(`backlog-issues.sh`, `git log --oneline`) and output contract (`#N`
identity, TSV) the surrounding prose already expected, so a full command
run was judged unnecessary for this size of change.
