# end-session Step 2 — rendering and reference relocation (Phase 2 design)

Proven-gate: N/A — a design document. It contains no claim that any change
here works; nothing in it has been built. The schema and line-number facts
below come from reading the source files named in each case.

**Program:** Phase 2 of
`meta/superpowers/specs/2026-09-02-determinism-program-design.md`. Depends on
nothing and can ship before or after Phase 0 and Phase 1.

## Problem

`commands/end-session.md` is 790 lines, all of which are sent to a model on
every `/session-continuity:end-session`. Roughly 160 of those lines — Step 2's
heuristics documentation (392-489) and its output/presentation rules
(491-552) — describe behavior that `hooks/lib/candidate-extract.jq` already
implements and hand a model a JSON-to-markdown formatting job.

Line 393-396 says so directly: `candidate-extract.jq` "decides all of this…
they are **not instructions to you**."

## The correction that shapes the design

The heuristics text is **not dead**. Lines 402-404 make it conditionally live:

> In context-window mode there is no script and no transcript to run it
> against. There, and only there, apply the rules below by hand.

So deleting it would break the fallback path. The win is not deletion — it is
making a rarely-needed 98-line load **conditional** instead of unconditional.
Context-window mode is reached only when the transcript is absent, unreadable,
empty, or older than five minutes (`candidate-extract.sh:68-84`), which is the
exception, not the rule.

This distinction is why Phase 2 needs a design rather than just a diff.

## Two defects found while reading the source

**The illustrative example teaches a format the data cannot produce.** The
presentation block at 514-532 shows candidate 2 rendered as a single inline
line: `Evidence: N Bash invocations across <paraphrased context>; resolved by
<paraphrased fix>.` But `candidate-extract.jq:204` emits
error-recurrence evidence as `($g[0:3] | map("@ " + .ts))` — an array of bare
timestamps with no command text, no context, and no fix. There is nothing in
the JSON to paraphrase. A model following the example must either invent the
missing content or silently deviate from the format it was just shown.

**Evidence shape differs by heuristic, and the prompt does not say so.**
Heuristics A, B, and D emit `"Bash @ <ts> → <command>"`
(`candidate-extract.jq:169`, `188`, `230-231`); heuristic C emits `"@ <ts>"`.
A renderer handles that trivially. A prompt shown one example and told
"render exactly as the Presentation section specifies" does not.

## Design

### The output schema, as it actually exists

`candidate-extract.sh` prints exactly one JSON object and always exits 0:

```
{"mode":"transcript"|"unavailable"|"error",
 "candidates":[{"heuristic":"…","title":"…","evidence":["…"]}],
 "overflow":N,
 "detail":"…"}
```

`evidence` is an array of plain strings. `evidence_count` is used for sorting
and the per-heuristic cap, then deleted (`candidate-extract.jq:252`). Every
value the presentation needs is present, and none of it needs interpretation.

### A sibling renderer, not a flag on the extractor

New: `hooks/lib/candidate-render.sh`, reading the extractor's JSON on stdin and
printing the finished user-facing block on stdout. One pipeline, one Bash call:

```bash
candidate-extract.sh "$TRANSCRIPT" | candidate-render.sh
```

Rejected alternatives, and why:

- **`candidate-extract.sh --render`.** Either it re-runs the jq filter for a
  second invocation, or it changes a `CONTRACT_VERSION=2` contract that
  `require-script.sh` guards and `commands/learning.md` and the existing smoke
  runner both depend on. A sibling leaves the extractor untouched.
- **Rendering inside the jq filter.** The filter would then own both extraction
  and presentation, and the existing smoke runner's 20-odd `jq -e` assertions
  against `.candidates[]` would have nothing to assert against.
- **Having the extractor print both JSON and rendered text.** Two output
  formats on one stream is the kind of contract that gets parsed with a regex.

The renderer is testable on its own against fixture JSON, with no transcript
and no `git` state — which none of Step 2's current behavior is.

### The renderer owns three of four modes

- `mode:"transcript"` with candidates — prints the numbered list with
  `[heuristic-id]` tags and indented evidence bullets, the `+N more
  candidates…` line when `overflow > 0`, and the capture prompt.
- `mode:"transcript"` with no candidates and no overflow — prints the single
  no-op line now specified at 505 and 543-544.
- `mode:"error"` — prints `⚠️ LEARNINGS candidates unavailable: <detail>` with
  `.detail` inserted, not paraphrased. This is the case the prose at 496-500
  is most anxious about, and the anxiety is well placed: a derivation that
  fails invisibly is what the whole Step 2 design exists to prevent.
- `mode:"unavailable"` — cannot be owned, because the correct response is to
  fall back to context-window mode, which is model work. The renderer prints
  one machine-recognizable line and stops:

```
SC-FALLBACK: context-window — <detail>
```

That gives the command exactly one branch to describe: if the output starts
with `SC-FALLBACK:`, switch to context-window mode; otherwise print the output
verbatim. Sixty lines of branching and format specification collapse to about
five.

### Transcript resolution moves here too

`hooks/lib/resolve-transcript.sh` prints the resolved transcript path on
stdout, or nothing. It absorbs the resolution order now written as prose at
`end-session.md:328-358`: encode `pwd` per the `/` → `-` rule, pick the
newest-mtime `.jsonl` in the resulting directory, and print nothing if the
directory is absent, holds no `.jsonl`, or the newest one is stale.

This was originally assigned to Phase 3 and belongs here instead. It sits
inside the section Phase 2 already rewrites, so leaving it out means editing
the same prose twice. It also composes with the fallback design rather than
adding a second one: a resolver that prints nothing feeds
`candidate-extract.sh` an empty path, which emits `mode:"unavailable"`, which
the renderer turns into `SC-FALLBACK:`. One fallback path, not two.

The staleness half of this already exists at `candidate-extract.sh:79-84`,
including the GNU-versus-BSD `stat` ordering trap that must not be re-derived
(`stat -c %Y` first — the BSD `-f %m` form means `--file-system` on GNU
coreutils, writes to stdout, and exits 1). The resolver reuses that ordering;
the extractor keeps its own check, because it must stay correct when handed a
path from any source.

Scripting this also retires the advisory at 351-354 telling the model to
"prefer `grep`/`wc`/`jq` … do not Read the whole file into context." That
instruction exists only because the model is the thing holding the path.

**Two consumers, not one.** `candidate-extract.sh` at line 370 and
`agent-active.sh` at line 743 both need the path, and Step 4's block is
currently gated on a `$TRANSCRIPT` variable set back in Step 2, in a different
Bash call. Both call sites resolve on demand instead, which removes the
cross-step variable dependency entirely.

Ruled out by measurement, recorded so it is not re-investigated: that
cross-step dependency is not currently broken.
`.session-continuity/performance.log` shows `step-4-agent-active` firing on
the two most recent invocations (`2026-09-02T00:42:56Z`, 83.415s within a
176s ritual; `2026-09-02T16:43:11Z`, 136.864s within 149s), and
`step-4-compute-only` on the five before them, from 2026-08-31 through
2026-09-01T20:51. The changeover is the first run after v0.25.0 shipped, so
the earlier "nothing has executed since v0.23.0" observation was the stale
plugin cache and nothing else. The measurement does not distinguish shell
state persisting from the model inlining the literal path, and on-demand
resolution makes the distinction irrelevant.

### Where the heuristics documentation goes

A new shipped file, `skills/session-continuity/HEURISTICS.md`, read on demand
and only in context-window mode.

Not `skills/session-continuity/REFERENCE.md`: at 109 lines it is user-facing
guidance about hooks, gates, and philosophy, and 98 lines of jq-internals
would swamp it. Not a file under `meta/`: per `CLAUDE.md` that tree is
repo-internal agent artifacts, and this text has to be reachable at runtime in
a consuming project. It also stops being prompt tokens and starts being
documentation a maintainer can read on its own, which is what lines 393-396
say it already is.

The privacy rules at 384-390 move with it. They constrain how a model
paraphrases evidence, and in transcript mode the jq filter already redacts
(`redact_paths`, `norm_err`, the 160- and 120-character caps), so they are
live in exactly the same conditional case as the heuristics.

### What Step 2 becomes in the prompt

The input-source and resolution-order prose (328-358) collapses to one
`resolve-transcript.sh` call. The extraction call (360-382) keeps its
`require_script` guard, gains the pipe, and loses the "parse `.mode`,
`.candidates[]`, `.overflow`, `.detail`" instruction along with the two
negative instructions at 377-379 telling the model not to add a timer. The
heuristics and presentation sections become a single conditional pointer to
`HEURISTICS.md`. The capture flow from 554 onward is untouched: drafting a
LEARNINGS entry's trap, symptom, and fix is irreducible model work and Phase 2
must not touch it.

## Estimated effect

Estimate, not a measurement: about 160 of 790 lines leave the unconditional
prompt path, near 20% of the file, with the relocated 98 loaded only in the
fallback case. The error-rate effect is the part worth more than the tokens —
it removes the JSON-to-markdown formatting job entirely, and with it the three
anti-drift instructions that exist because a model does that job unreliably
("Enumerate every entry… Never summarize multiple candidates into one line or
silently drop one", 507; "Always include it", 534-535; the enumeration rule at
533-536).

## Testing

A new smoke runner for the renderer, driven entirely by fixture JSON on stdin:
one fixture per mode, a zero-candidate transcript fixture, an overflow
fixture, a fixture whose `detail` contains quotes and a newline, a fixture
with all four heuristic ids present, and a fixture mixing heuristic C's
bare-timestamp evidence with A's command-bearing evidence — the shape mismatch
named above. Malformed JSON on stdin must produce the `SC-FALLBACK:` line
rather than a crash, since the renderer sits in a ritual that must not abort.
Follow the existing convention: `ok`/`bad` counters, every failure message
carrying the mismatched value, and preserve the failing diagnostic in the run
log before teardown.

The existing `2026-09-01-candidate-extract-smoke.zsh` must keep passing
unchanged. That is the check that the extractor's contract really was left
alone.

## Out of scope

- Step 3's checklist assembly and its example block at 687-701. Phase 4. One
  seam to hand over: line 544 requires the zero-candidate case to be noted in
  Step 3's checklist, so Phase 4's assembly script needs that fact from the
  renderer.
- The four duplicated epoch-subtraction blocks (228-241, 295-308, 579-592,
  715-729) and the `perf-log.sh mark`/`since` pair that replaces them.
  Phase 3, because those have call sites in `primer.md` and `doctor.md` too —
  shared infrastructure with three consumers is a different risk and test
  surface from a single-file change.
- The `overlap()` asymmetry in the dedupe, already filed as BACKLOG item 7
  `[c9a4]`. Deliberately excluded, not merely deferred: fixing it changes
  which candidates survive dedupe, which would invalidate assertions in
  `2026-09-01-candidate-extract-smoke.zsh` — the suite this design relies on
  passing unchanged as its proof that the extractor's contract was left alone.
  Bundling a behavior change into a relocation also makes the release
  un-bisectable if candidate quality shifts afterwards. The renderer displays
  whatever survives dedupe and neither fixes nor worsens it.
