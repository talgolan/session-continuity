# End-session Step 2 — cost attribution and heuristic execution — design

Date: 2026-09-01
Status: approved, ready for implementation plan

Real path: the shipped `/session-continuity:end-session` ritual at v0.22.0,
as actually run 28 times in `architect-workbench` and 10 times in this repo.
Every number below is read back from those repos'
`.session-continuity/performance.log` files and from the live Claude Code
session transcripts under `~/.claude/projects/`.
Stubbed: nothing — no fixture repo, no synthetic log, no replayed input. The
measurement is of real invocations that already happened.

## Problem

`/session-continuity:end-session` feels slow, and the performance log added
in `2026-08-17-performance-logging-design.md` reports numbers that seem to
confirm it: in `architect-workbench`, `step-4-ritual-complete` reaches
8732s and `step-4-compute-only` — the field whose whole purpose is to
exclude human time — reaches 4572s.

Two questions have to be answered together: how much of the ritual is the
plugin's own cost, and whether the number that claims to answer that means
anything. The second turns out to dominate the first.

## What the measurement shows

### Finding 1 — `compute-only` counts human idle as compute

Twenty-six of the 28 `architect-workbench` invocations reach Step 2 and so
have a measurable span from `step-2-transcript-extraction` to the end of
Step 2. Shown with the largest contiguous interval inside that span in which
no logged event of any kind occurred:

| Invocation (UTC) | Step 2 span | largest gap | gap share |
|---|---|---|---|
| 2026-08-27T00:41 | 8588s | 8181s | 95% |
| 2026-09-01T02:52 | 4217s | 4006s | 95% |
| 2026-08-23T21:53 | 3931s | 3586s | 91% |
| 2026-08-29T19:50 | 3120s | 2892s | 93% |
| 2026-08-26T17:51 | 2634s | 2077s | 79% |
| 2026-08-21T22:30 | 2044s | 1281s | 63% |
| 2026-08-25T21:32 | 753s | 288s | 38% |
| the other 19 runs | ≤312s | small | many events, no dominant gap |

The distribution is bimodal: p50 is 146s and p75 is 312s, and 19 runs sit at
or under 312s. Six of the seven runs above that are dominated by a single
no-event stretch worth 63-95% of the span. The seventh, 2026-08-25T21:32 at
753s, is the exception that matters: 44 events, no dominant gap, genuinely
busy. It is the honest upper bound on what Step 2 costs when the agent is
actually working.

Hooks only fire on Bash/Write/Edit, so a gap could in principle hide
Read/Grep work. It does not. In the transcript for the 2026-09-01T02:52 run
(`3a9f0e24-9e95-4473-a771-7224dbaeb52d.jsonl`) the assistant emitted its
closing text at 03:04:19 and the turn ended; the next record is a user
message at 04:09:45. Sixty-five minutes with no turn in flight. The same
signature — a turn-end `system` record, a long nothing, then a user message
— holds for the 08-27 (7962s), 08-23 (3572s), 08-29 (2519s) and 08-26
(1854s) runs. These four numbers are strictly smaller than the "largest
gap" column above, and that is expected, not an error: the table's gap is
bounded by the nearest *logged* Bash/Write/Edit events on either side,
which can span part of an active turn on each end, while the number here is
the transcript-measured idle span from the turn-end record to the next user
message — the true no-turn-in-flight duration, a subset of the table's gap
by construction.

`step-4-compute-only` subtracts only `step-1-prompt-wait` and
`step-2-prompt-wait`, the two instrumented `AskUserQuestion` waits (311s and
78s in that run). It has no notion of a turn boundary, so every mid-ritual
turn boundary is booked as agent compute. It also reads each wait step with
`tail -1`, so a second Step 1 prompt inside one invocation silently drops
out of the subtraction.

### Finding 2 — the real Step 2 cost is sequential re-filtering

From the same transcript, the tool sequence after the shared extraction:

- 03:01:49–03:02:07 — the combined `jq` extraction pass, logged at 0.093s.
- 03:02:15, 03:02:28, 03:02:42, 03:03:04, 03:03:13, 03:03:27, 03:03:43 —
  seven further calls: one `jq` per heuristic against `/tmp/extracted.json`,
  plus a `python3` heredoc for Heuristic D's timing arithmetic.

`commands/end-session.md` states that Heuristics A–D read from the three
in-memory arrays and that none of them re-reads or re-filters the
transcript. The agent honoured the letter (one extraction) and re-filtered
the extracted JSON six more times anyway. Those six round trips are roughly
88s of the ~132s Step 2 spent producing candidates. Prose cannot enforce
"do not re-derive this."

### Finding 3 — the shipped shell work is free

Across both repos, every instrumented Bash unit is sub-second:
`step-2-transcript-extraction` max 0.093s, `step-3-gather-facts` max 0.176s,
`step-1-fast-path` max 0.102s. No shell operation the plugin ships is a
measurable share of any ritual.

Hooks are likewise cheap. `learnings-surface.sh` fired 8066 times in
`architect-workbench` for 489s cumulative (p50 0.036s, p95 0.153s, max
4.757s); the seven commit-time gates sit at mean 0.07-0.08s each.

### Finding 4 — the derived-content steps are not running at scale

`architect-workbench`'s `LEARNINGS.md` is 161KB / 2356 lines / 68 entries
and contains **zero** `## Symptoms index` bullets — the section does not
exist in the file. Step 6 of `commands/learning.md` mandates regenerating
that index on every append, and it has never run in the repo with the most
entries. Only 12 of the 68 entries carry a `Trigger:` line, so
`learnings-surface.sh` can resurface 18% of the corpus.

This is the same failure mode as Finding 2 from the other direction: an
expensive derivation expressed as prose gets skipped rather than done.

## Invariants

Per CLAUDE.md rule 4, the end-states this design has to hold on every path,
not just on the paths that produced the numbers above:

1. **No number the plugin logs as compute may include an interval with no
   agent turn in flight.** Enforced where the number is computed, not by
   adding another prompt marker at each prompt site — a new prompt site
   added later must not be able to reintroduce the bug.
2. **Every deterministic derivation over the transcript or over
   `LEARNINGS.md` runs as shipped code, invoked once, with its output
   consumed as data.** Heuristic thresholds, entry numbering, duplicate and
   slug detection, and the Symptoms index are all derivations. Prose
   descriptions of them are documentation, never the execution path.

## Design

### Change 1 — ship the extraction and the heuristics as one script

New script under `hooks/lib/` taking a transcript path and emitting ranked
candidate JSON on stdout:

- Absorbs the ~55-line `jq` filter currently embedded in
  `commands/end-session.md`, so the agent stops re-emitting it verbatim on
  every run. The file's own note that a naive rewrite already caused a
  syntax-error retry round trip is the argument for this on its own.
- Absorbs Heuristics A-D in full: command normalization and the ≥3-retry
  trigger, the revert/reset command set, error normalization with the
  ≥3-occurrence and ≥15-minute window, and the fix-burst commit match with
  its ≥10-calls-in-30-minutes precondition.
- Absorbs the output rules: dedup by title overlap, sort by evidence count,
  cap at 5, and the `+N more candidates` overflow note.
- Emits one JSON object: `{"mode":"transcript"|"unavailable","candidates":[…],"overflow":N}`.
  Each candidate carries `heuristic`, `title`, and `evidence[]` already
  paraphrased to the privacy rule in the current Step 2.
- Never fails loud: unreadable, missing, or stale *transcript* (input data,
  not the script itself — see Resolved decision 2) yields
  `mode:"unavailable"` with an empty candidate list and exit 0. Step 2's
  existing context-window fallback prose handles that case unchanged.
- Times itself through `hooks/lib/perf-log.sh` exactly as the current
  extraction step does, keeping `step-2-transcript-extraction` comparable
  across the change.

Step 2 in `commands/end-session.md` collapses to: run the script once, read
the candidates, present them, and draft prose only for the ones the user
picks. The heuristic prose stays in the file as documentation of what the
script decides, explicitly marked as non-executable.

### Change 2 — measure agent-active time instead of guessing at it

Step 4 already knows the transcript path (Step 2 resolved it) and already
knows this invocation's start epoch. Replace the prompt-wait subtraction
with a derivation over the transcript.

**Primary mechanism — sum harness-reported turn durations.** Both real
transcripts behind Finding 1 (the `architect-workbench` file cited there,
and this repo's own current session, checked directly rather than assumed)
carry `{"type":"system","subtype":"turn_duration","durationMs":N,...}` at
the end of every assistant turn, and a matching
`{"type":"system","subtype":"away_summary",...}` record precisely on the
idle stretches Finding 1 found by manual inspection. Sum `durationMs` over
every `turn_duration` record whose `timestamp` falls in `[start_epoch,
now]`, convert to seconds, and that sum is the agent-active metric —
already excluding idle time, computed by the harness itself rather than
inferred from record adjacency.

**Fallback — timestamp turn-boundary walk.** If a transcript in
`[start_epoch, now]` contains zero `turn_duration` records (an older
Claude Code version or a harness configuration that doesn't emit them —
unverified whether every user's schema includes this field), fall back to
walking transcript records and summing the interval between consecutive
records only when the earlier record is inside a turn — concretely, when
it is not itself a `turn_duration` record. An interval whose left edge is
a `turn_duration` record is human latency by definition, whatever its
length, and is excluded. This fallback is schema-weaker than the primary
mechanism (it infers turn boundaries from adjacency rather than reading an
explicit field) but activates only when the primary signal is entirely
absent.

Log the result as a new step slug, `step-4-agent-active`, alongside the
unchanged `step-4-ritual-complete` wall clock, regardless of which
mechanism produced it.

This satisfies invariant 1 structurally: neither mechanism enumerates
prompt sites, so a future prompt cannot escape either one.
`step-4-compute-only` is retired rather than fixed — the two-marker
subtraction cannot be made correct, since the markers only exist where
someone remembered to put them.

If the transcript is unavailable, log no `step-4-agent-active` line at all
rather than falling back to a number that would be wrong in the same way the
current one is.

### Change 3 — ship the LEARNINGS derivations as a script

A second script handling the parts of `commands/learning.md` Steps 4 and 6
that are pure derivation over the file:

- Report the true maximum entry number, every duplicate number with its line
  numbers, and every duplicate slug — the inputs to the existing refuse-to-
  write guard, which stays prose because it is a decision, not a derivation.
- Regenerate `## Symptoms index` wholesale from every entry's `**Symptom.**`
  line, creating the section when absent.
- Idempotent: running twice over an unchanged file produces no diff.

`commands/learning.md` Step 6 and `commands/end-session.md`'s capture flow
both call it. At 68 entries and 161KB this is the difference between a
derivation that runs and one that gets skipped.

### Out of scope

Token accounting (still deferred, same reasoning as the performance-logging
spec). Hook micro-optimization — 489s spread over 8066 calls is not where
the time is. Any change to the `LEARNINGS.md` file format. Any change to
what the heuristics decide; this spec moves them, it does not retune them.

## Testing plan (nothing here is implemented yet)

- **Replay against the archived transcripts.** Run the candidate script over
  the six gap-dominated transcripts identified in Finding 1 and over two fast runs,
  and compare its candidate set against what the agent produced by hand in
  those same invocations (recoverable from the perf-log timeline and the
  `LEARNINGS.md` commits of those dates). Divergence is either a heuristic
  transcription bug or a finding about the prose version; both need naming
  before the script ships.
- **Determinism.** Same transcript twice produces byte-identical JSON.
- **Degradation.** Missing path, truncated JSONL, and a transcript older
  than the 5-minute staleness rule each produce `mode:"unavailable"`, empty
  candidates, exit 0.
- **Metric correction.** Recompute `step-4-agent-active` for all 28 recorded
  `architect-workbench` invocations from their transcripts. The six
  gap-dominated runs must collapse into the same band as the 19 fast ones;
  the busy 753s run must not. A slow run that stays slow under the new
  metric is a real finding and gets investigated rather than explained away.
- **Fallback coverage.** Confirm which of the 28 `architect-workbench`
  transcripts and this repo's own transcripts carry `turn_duration` records
  at all (grep the raw files, don't assume) and run at least one recorded
  invocation through the fallback path deliberately (e.g. by truncating a
  copy of a transcript to strip `turn_duration`/`away_summary` records) to
  prove the fallback isn't dead code.
- **Index script.** Against the 68-entry file: 68 bullets produced, entry
  bodies byte-unchanged, second run a no-op. Against this repo's 15-entry
  file with an existing index: verify the script's own rule (hard 12-word
  cutoff + ellipsis, dictionary-order case-insensitive sort) is applied
  correctly and the second run is a no-op — **not** a byte-identical match
  against the current hand/LLM-authored index. Confirmed by direct test:
  the current index truncates some entries by judgment rather than a strict
  12-word count (entry #14 cuts at 10 words) and orders one backtick-led
  title differently than any deterministic `sort` reproduces. A mechanical
  script cannot and should not reproduce a prior ad-hoc judgment call —
  its own rule, applied consistently, is the correctness bar going forward.
- **End to end.** Run the full ritual in a scratch repo and confirm Step 2
  issues exactly one analysis call, that `step-4-agent-active` appears with
  a plausible value, and that `step-4-compute-only` is gone.

## Resolved decisions

1. **Placement.** Both new scripts ship under `hooks/lib/`, alongside the
   plugin's existing shipped shell libraries, on the `${CLAUDE_PLUGIN_ROOT}`
   path the commands already reference. Not a new `skills/` scripts
   directory — one path to wire up, not two.
2. **Version skew.** No prose fallback. If a command finds its script file
   missing or its version marker older than the command's, Step 2 (or the
   equivalent capture step) reports the candidate/index script as outdated
   and directs the user to update the plugin, rather than silently
   degrading to the prose path. The prose stays in the command files as
   documentation only, never as a live fallback — keeping a fallback alive
   keeps it drifting, which is the failure this spec exists to close. This
   is orthogonal to Change 1's `mode:"unavailable"`: that path handles a
   present, current script given bad *input* (no readable transcript, e.g.
   the session ran past the context window); this decision handles an
   absent or outdated *script* relative to the command prose invoking it.
   The two never share a code path.
3. **Index script ownership.** Both `commands/learning.md` Step 6 and
   `commands/end-session.md`'s capture flow call the index-regeneration
   script directly after writing an entry. The script is idempotent and
   cheap (comparable to the sub-second shell steps in Finding 3), so the
   duplication costs nothing measurable; the alternative — only `learning.md`
   owns it — depends on every entry path routing through
   `/session-continuity:learning`, and a capture path that ever writes
   directly would silently reintroduce Finding 4.
