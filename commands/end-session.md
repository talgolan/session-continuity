---
description: Refresh the primer, surface LEARNINGS candidates from this session, and report a close-out checklist. Zero args.
---

# /session-continuity:end-session

You are responding to the `/session-continuity:end-session` slash command.

**Your job: run a close-out ritual that (1) refreshes `.session-continuity/SESSION_PRIMER.md`, (2) surfaces LEARNINGS candidates from this session's conversation, and (3) reports a structured ✓ / ⚠️ checklist of the repo's state so the user can walk away knowing nothing is forgotten.**

Zero arguments. Never commits. Never pushes.

## Step 0 — Preconditions

Check that both files exist at the canonical path:

1. `.session-continuity/SESSION_PRIMER.md`
2. `.session-continuity/LEARNINGS.md`

If either is missing, tell the user:

> "No `.session-continuity/SESSION_PRIMER.md` (or `.session-continuity/LEARNINGS.md`) found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

Exit. Do not proceed.

## Step 1 — Refresh the primer (drift-gated)

Before prompting the user for anything, check the fast path below. If it
doesn't fire, verify the primer's outstanding items against code, then run a
drift check. The goal: if the primer is already in sync with the repo, do
nothing and record a no-op. Only enter the refresh flow when something
actually changed.

### Fast path — nothing changed since last close-out (check first, cheap)

Run all three in **one Bash call** (one round trip, not three), timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git status --porcelain
git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md   # <last-primer-commit>
git rev-parse HEAD
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-fast-path --duration="$_PERF_DURATION"
```

If `git status --porcelain` is empty AND `<last-primer-commit>` equals
`HEAD` (no commits have landed since the primer was last touched), skip the
rest of Step 1 entirely — no drift check, no backlog verification,
no git-log recomputation. Nothing in the repo has changed since the last
close-out, so no per-item re-check could turn up anything new. Step 3's
Primer refresh row reads ✓ "Primer already current (no-op)"; the
Backlog row reads ✓ "N tracked — not re-verified this session (no
repo changes since last close-out)". Skip straight to Step 2.

Otherwise — something changed — proceed with the checks below.

### Backlog verification (gated by commit-subject overlap)

Verify the primer's outstanding items against actual repo state. Runs
whenever the fast path above didn't fire. Compute each verdict once here;
Step 3 reuses these verdicts.

**Compute the commit list once.** Run
`git log <last-primer-commit>..HEAD --oneline` (reusing `<last-primer-commit>`
from the fast-path check above). This same list feeds both this section's
overlap gate below and the Refresh flow's overlay further down — compute it
here, don't recompute it there.

**Data source.** Read `.session-continuity/BACKLOG.md`, not a
heading inside the primer — the backlog lives in its own file now.

**Skip conditions.**
- If `.session-continuity/BACKLOG.md` doesn't exist AND the
  primer has no leftover inline outstanding-items heading from before the
  split either: skip verification silently (fresh/already-flat project).
  Step 3's row reads `Backlog: none tracked`.
- If `.session-continuity/BACKLOG.md` doesn't exist BUT the
  primer still has the inline heading: this is an unmigrated project.
  Skip only the backlog verification sub-flow (this whole
  section) — everything else in Step 1 (fast path, drift check, git-log
  regeneration, test-count rerun) proceeds normally, independent of this
  condition. Tell the user once: "This project's backlog hasn't
  migrated to `.session-continuity/BACKLOG.md` yet —
  run `/session-continuity:primer` first (it migrates automatically),
  then re-run `/session-continuity:end-session`." Step 3's row reads
  `Backlog: not migrated — run /session-continuity:primer`.
- If `.session-continuity/BACKLOG.md` exists but is empty
  (no `### N.` entries): skip verification, Step 3's row reads `none
  tracked`, same as the fresh-project case.

**For each `### N.` entry** in `.session-continuity/BACKLOG.md`
(scope the item exactly as the overlay does: the heading line plus every line
until the next `### N.` heading or end of file; sub-bullets roll up to their
parent):

**Overlap gate (cost control) — run this before classifying.** Tokenize the
item (same rule as the overlay below: lowercase, split on non-alphanumeric,
drop tokens <3 chars, drop the overlay's stopword list) and compare against
each commit subject in the list computed above, tokenized the same way. If
the intersection with EVERY commit subject has cardinality <3 — nothing that
landed since the last refresh implicates this item — skip the
classify/verify steps below for this item. Assign verdict **`manual`**, cited
as `"no related commits since last refresh — not re-checked this session"`.
This is the deliberate accuracy tradeoff of the gate: an item resolved
through means that leave no matching commit subject (a manual/external fix)
won't be caught until a touching commit lands or the user mentions it
directly. Items with cardinality ≥3 against at least one commit subject
proceed to full classify/verify below.

1. **Classify — code-verifiable or not.** An item is code-verifiable if a
   `grep`/`glob`/file-exists check *could* speak to it (it names a file, a
   hook path, a test harness, a LEARNINGS title, a code construct).
   Classification is binary: low-confidence code items (a grep exists but the
   match may be ambiguous) still classify AS code-verifiable — they resolve to
   `manual` below when evidence is insufficient. Items naming an external
   action or a parked decision (marketplace submission, rejected
   recommendations) are non-code.

2. **Verify code items** with a derived `grep`/`glob`/file-exists check via
   Bash. **Batch every item's check into one Bash call** — one script that
   runs all the derived checks back-to-back (e.g. one `grep`/`test -e` per
   item, each echoing a labeled result line) and returns all evidence in a
   single round trip. Never spend one round trip per item. Wrap that one
   Bash call with a timer, and set `ITEMS` to the count of items that went
   through this classify/verify pass (i.e. items NOT already resolved as
   `manual` by the overlap gate above):

   ```bash
   _PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   # ... the derived per-item grep/test -e checks run here ...
   _PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
   _PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-outstanding-items-verification --duration="$_PERF_DURATION" --items="$ITEMS"
   ```

   Assign one verdict per item from that combined output:
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
  append every `appears-DONE` item to the existing backlog overlay
  candidate list, so it surfaces at Step 1's single combined prompt. One reply
  closes it. Cite the evidence beside the candidate.
- **When the primer is drift-clean** (refresh flow skipped): if at least one
  `appears-DONE` item was found, run the **drift-clean close-candidate prompt**
  below instead of the refresh flow. If zero `appears-DONE` items were found,
  no prompt fires at all — the "drift-clean + zero candidates = zero prompts"
  guarantee holds.

Removal of any item always requires explicit user confirmation. A verdict never
mutates the primer on its own.

### Drift check (silent — no user prompt)

Read `.session-continuity/SESSION_PRIMER.md` and compare its `git log --oneline -5` block to the actual output of `git log --oneline -5` against the primary branch. Two outcomes:

- **Block matches.** Treat the primer as current — no git-log regeneration, no test-count re-check, no refresh flow. Then check the Backlog verification results computed above:
  - **Zero `appears-DONE` items.** Skip the rest of Step 1. In Step 3's checklist, record the Primer refresh row as ✓ "Primer already current (no-op)".
  - **≥1 `appears-DONE` item.** Run the drift-clean close-candidate prompt below instead of skipping Step 1.
- **Block differs** (any line differs — subjects, hashes, or ordering). Enter the refresh flow below.

If the primer has a test-counts section, decide whether to re-run it (logic
lives in Step 5.3 of `commands/primer.md` — summarized here). Do this as
**one Bash call**, timed, tracking a `RETRIES` count (0 if skipped or the
first run matched, else the number of *extra* runs actually executed
beyond the first):

- **Skip the rerun** if the commit list already computed above
  (`<last-primer-commit>..HEAD`) contains no file outside
  `.session-continuity/` — no source or test file changed, so the recorded
  count cannot have drifted.
- **Otherwise, run the test command(s) once.** Matches the primer's
  recorded count → stop, no drift on this axis.
- **Only if that first run disagrees**, retry up to 2 more times (3 total)
  to rule out flakiness. Pin to the count seen in ≥2 of 3 runs — if that
  pinned count matches the primer, the first run was the flake and there's
  no drift; if it still differs, report drift with the pinned count. If all
  three runs disagree with each other, surface the spread (`saw 1162 / 1161
  / 1162 across 3 runs — using 1162; suite is unstable`) instead of
  silently picking one.

Common cases stay cheap: zero test runs when nothing relevant changed, one
run when the count still holds, three only when there's an actual
discrepancy to resolve.

At the end of this Bash call (whichever branch above ran):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-drift-test-rerun --duration="$_PERF_DURATION" --retries="$RETRIES"
```
using the same `_PERF_START`/`_PERF_END`/`_PERF_DURATION` pattern used
elsewhere in this file, captured around this whole check.

### Drift-clean close-candidate prompt (runs only when drift is clean AND ≥1 `appears-DONE` item)

A lighter-weight alternative to the refresh flow below — no git-log regeneration, no test-count re-check, no commit-subject overlay matching (there is no "commits since last refresh" list to match against when nothing drifted).

1. Render the `appears-DONE` items as the same markdown ordered list format used by the refresh flow's overlay (item's own primer number as ordinal, citing the code evidence).
2. Before rendering the question below, log a prompt-shown marker (isolates the human-response wait from ritual compute time — see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-shown --duration=0.000
   ```

   Then ask a close-only question, scoped narrower than the refresh flow's combined prompt since there are no commit subjects or free-form drift to fold in:

   > "Backlog — N appears-DONE (see list). Close any, or leave as-is?"
3. **Wait for the answer before continuing.** Same refusal rule as the refresh flow: never close an item without explicit confirmation. Once the answer arrives, log the wait duration:

   ```bash
   prior_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
     | grep '"step":"step-1-prompt-shown"' | tail -1 \
     | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
   prior_epoch=""
   if [ -n "$prior_ts" ]; then
     prior_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$prior_ts" +%s 2>/dev/null \
       || date -u -d "$prior_ts" +%s 2>/dev/null || true)"
   fi
   if [[ "$prior_epoch" =~ ^[0-9]+$ ]]; then
     now_epoch="$(date -u +%s)"
     bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-wait --duration="$(( now_epoch - prior_epoch )).000"
   fi
   ```
4. If the user closes any items, edit only `.session-continuity/BACKLOG.md` (the drift check already confirmed the primer's `git log --oneline -5` block is current and untouched, so the primer itself needs no edit here) and stage that file: `git diff --quiet .session-continuity/BACKLOG.md 2>/dev/null || git add .session-continuity/BACKLOG.md`. Step 3's Primer refresh row reads ✓ "Primer updated (outstanding item(s) closed)".
5. If the user declines, skip the rest of Step 1. Step 3's Primer refresh row reads ✓ "Primer already current (no-op)", and the still-open `appears-DONE` item(s) surface again as a ⚠️ in the Backlog row (same standing-reminder behavior as before — it'll be offered again next session).

### Refresh flow (runs only when drift was detected)

Follow the logic in **Step 5 of `commands/primer.md`** (refresh mode):

1. Regenerate the `git log --oneline -5` block with current output.
2. If the primer has a test-counts section and the counts changed (after the 3× retry), update them to match current output.
3. **Surface commits since the last primer refresh, with backlog overlay.** Reuse the commit list already computed in the Backlog verification section above (`git log <last-primer-commit>..HEAD --oneline`) — do not recompute it. Present the subject list as candidate prompts.

   Then compute a **backlog overlay** for each subject:

   - Tokenize the subject: lowercase, split on non-alphanumeric, drop tokens of length <3, drop the stopword list below.
   - For each `### N.` entry in `.session-continuity/BACKLOG.md`: tokenize the item text the same way, capped at the first 200 characters of the item (the heading line through everything up to the next `### N.` heading or end of file; sub-bullets roll up to their parent item).
   - Match if the intersection of subject tokens and item tokens has cardinality ≥ 3.

   **Stopwords** (extend per project as needed):

   ```
   the and for fix add update from with into feat chore docs primer learnings session continuity tag version release
   ```

   **Presentation.** Render the "May close outstanding items" block when EITHER
   token-overlap matches from commit subjects OR `appears-DONE` items from the
   Backlog verification sub-block above exist. **Render candidates as
   a markdown ordered list, one item per line, using the item's own primer
   number as the list ordinal** (e.g. `4. <cited code evidence> — <sha>`) so
   the numbering the user sees matches the numbering in the primer — never a
   bare bullet list or an inline comma-separated citation. Cite each
   candidate: commit-subject matches as `<sha> → item #<N>`, verification
   candidates as `item #<N> (<cited code evidence>)`. Dedupe by item number: an
   item that is both a commit-subject match and an `appears-DONE` candidate
   appears once, on a single numbered line carrying both the `<sha>` and the
   code-evidence citation. Omit the block only when BOTH sources are empty (do
   not print an empty section).

   **Refusal.** Never close an outstanding item without explicit user confirmation. The overlay is a candidate list, not an auto-close.

   **Skip conditions.** If `.session-continuity/BACKLOG.md` doesn't exist (unmigrated project, or the file was deleted), skip the overlay silently — the raw subject list still appears.
4. **Single combined prompt.** After printing the subject list (and overlay block if any), log a prompt-shown marker (same mechanism as the drift-clean prompt above — isolates human-response wait from ritual compute time, see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-shown --duration=0.000
   ```

   Then ask the user one question covering both close-candidates and free-form edits:

   > "Backlog — close any from the overlay, add new follow-ups, or no changes?"

   **Wait for the answer before continuing.** Do not preemptively edit the list, clear items you interpret as "stale," or proceed based on your own reading. Do not split this into two sequential prompts — one prompt covers the same answer space. Once the answer arrives, log the wait duration:

   ```bash
   prior_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
     | grep '"step":"step-1-prompt-shown"' | tail -1 \
     | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
   prior_epoch=""
   if [ -n "$prior_ts" ]; then
     prior_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$prior_ts" +%s 2>/dev/null \
       || date -u -d "$prior_ts" +%s 2>/dev/null || true)"
   fi
   if [[ "$prior_epoch" =~ ^[0-9]+$ ]]; then
     now_epoch="$(date -u +%s)"
     bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-prompt-wait --duration="$(( now_epoch - prior_epoch )).000"
   fi
   ```
5. Apply the edits the user specified. If the user replied "no changes" (or similar), skip this step.
6. Stage the updated primer and `BACKLOG.md` (if the user closed or
   edited any items in step 5 above), and `PROJECT_CONTEXT.md` too if it has
   unstaged changes (e.g. the session edited repo layout / conventions):

   ```bash
   git add .session-continuity/SESSION_PRIMER.md
   git diff --quiet .session-continuity/PROJECT_CONTEXT.md 2>/dev/null || git add .session-continuity/PROJECT_CONTEXT.md
   git diff --quiet .session-continuity/BACKLOG.md 2>/dev/null || git add .session-continuity/BACKLOG.md
   ```

**Do not** commit. Staging only.

## Step 2 — Session reflection for learnings

Apply four explicit heuristics to surface LEARNINGS candidates from
this session. Each heuristic emits zero-or-more candidates; the union
is presented to the user, deduplicated by title, capped at 5.

### Input source

Prefer the session transcript file when accessible; fall back to the
context window when not. Transcript file location:

```
~/.claude/projects/<url-encoded-cwd>/<session-id>.jsonl
```

URL-encoding rule: `/` → `-`, leading `/` becomes leading `-`. Example
cwd `/Users/tal.golan/repo` → directory `-Users-tal-golan-repo`.

**Resolution order:**

1. Compute the expected directory from `pwd` using the encoding rule.
2. If the directory exists, pick the `.jsonl` file with the most
   recent mtime — this is assumed to be the live session.
3. Fall back to context-window mode if any of: the directory does not
   exist, no `.jsonl` files inside, or the most-recent file's mtime
   is older than 5 minutes (stale, probably the wrong session).
4. Best-effort. Any failure falls through to context-window mode
   without error.

When in transcript-file mode, prefer `grep`/`wc`/`jq` via Bash to
filter relevant entries (Bash tool calls, errors, commits) before
pulling raw JSON into context. JSONL files for long sessions can be
megabytes — do not Read the whole file into context.

When in context-window mode, note the limitation in the candidate
output: "session context may be compacted; some early-session events
may not have surfaced." Do not pretend to have full visibility.

### Combined extraction pass (transcript-file mode only)

Do this ONCE, before applying any heuristic below — not once per heuristic.
Four independent greps/jq passes over the same (possibly multi-megabyte)
file is pure redundant cost; one pass produces everything all four
heuristics need.

Run the `jq` filter below over the transcript file in **one Bash call**
(`jq -n -f <(cat <<'JQEOF' ... JQEOF) "$TRANSCRIPT"` or write it to a temp
file and `jq -n -f`). It has been validated against real Claude Code
transcripts across schema variants (some tool_result lines carry a
`toolUseResult.{stdout,stderr}` object, others carry only a `content`
string prefixed `"Exit code N\n..."` — the filter handles both) and runs in
well under a second even on multi-megabyte, 200+-call transcripts. Use it
as-is; do not re-derive a filter from scratch (a naive rewrite is exactly
what caused a syntax-error retry round trip in past runs — e.g. `"" |
split("\n")[0]` returns `null` in jq, not `""`, and crashes the next
`gsub` in the chain). Time this Bash call: capture
`_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")` immediately
before running `jq`, `_PERF_END` the same way immediately after, compute
`_PERF_DURATION` the same way as elsewhere in this file, and call:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-2-transcript-extraction --duration="$_PERF_DURATION"
```
in the same call, right after `jq` returns.

```jq
def norm_err:
  if (. == null or . == "") then ""
  else
    .
    | gsub("(?<p>/[^ :\"]+/)(?<b>[^/ :\"]+)"; "\(.b)")
    | gsub(":[0-9]+:[0-9]+"; "")
    | gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?"; "")
    | gsub("[0-9]{2}:[0-9]{2}:[0-9]{2}"; "")
    | gsub("0x[0-9a-fA-F]+"; "0xN")
  end;
# First useful line out of a tool_result's text blob: skips a leading
# "Exit code N" line (Bash convention), skips blank lines.
def first_line_from_text:
  (split("\n") | map(select(length>0))) as $ls
  | if ($ls|length)==0 then ""
    elif ($ls[0] | test("^Exit code")) then ($ls[1] // "")
    else $ls[0]
    end;
def err_line_of($is_error; $stderr; $text):
  if ($stderr // "") != "" then $stderr
  elif $is_error then ($text // "" | first_line_from_text)
  else (($text // "" | split("\n") | map(select(test("^Error:"))) | .[0]) // "")
  end;
[inputs] as $lines
| ($lines
    | map(select(.type=="user" and (.message.content|type)=="array"))
    | map(. as $line
        | $line.message.content[]?
        | select(.type=="tool_result")
        | {
            ts: $line.timestamp,
            tool_use_id: .tool_use_id,
            is_error: (.is_error // false),
            text: (.content | if type=="string" then . else tostring end),
            stderr: ($line.toolUseResult | if type=="object" then .stderr else null end)
          })
  ) as $tool_results
| ($tool_results | map(. + {err_line: err_line_of(.is_error; .stderr; .text)})) as $tool_results2
| ($tool_results2 | map({key: .tool_use_id, value: .}) | from_entries) as $results_by_id
| ($lines
    | map(select(.type=="assistant"))
    | map(. as $line | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | {
        ts: $line.timestamp,
        tool_use_id: .id,
        command: .input.command,
        result: ($results_by_id[.id] // {is_error:false, err_line:""})
      })
  ) as $bash_calls
| {
    bash_calls: ($bash_calls | map({ts, command, is_error: .result.is_error, first_err_line: (.result.err_line | norm_err)})),
    commits: ($bash_calls | map(select(.command | test("git commit"))) | map({ts, command})),
    errors: ($tool_results2 | map(select(.err_line != "")) | map({ts, err: (.err_line | norm_err)}))
  }
```

Output shape — three arrays in one JSON object:

- **`bash_calls`** — every Bash tool call: timestamp (`ts`), raw command,
  `is_error`, normalized first error line (`first_err_line`, empty string
  if none). Feeds Heuristics A and D. Apply Heuristic A's own command
  normalization (strip-after-newline, whitespace-collapse, drop pure-read
  commands) on top of the raw `command` field — that normalization is
  heuristic-specific, not part of this shared pass.
- **`commits`** — every Bash call whose command matches `git commit`:
  timestamp, raw command (parse `sha`/`subject` from the `-m` argument or
  from stdout's `[branch sha] subject` line — the filter doesn't attempt
  this since it varies by whether a heredoc or `-m` string was used).
  Feeds Heuristic D's trigger.
- **`errors`** — every tool result (any tool, not just Bash) whose derived
  error line is non-empty: timestamp, normalized error string. Feeds
  Heuristic C. Entries are already deduped to non-empty `err` — an
  `is_error: true` result with no extractable text is silently excluded
  rather than appearing as a spurious empty-string "error", which would
  otherwise falsely satisfy Heuristic C's ≥3-recurrence trigger.

Heuristics A–D below all read from these three in-memory arrays. None of
them re-reads or re-filters the transcript file — if a heuristic's logic
seems to require a fresh scan, derive it from `bash_calls`/`commits`/`errors`
instead.

### Privacy

Heuristic candidates' "evidence" bullets paraphrase tool inputs; they
never quote raw stdout/stderr beyond the first error line of any
failing tool call. Never include full prompt text, full command
output, or any value that could plausibly be a secret. When in
doubt, paraphrase.

### Heuristics

Apply each heuristic to the resolved input source (transcript file or
context window). Each heuristic emits zero-or-more candidates with a
title and supporting evidence (1-3 bullet citations).

#### Heuristic A — retry burst

From `bash_calls` (computed once above), group consecutive calls by
**normalized command**:

- Strip arguments after the first newline (heredocs collapse to their
  command head).
- Collapse runs of whitespace to single spaces.
- Drop pure-read commands: `cat`, `ls`, `grep`, `find`, `stat`,
  `pwd`, `which`, `echo`. (These are noise — not investigatory
  retries.)

**Trigger:** the same normalized command appears ≥3 times in the
session.

**Candidate title:** `<command> — investigated for N retries.`

**Evidence:** up to 3 of the invocation timestamps + `is_error` flags
(redact stdout/stderr beyond the first error line).

#### Heuristic B — revert / reset

**Trigger:** in `bash_calls`, any invocation matching one of:

- `git reset --hard`
- `git checkout -- <path>`
- `git revert`
- `git restore`
- `rm -rf <path>` where `<path>` appears in `git ls-files` output
  (i.e. a tracked file, not a tmp directory).

**Candidate title:** `Reverted approach: <commit subject of reverted
commit if available, else 'unrecorded'>.`

**Evidence:** the offending Bash invocation + the commit being
reverted (look up `git show <reverted-sha> --format=%s` if known).

#### Heuristic C — error recurrence

`errors` (computed once above) already holds the normalized error string per
entry:

- First non-empty line of stderr, or
- The `Error:`-prefixed line, whichever appears first.
- Normalized: absolute paths stripped to basenames, line:column refs
  (`:42:7`) stripped, ISO-8601/`HH:MM:SS` timestamps stripped, hex addresses
  (`0x[0-9a-f]+`) stripped.

**Trigger:** the same normalized error string appears ≥3 times in `errors` AND
the first and last occurrences span ≥15 minutes (use timestamps from
the JSONL `timestamp` field; in context-window fallback skip the
wall-clock gate and trigger on count alone).

**Candidate title:** `<error string> — recurred N times over M minutes.`

**Evidence:** up to 3 invocation citations spanning the timeline.

#### Heuristic D — fix burst

**Trigger:** in `commits`, a subject (parse from the `-m` argument, or the
first line of a `<<'EOF'` heredoc body, in the entry's raw `command` field)
matching `^fix(\(.+\))?: ` preceded, in `bash_calls`, by ≥10 calls within
the prior 30 minutes (count both successful and failing invocations; use
JSONL timestamps; in fallback mode use ordinal proximity rather than
wall-clock).

**Candidate title:** `<commit subject> — fix preceded by N-action investigation.`

**Evidence:** the commit invocation + a representative sample of the
preceding burst (3 citations, evenly spaced through the 30-minute
window).

### Output

Compute the **union** of triggers from all four heuristics.
Deduplicate by title (case-insensitive substring match — if two
candidates share a >70% title overlap, keep the one with more
evidence). Sort by evidence-bullet count, descending.

**Cap:** present at most 5 candidates. If more triggered, show the
top 5 and append:

```
+N more candidates not shown — capture these first, then re-run /session-continuity:end-session.
```

**Zero candidates:** print `No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.` and proceed directly to Step 3.

### Presentation

Render candidates as a numbered list with `[heuristic-id]` annotations
and indented evidence bullets. Format:

```
LEARNINGS candidates from this session:

1. [retry-burst] `<command>` — investigated for N retries.
   Evidence:
   - Bash @ HH:MM → exit 1 ("<paraphrased error>")
   - Bash @ HH:MM → exit 1 ("<paraphrased error>")
   - Bash @ HH:MM → exit 0 (after <paraphrased fix>)

2. [error-recurrence] "<normalized error string>" — recurred N times over M minutes.
   Evidence: N Bash invocations across <paraphrased context>; resolved by <paraphrased fix>.

3. [revert] Reverted approach: "<commit subject>" (commit <sha> → git reset --hard).
   Evidence: <paraphrased justification>.

Capture any? (1, 2, 3, all, none, or describe another)
```

The `[heuristic-id]` tag is one of: `retry-burst`, `revert`,
`error-recurrence`, `fix-burst`. Always include it — it tells the
user which signal triggered the candidate.

If the cap fired (more than 5 triggered), append after the list:

```
+N more candidates not shown — capture these first, then re-run /session-continuity:end-session.
```

If you find **zero** candidates, skip the prompt entirely and print
`No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.`
to the user, then note "no new learnings" in Step 3's checklist.

If the input source was context-window (transcript file unavailable),
append a single line under the list:

```
Note: session context may be compacted; some early-session events may not have surfaced.
```

### Capture flow — batch presentation, single confirm

For every candidate the user picked (e.g. "1, 3" or "all"), pre-draft the full LEARNINGS entry up front. Compose each per `commands/learning.md`'s structure:

- Pre-fill the **Title** from the candidate description.
- Pre-draft **The trap**, **Symptom**, **Fix**, and **Diagnostic signal** from session context. Do not invent details the session does not support — leave a field blank rather than fabricating.
- Choose section per **Step 3 of `commands/learning.md`**.
- Compute the next number per **Step 4 of `commands/learning.md`** (number entries sequentially within the chosen section).

If the user describes "another" candidate not on your list, treat that description as a pre-filled title and draft alongside the others.

**Single confirm prompt.** Present every pre-drafted entry together in one rendered block (numbered, full body, target section labeled). Before asking, log a prompt-shown marker (same mechanism as Step 1's prompts — isolates human-response wait from ritual compute time, see Step 4):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-2-prompt-shown --duration=0.000
```

Then ask one question:

> "Stage all N entries as drafted, revise specific ones, or skip any?"

Possible replies you must handle: "all" / "stage" → stage every draft; "revise N" → loop into edit-draft-N flow then re-present; "skip N" → drop draft N from the batch; "none" → stage nothing.

Once the answer arrives, log the wait duration:

```bash
prior_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
  | grep '"step":"step-2-prompt-shown"' | tail -1 \
  | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
prior_epoch=""
if [ -n "$prior_ts" ]; then
  prior_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$prior_ts" +%s 2>/dev/null \
    || date -u -d "$prior_ts" +%s 2>/dev/null || true)"
fi
if [[ "$prior_epoch" =~ ^[0-9]+$ ]]; then
  now_epoch="$(date -u +%s)"
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-2-prompt-wait --duration="$(( now_epoch - prior_epoch )).000"
fi
```

Once the user confirms, insert each accepted draft at the top of its chosen section per **Step 5 of `commands/learning.md`** and stage per **Step 6**: `git add .session-continuity/LEARNINGS.md`.

Do not loop one-prompt-per-candidate. The batch is the unit.

**Do not** commit. Staging only.

## Step 3 — Final checklist

Run real git commands and emit a structured checklist. Every item must reflect actual repo state, not an assertion.

### Gather the facts

Run all six in **one Bash call** (one round trip, not six), timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git diff --cached --name-only          # staged files
git diff --name-only                    # unstaged modifications
git ls-files --others --exclude-standard   # untracked (ignoring .gitignore'd)
git rev-parse --abbrev-ref HEAD         # current branch (or "HEAD" if detached)
git rev-parse --abbrev-ref @{u} 2>/dev/null  # upstream branch, or empty if none
git rev-list --count @{u}..HEAD 2>/dev/null  # unpushed commits, empty if no upstream
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-3-gather-facts --duration="$_PERF_DURATION"
```

- **Backlog verdicts** — reuse the per-item verdicts from Step 1's
  verification sub-block; re-read `.session-continuity/BACKLOG.md` to
  get the post-edit item set. No new git command — the evidence was already
  gathered in Step 1.

Handle these edge cases explicitly:

- **Not a git repo.** If `git rev-parse` fails, the precondition in Step 0 should have caught this, but belt-and-suspenders: report "⚠️ not inside a git repo" once and skip git-dependent rows.
- **Detached HEAD.** `git rev-parse --abbrev-ref HEAD` returns `HEAD`. Note "⚠️ detached HEAD at `<short-sha>`" in the unpushed-commits row.
- **No upstream.** `git rev-parse --abbrev-ref @{u}` fails. Note "⚠️ branch `<name>` has no upstream — set one with `git push -u origin <name>`" in the unpushed-commits row.

### Emit the checklist

**List every file enumerated by the git commands — do not summarize, filter, or pick a "primary" one.** If `git diff --cached --name-only` returns three files, the "Staged files" row lists all three. Same rule for the Unstaged and Untracked rows. The suggested-commit message may emphasize one theme, but the checklist rows are inventories, not summaries.

Output using this structure. Use ✓ (green), ⚠️ (yellow), or → (suggestion):

| Row | Marker | Content |
|---|---|---|
| Primer refresh | ✓ | "Primer refreshed and staged" OR "Primer updated (outstanding item(s) closed)" OR "Primer already current (no-op)" |
| New learnings | ✓ | "N LEARNINGS entry/entries captured (#X, \"<title>\" …)" OR "No new learnings" |
| Backlog | checkmark if none stale, else warning | "N tracked — <k> appears-DONE (#X, evidence), <m> still-open (#…), <j> manual (#…)" OR "none tracked" |
| Staged files | ✓ | "Staged: <file1>, <file2>, …" OR "Nothing staged" |
| Unstaged modifications | ✓ if none, else ⚠️ | "No unstaged modifications" OR "⚠️ Unstaged: <file1>, <file2>, …" |
| Untracked files | ✓ if none, else ⚠️ | "No untracked files" OR "⚠️ N untracked: <file1>, <file2>, … — ignore, add, or delete?" |
| Unpushed commits | ✓ / ⚠️ | "Up to date with origin/<branch>" OR "⚠️ Branch <name> is N commits ahead of origin — push before closing?" OR the detached-HEAD / no-upstream variants |
| Suggested commit | → | Derived from staged files + captured learnings. Omit row entirely if nothing is staged. |

**Backlog row — re-derive, do not cache.** Step 3 re-reads
`.session-continuity/BACKLOG.md` AFTER any Step 1 closures the
user confirmed. The *set* of items and the counts are recomputed against the
post-edit `.session-continuity/BACKLOG.md`; only the per-item
verdicts (`still-open` / `appears-DONE` / `manual`) computed in Step 1 are
reused. If the user closed an item at the Step 1 prompt, it is gone from the
file and absent from this row. Marker: ✓ if
every remaining item is `still-open` or `manual` (nothing stale lingering);
⚠️ if any remaining item is `appears-DONE` (a resolved item still listed).
Cite the evidence for each `appears-DONE` item inline. A `manual` item's
citation is either `"not auto-verifiable"` (genuinely non-code) or `"no
related commits since last refresh — not re-checked this session"` (skipped
by the overlap gate) — keep whichever citation Step 1 assigned, don't
collapse them to one phrase. When the fast path fired, skip re-deriving this
row altogether and use its own citation as specified there.

### Suggested commit message

If files are staged, derive a commit message from the pattern:

- Only `.session-continuity/` staged → `docs: update session continuity`.
- `.session-continuity/LEARNINGS.md` is staged with code → pick the most prominent captured learning's title (or the primary code-change theme) and use conventional-commit style: `<type>(<scope>): <subject>`. Keep subject line ≤ 72 chars.
- Only code staged (no docs) → should not happen if Step 1 ran; if it does, suggest based on the file paths.

Prefix with `→ Suggested:` and wrap in a fenced code block so the user can copy-paste.

### Example output

```
✓ Primer refreshed and staged
✓ 1 LEARNINGS entry captured (#7, "awk range collapse on single-version CHANGELOG")
⚠️ Backlog: 5 tracked — 1 appears-DONE (#4, "add bats test harness": found test/end_to_end.bats → 0 hits before, now present), 1 still-open (#3), 3 manual (#1, #2, #5)
✓ Staged: .session-continuity/SESSION_PRIMER.md, .session-continuity/LEARNINGS.md, .github/workflows/release.yml
✓ No unstaged modifications
⚠️ 2 untracked files: scratch.md, tmp/debug.log — ignore, add, or delete?
⚠️ Branch "main" is 3 commits ahead of origin — push before closing?
→ Suggested:
    git commit -m "fix(ci): extract CHANGELOG section with proper awk range"
```

*(Illustrative only — the real Backlog row reflects the current primer's actual item set and verdicts.)*

## Step 4 — Terminal sign-off (always)

After the checklist (and suggested-commit block, if any), emit a final closing line so the user knows the ritual completed and they are not blocked waiting for further prompts.

**Before that line, record total ritual time.** Each step above only timed
its own Bash block, not the gaps between them — this reads back this
invocation's own `step-1-fast-path` timestamp (always the first thing every
invocation logs, fast-path or not) and diffs it against now, so the log
carries one real end-to-end number per invocation alongside the per-step
ones. Skip the log call entirely rather than record a bogus duration if the
timestamp is missing or unparseable:

```bash
last_ts="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
  | grep '"step":"step-1-fast-path"' | tail -1 \
  | sed -E 's/.*"ts":"([^"]*)".*/\1/' || true)"
start_epoch=""
if [ -n "$last_ts" ]; then
  start_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last_ts" +%s 2>/dev/null \
    || date -u -d "$last_ts" +%s 2>/dev/null || true)"
fi
if [[ "$start_epoch" =~ ^[0-9]+$ ]]; then
  now_epoch="$(date -u +%s)"
  _PERF_DURATION="$(( now_epoch - start_epoch )).000"
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-4-ritual-complete --duration="$_PERF_DURATION"
fi
```

**Then derive compute-only time** — `step-4-ritual-complete` is real wall clock, but it includes however long the user took to answer the Step 1 and Step 2 prompts logged above (`step-1-prompt-wait`, `step-2-prompt-wait`). Subtract whichever of those fired *this invocation* (their `ts` must be ≥ this invocation's `start_epoch`, computed above — a wait logged before this invocation's `step-1-fast-path` belongs to a prior run and must not be counted) to isolate the agent's own processing time:

```bash
if [[ "$start_epoch" =~ ^[0-9]+$ ]]; then
  wait_total=0
  for wstep in step-1-prompt-wait step-2-prompt-wait; do
    line="$(grep '"name":"end-session"' .session-continuity/performance.log 2>/dev/null \
      | grep "\"step\":\"$wstep\"" | tail -1 || true)"
    if [ -n "$line" ]; then
      w_ts="$(printf '%s' "$line" | sed -E 's/.*"ts":"([^"]*)".*/\1/')"
      w_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$w_ts" +%s 2>/dev/null \
        || date -u -d "$w_ts" +%s 2>/dev/null || true)"
      if [[ "$w_epoch" =~ ^[0-9]+$ ]] && [ "$w_epoch" -ge "$start_epoch" ]; then
        w_dur="$(printf '%s' "$line" | sed -E 's/.*"duration_s":([0-9.]+).*/\1/')"
        wait_total="$(awk -v a="$wait_total" -v b="$w_dur" 'BEGIN{printf "%.3f", a+b}')"
      fi
    fi
  done
  compute_only="$(awk -v a="$_PERF_DURATION" -v b="$wait_total" 'BEGIN{printf "%.3f", a-b}')"
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-4-compute-only --duration="$compute_only"
fi
```

**Always emit one of these two lines, exactly:**

- If every checklist row was ✓ (no ⚠️ anywhere):

  ```
  ✅ Session complete. Safe to close.
  ```

- If any checklist row had ⚠️:

  ```
  ✅ Session complete. Safe to close. (Warnings above are advisory — review before closing if relevant.)
  ```

**Required.** Print this line on its own, after the checklist and any suggested-commit block. Never omit it. Never replace it with paraphrased prose. Never ask follow-up questions after this line — the line marks the end of the ritual. If the user wants to act on a warning, they will reply on their own.

## Notes

- **Never commit automatically.** Stage only, across both Step 1 and Step 2.
- **Never push.** The checklist flags unpushed commits; the user decides.
- **Never invent LEARNINGS details.** If you can't draft a field from session context, leave it blank and ask the user — same rule as `/session-continuity:learning`.
- **Reflection is bounded by the current session.** Step 2 looks only at this conversation's context. Bugs from prior sessions, parallel worktrees, or separate Claude instances (subagents, different windows) aren't visible and won't be proposed. For those, the user should invoke `/session-continuity:learning` directly.
- **`step-4-ritual-complete` includes human response time, by design.** It is real wall clock from this invocation's first log line to its last, and that necessarily spans however long the user took to answer the Step 1 and Step 2 prompts. `step-4-compute-only` (same block) subtracts the `step-1-prompt-wait`/`step-2-prompt-wait` entries logged around those prompts, isolating the agent's own processing time. When investigating a slow ritual, compare both numbers before assuming a script regression — a large `step-4-ritual-complete` with a small `step-4-compute-only` means the user was away from the keyboard, not that anything got slower.
- **Respect the primer-only-commit rule.** If the user, after seeing the checklist, commits only the primer, the `PreToolUse` hook's nudge still applies — nothing to do here.
- **Zero arguments.** If the user passed text after `/session-continuity:end-session`, ignore it — session reflection provides all context needed.
- **Bound the prompt count.** The whole ritual must fit ≤2 user prompts in the common case: one Step 1 prompt (the full combined prompt when drift exists, or the lighter drift-clean close-candidate prompt when drift is clean but `appears-DONE` items exist), one batch confirm in Step 2 (only when candidates surface). Drift-clean + zero candidates = zero prompts; drift-clean + ≥1 candidate = exactly one (lightweight) prompt. Never split Step 1's prompt into two sequential asks. Never loop one-prompt-per-candidate in Step 2.
- **Always sign off.** Step 4's terminal line is non-negotiable — the user invoked an explicit close-out and must not be left ambiguous about whether the ritual is done.
- **Backlog verdicts never mutate the primer.** The verification in
  Step 1 only classifies and reports; an `appears-DONE` item is removed only if
  the user confirms it at a Step 1 prompt (full combined prompt or the
  drift-clean close-candidate prompt). Declining either prompt leaves the item
  as a standing ⚠️ in the checklist, never a silent deletion.
