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
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-issues.sh" --count .   # <fast-path-backlog-count>, "?" on failure
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-fast-path --duration="$_PERF_DURATION"
```

`<fast-path-backlog-count>` feeds Step 3's `backlog_fastpath_count`. If it printed `?` (GitHub unavailable), use `backlog_mode="unavailable"` in Step 3 instead of `"fast-path"` — same GitHub-unavailable handling as the non-fast-path skip condition below.

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

**Data source.** Run
`bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-issues.sh" .`
and identify each item by `#N`. Do not read `.session-continuity/BACKLOG.md`.

**Skip conditions.**
- If the helper prints `No open backlog issues.`: skip verification.
  Step 3's row reads `Backlog: none tracked`.
- If the helper prints the GitHub-unavailable warning: skip verification.
  Step 3's row reads `Backlog: GitHub queue unavailable — run /session-continuity:doctor`.
- If the primer still has an inline `## Outstanding items` heading or
  `.session-continuity/OUTSTANDING_ITEMS.md` exists: tell the user once
  to run `/session-continuity:primer` (it migrates), then re-run
  `/session-continuity:end-session`. Step 3's row reads
  `Backlog: not migrated — run /session-continuity:primer`.

**For each open issue** (`N. #NUMBER Title` from the helper). Identify
the item by `#NUMBER`, never by the ephemeral 1..N list position.

**Overlap gate (cost control) — run this before classifying.** Tokenize the
issue title (same rule as the overlay below: lowercase, split on non-alphanumeric,
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

**Record every verdict for Step 3.** Once every open item has a verdict
(from the overlap gate, the batched classify/verify pass, or the
non-code default), write them all in **one Bash call**. There is no
in-shell list to loop over — the verdicts exist only in what you just
decided — so write one literal `printf` line per item by hand (not a
shell `for`/`while` loop):

```bash
mkdir -p .session-continuity
: > .session-continuity/.end-session-checklist.tsv
printf '%s\t%s\t%s\n' "#4" "appears-DONE" "found test/end_to_end.bats -> 0 hits before, now present" >> .session-continuity/.end-session-checklist.tsv
printf '%s\t%s\t%s\n' "#3" "still-open" "no *.bats and no test/ dir -> item still open" >> .session-continuity/.end-session-checklist.tsv
# ... one such literal printf line per remaining open item, tag first (the
# #N identity, never the ephemeral 1..N list position), verdict second
# (still-open|appears-DONE|manual), citation third (the same evidence string
# already decided above — "not auto-verifiable" for non-code items, "no
# related commits since last refresh — not re-checked this session" for
# overlap-gated ones) ...
```

Skip this entirely when there were zero open items to classify (the file is
absent; Step 3 treats a missing path under `backlog_mode="normal"` as zero
tracked items — see `hooks/lib/checklist-assemble.sh`'s contract).

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

1. Render the `appears-DONE` items as the same markdown ordered list format used by the refresh flow's overlay (`#N` as identity, citing the code evidence).
2. Before rendering the question below, log a prompt-shown marker (isolates the human-response wait from ritual compute time — see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" mark --source=command --name=end-session --step=step-1-prompt-shown
   ```

   Then ask a close-only question, scoped narrower than the refresh flow's combined prompt since there are no commit subjects or free-form drift to fold in:

   > "Backlog — N appears-DONE (see list). Close any, or leave as-is?"
3. **Wait for the answer before continuing.** Same refusal rule as the refresh flow: never close an item without explicit confirmation. Once the answer arrives, log the wait duration:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-1-prompt-shown --emit-step=step-1-prompt-wait
   ```
4. If the user closes any items, `gh issue close N --reason completed` for each confirmed `#N`. Do not edit a markdown backlog file. Step 3's Primer refresh row reads ✓ "Primer updated (outstanding item(s) closed)".
5. If the user declines, skip the rest of Step 1. Step 3's Primer refresh row reads ✓ "Primer already current (no-op)", and the still-open `appears-DONE` item(s) surface again as a ⚠️ in the Backlog row (same standing-reminder behavior as before — it'll be offered again next session).

### Refresh flow (runs only when drift was detected)

Follow the logic in **Step 5 of `commands/primer.md`** (refresh mode):

1. Regenerate the `git log --oneline -5` block with current output.
2. If the primer has a test-counts section and the counts changed (after the 3× retry), update them to match current output.
3. **Surface commits since the last primer refresh, with backlog overlay.** Reuse the commit list already computed in the Backlog verification section above (`git log <last-primer-commit>..HEAD --oneline`) — do not recompute it. Present the subject list as candidate prompts.

   Then compute a **backlog overlay** for each subject:

   - Tokenize the subject: lowercase, split on non-alphanumeric, drop tokens of length <3, drop the stopword list below.
   - For each open backlog issue from the helper: tokenize the title the same way.
   - Match if the intersection of subject tokens and item tokens has cardinality ≥ 3.

   **Stopwords** (extend per project as needed):

   ```
   the and for fix add update from with into feat chore docs primer learnings session continuity tag version release
   ```

   **Presentation.** Render the "May close outstanding items" block when EITHER
   token-overlap matches from commit subjects OR `appears-DONE` items from the
   Backlog verification sub-block above exist. **Render candidates as
   a markdown ordered list, one item per line, using the item's current
   `<position>` as the list ordinal** (e.g. `4. [a3f9] <cited code evidence> — <sha>`)
   so the numbering the user sees matches the numbering in the primer — never a
   bare bullet list or an inline comma-separated citation. Cite each
   candidate by tag: commit-subject matches as `<sha> → item [a3f9]`, verification
   candidates as `item [a3f9] (<cited code evidence>)`. Dedupe by tag (never by
   position — it's recomputed per render and not a stable key): an item that is
   both a commit-subject match and an `appears-DONE` candidate appears once, on
   a single numbered line carrying both the `<sha>` and the code-evidence
   citation. Omit the block only when BOTH sources are empty (do not print an
   empty section).

   **Refusal.** Never close an outstanding item without explicit user confirmation. The overlay is a candidate list, not an auto-close.

   **Skip conditions.** If the helper printed a warning or `No open backlog issues.`, skip the overlay silently — the raw subject list still appears.
4. **Single combined prompt.** After printing the subject list (and overlay block if any), log a prompt-shown marker (same mechanism as the drift-clean prompt above — isolates human-response wait from ritual compute time, see Step 4):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" mark --source=command --name=end-session --step=step-1-prompt-shown
   ```

   Then ask the user one question covering both close-candidates and free-form edits:

   > "Backlog — close any from the overlay, add new follow-ups, or no changes?"

   **Wait for the answer before continuing.** Do not preemptively edit the list, clear items you interpret as "stale," or proceed based on your own reading. Do not split this into two sequential prompts — one prompt covers the same answer space. Once the answer arrives, log the wait duration:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-1-prompt-shown --emit-step=step-1-prompt-wait
   ```
5. Apply the edits the user specified. If they asked to close issues, `gh issue close N --reason completed` for each confirmed `#N` after checking the claim against the code. If they asked to file new follow-ups, `gh issue create --label backlog --title "..." --body "..."`. If the user replied "no changes" (or similar), skip this step.
6. Stage the updated primer, and `PROJECT_CONTEXT.md` too if it has
   unstaged changes (e.g. the session edited repo layout / conventions):

   ```bash
   git add .session-continuity/SESSION_PRIMER.md
   git diff --quiet .session-continuity/PROJECT_CONTEXT.md 2>/dev/null || git add .session-continuity/PROJECT_CONTEXT.md
   ```

**Do not** commit. Staging only.

## Step 2 — Session reflection for learnings

Apply four explicit heuristics to surface LEARNINGS candidates from
this session. Each heuristic emits zero-or-more candidates; the union
is presented to the user, deduplicated by title, capped at 5.

### Resolve, extract, and render

Three scripts, one pipeline. Never re-derive the jq filter, re-filter the
extracted JSON per heuristic, or hand-format the result — that was the
entire cost problem this replaced; see Finding 2 of
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`.

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"

TRANSCRIPT=""
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh" 1; then
  TRANSCRIPT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh")"
fi

if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" 2; then
  CANDIDATE_JSON="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" "$TRANSCRIPT")"
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  CANDIDATE_JSON='{"mode":"error","candidates":[],"overflow":0,"detail":"candidate-extract.sh is missing or outdated."}'
fi

if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-render.sh" 1; then
  RENDERED="$(printf '%s' "$CANDIDATE_JSON" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-render.sh")"
else
  RENDERED="SC-FALLBACK: context-window — $SC_REQUIRE_SCRIPT_MSG"
fi
```

`candidate-extract.sh` times itself — do not wrap this call in a timer, and
do not add a `perf-log.sh record` line for `step-2-transcript-extraction`;
you would double-log it.

### Privacy

Relevant only in context-window mode — see
`skills/session-continuity/HEURISTICS.md`. Transcript-mode evidence is
already redacted by `candidate-extract.jq` before it reaches you.

### Output

`$RENDERED` starts with `SC-FALLBACK:` in exactly the cases where there is no
script-derived answer: no transcript, a stale or unreadable one, a
missing/outdated script, or extractor output the renderer could not parse.
That is your one branch:

- **`$RENDERED` starts with `SC-FALLBACK:`** — switch to context-window mode.
  Apply the heuristics in `skills/session-continuity/HEURISTICS.md` by hand
  against what you can still see in the conversation, skipping the
  wall-clock gates you cannot evaluate, render the result following that
  file's Presentation section, and append this line under the list:

  ```
  Note: session context may be compacted; some early-session events may not have surfaced.
  ```

- **Otherwise, print `$RENDERED` verbatim.** It is already the finished
  user-facing block: either the numbered candidate list with evidence
  bullets, a capture prompt, and (if candidates were capped) a `+N more
  candidates…` line; or the single no-op line `No LEARNINGS candidates
  surfaced from this session — Step 2 is a no-op.` (note "no new learnings"
  in Step 3's checklist when this is what printed); or `⚠️ LEARNINGS
  candidates unavailable: <detail>` when the plugin or its environment is
  broken. Do **not** treat the last case as "no candidates" — continue to
  Step 3 regardless.

If `$RENDERED` was the no-op line or the `⚠️` line, skip the capture prompt
entirely — there is nothing to capture.

### Capture flow — batch presentation, single confirm

For every candidate the user picked (e.g. "1, 3" or "all"), pre-draft the full LEARNINGS entry up front. Compose each per `commands/learning.md`'s structure:

- Pre-fill the **Title** from the candidate description.
- Pre-draft **The trap**, **Symptom**, **Fix**, and **Diagnostic signal** from session context. Do not invent details the session does not support — leave a field blank rather than fabricating.
- Choose section per **Step 3 of `commands/learning.md`**.
- Compute the next number per **Step 4 of `commands/learning.md`** (number entries sequentially within the chosen section).

If the user describes "another" candidate not on your list, treat that description as a pre-filled title and draft alongside the others.

**Single confirm prompt.** Present every pre-drafted entry together in one rendered block (numbered, full body, target section labeled). Before asking, log a prompt-shown marker (same mechanism as Step 1's prompts — isolates human-response wait from ritual compute time, see Step 4):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" mark --source=command --name=end-session --step=step-2-prompt-shown
```

Then ask one question:

> "Stage all N entries as drafted, revise specific ones, or skip any?"

Possible replies you must handle: "all" / "stage" → stage every draft; "revise N" → loop into edit-draft-N flow then re-present; "skip N" → drop draft N from the batch; "none" → stage nothing.

Once the answer arrives, log the wait duration:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-2-prompt-shown --emit-step=step-2-prompt-wait
```

Once the user confirms, insert each accepted draft at the top of its chosen section per **Step 5 of `commands/learning.md`**, then run the same index-regeneration script Step 6 of `commands/learning.md` calls (duplicated here deliberately — see Resolved decision 3 of the spec — rather than delegating, so this path can never leave the index stale regardless of whether a future change routes entries differently):

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 2; then
  if ! bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" reindex .session-continuity/LEARNINGS.md; then
    echo "⚠️ Symptoms index not regenerated — LEARNINGS.md was left untouched (see the message above)."
  fi
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG — Symptoms index not regenerated this run."
fi
git add .session-continuity/LEARNINGS.md
```

Do not loop one-prompt-per-candidate. The batch is the unit.

**Do not** commit. Staging only.

## Step 3 — Final checklist

One script call. Every row reflects actual repo state or a value you
decided in Step 1/Step 2 and pass through — never format or re-derive a row
by hand.

### Gather the facts and render

Run in **one Bash call**, timed. First, copy the Step 1 scratch TSV to a
location outside the repo and delete the in-repo copy — *before* any
git-status command runs, so the git commands below never see it (its path
can't be deleted-then-read, since `checklist-assemble.sh` needs to read it
after the git commands run; copying it out first is what makes both true
at once). Task 2's gitignore entry is the separate belt-and-suspenders case:
a ritual that crashes *before* this block ever runs leaves the file
in-repo, and only the gitignore entry (not this ordering) keeps it out of
a later `git ls-files --others`. Then run the seven git commands, then
build the JSON `checklist-assemble.sh` expects and pipe it through:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
TSV_INREPO=".session-continuity/.end-session-checklist.tsv"
TSV=""
if [[ -r "$TSV_INREPO" ]]; then
  TSV="$(mktemp)"
  cp "$TSV_INREPO" "$TSV"
  rm -f "$TSV_INREPO"
fi
BACKLOG_MODE="normal"   # set to none|unavailable|not-migrated|fast-path per Step 1's skip conditions/fast path instead, when applicable
BACKLOG_FASTPATH_COUNT="null"   # the fast path's <fast-path-backlog-count>, only when BACKLOG_MODE=fast-path

STAGED_JSON="$(git diff --cached --name-only | jq -R -s 'split("\n") | map(select(length>0))')"
UNSTAGED_JSON="$(git diff --name-only | jq -R -s 'split("\n") | map(select(length>0))')"
UNTRACKED_JSON="$(git ls-files --others --exclude-standard | jq -R -s 'split("\n") | map(select(length>0))')"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
if [[ "$BRANCH" == "HEAD" ]]; then DETACHED=true; else DETACHED=false; fi
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
UPSTREAM="$(git rev-parse --abbrev-ref @{u} 2>/dev/null || true)"
if [[ -z "$UPSTREAM" ]]; then UPSTREAM_JSON="null"; AHEAD_JSON="null"; else
  UPSTREAM_JSON="$(printf '%s' "$UPSTREAM" | jq -R .)"
  AHEAD="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
  AHEAD_JSON="$AHEAD"
fi

# PRIMER, LEARNINGS_JSON, COMMIT_SUBJECT_JSON: set these three from what
# Step 1/Step 2 actually did this invocation — see the field notes below.
PRIMER="current"            # "refreshed" | "closed" | "current"
LEARNINGS_JSON="[]"         # e.g. '[{"number":7,"title":"..."}]' from Step 2's captures
COMMIT_SUBJECT_JSON="null"  # a quoted JSON string, or "null", per the field note below

JSON_TMP="$(mktemp)"
jq -n \
  --argjson staged "$STAGED_JSON" --argjson unstaged "$UNSTAGED_JSON" \
  --argjson untracked "$UNTRACKED_JSON" --arg branch "$BRANCH" \
  --argjson detached "$DETACHED" --arg short_sha "$SHORT_SHA" \
  --argjson upstream "$UPSTREAM_JSON" --argjson ahead "$AHEAD_JSON" \
  --arg primer "$PRIMER" --argjson learnings "$LEARNINGS_JSON" \
  --arg backlog_mode "$BACKLOG_MODE" --argjson backlog_fastpath_count "$BACKLOG_FASTPATH_COUNT" \
  --argjson commit_subject "$COMMIT_SUBJECT_JSON" \
  '{staged:$staged, unstaged:$unstaged, untracked:$untracked, branch:$branch,
    detached:$detached, short_sha:$short_sha, upstream:$upstream, ahead:$ahead,
    primer:$primer, learnings:$learnings, backlog_mode:$backlog_mode,
    backlog_fastpath_count:$backlog_fastpath_count, commit_subject:$commit_subject}' \
  > "$JSON_TMP"

source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/checklist-assemble.sh" 1; then
  CHECKLIST="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/checklist-assemble.sh" "$TSV" < "$JSON_TMP")"
else
  CHECKLIST="⚠️ $SC_REQUIRE_SCRIPT_MSG"
fi
rm -f "$TSV" "$JSON_TMP"

_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-3-gather-facts --duration="$_PERF_DURATION"
echo "$CHECKLIST"
```

**Field notes — the values only you know, filled in before running the block above:**

- `BACKLOG_MODE` / `BACKLOG_FASTPATH_COUNT`: `"fast-path"` + the fast path's `<fast-path-backlog-count>` when Step 1's fast path fired; otherwise whichever of `none`/`unavailable`/`not-migrated`/`normal` Step 1's Backlog verification section landed on (its own skip conditions already tell you which).
- `TSV`: leave as computed above (empty string unless the in-repo scratch file existed and was copied out before deletion) — never override it by hand.
- `PRIMER`: `"refreshed"` if the refresh flow ran and staged the primer, `"closed"` if only the drift-clean close-candidate prompt ran and closed item(s), `"current"` if Step 1 was a no-op (fast path or drift-clean-zero-candidates).
- `LEARNINGS_JSON`: the accepted drafts from Step 2's capture flow, as `[{"number":N,"title":"..."}]`; `[]` if Step 2 captured nothing.
- `COMMIT_SUBJECT_JSON`: `"null"` (the bare word, unquoted) unless staged files exist AND at least one is outside `.session-continuity/` — in that case, a quoted JSON string with your conventional-commit subject (`<type>(<scope>): <subject>`, ≤72 chars), e.g. `'"fix(ci): extract CHANGELOG section with proper awk range"'`. Pick the theme from the most prominent captured learning's title, or the primary code-change theme — same judgment call as before this phase, just handed to the script instead of formatted by hand.

**Output.** If `$CHECKLIST` starts with `⚠️` (the `require_script` failure) or `SC-FALLBACK:` (the script's own malformed-input escape), print it as a single warning line and assemble the checklist by hand this one time, following the row table that existed before this phase (Primer refresh / New learnings / Backlog / Staged files / Unstaged modifications / Untracked files / Unpushed commits / Suggested commit, each ✓/⚠️/→, backlog citing evidence for `appears-DONE` only) — then still emit the terminal sign-off line yourself: `✅ Session complete. Safe to close.` if every row you assembled was ✓, or `✅ Session complete. Safe to close. (Warnings above are advisory — review before closing if relevant.)` if any row carries ⚠️. Otherwise, relay the block's printed checklist unchanged — it already ends with the terminal sign-off line; do not print anything after it except whatever Step 4's timing calls require.

## Step 4 — Ritual timing (always)

Step 3's `$CHECKLIST` already ended with the terminal sign-off line — this
step prints nothing of its own. It only logs how long the ritual took, so
the log carries one real end-to-end number per invocation.

**Before that line, record total ritual time.** Each step above only timed
its own Bash block, not the gaps between them — this reads back this
invocation's own `step-1-fast-path` timestamp (always the first thing every
invocation logs, fast-path or not) and diffs it against now, so the log
carries one real end-to-end number per invocation alongside the per-step
ones. Skip the log call entirely rather than record a bogus duration if the
mark is missing or unparseable — `since` already does this silently:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --source=command --name=end-session --mark-step=step-1-fast-path --emit-step=step-4-ritual-complete
```

**Then derive agent-active time** — `step-4-ritual-complete` is real wall
clock, but it includes however long the user took to answer any prompts
along the way. Rather than subtract specific prompt-wait markers (the old
approach, retired — see
`meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md`
Change 2 for why a two-marker subtraction can't be made correct), derive
active time directly from the transcript. Resolve both the transcript and
the start epoch again here — this is a separate Bash call from Step 2's and
from the `since` call above, and shell state does not persist across Bash
calls, so neither Step 2's `$TRANSCRIPT` nor a `$start_epoch` set above
would be visible here even if it were still computed as a shell variable
(the previous version of this block was exactly this bug — backlog item
`52dc` — depending on `$start_epoch` across that same boundary):

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
STEP4_TRANSCRIPT=""
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh" 1; then
  STEP4_TRANSCRIPT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/resolve-transcript.sh")"
fi
START_EPOCH="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" since --print-epoch --name=end-session --mark-step=step-1-fast-path)"
if [[ "$START_EPOCH" =~ ^[0-9]+$ ]] && [[ -n "$STEP4_TRANSCRIPT" ]]; then
  if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" 1; then
    AGENT_ACTIVE="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/agent-active.sh" "$STEP4_TRANSCRIPT" "$START_EPOCH")"
    if [[ -n "$AGENT_ACTIVE" ]]; then
      bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-4-agent-active --duration="$AGENT_ACTIVE"
    fi
  else
    echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  fi
fi
```

If `resolve-transcript.sh` prints nothing (no readable `.jsonl` under this
session's transcript directory, or the script is missing/outdated), this
block is skipped entirely — no `step-4-agent-active` line is logged for
this invocation, same "skip rather than log a wrong number" rule that
already governs the rest of this design.

**Never ask follow-up questions after Step 3's sign-off line printed.** It marks the end of the ritual. If the user wants to act on a warning, they will reply on their own.

## Notes

- **Never commit automatically.** Stage only, across both Step 1 and Step 2.
- **Never push.** The checklist flags unpushed commits; the user decides.
- **Never invent LEARNINGS details.** If you can't draft a field from session context, leave it blank and ask the user — same rule as `/session-continuity:learning`.
- **Reflection is bounded by the current session.** Step 2 looks only at this conversation's context. Bugs from prior sessions, parallel worktrees, or separate Claude instances (subagents, different windows) aren't visible and won't be proposed. For those, the user should invoke `/session-continuity:learning` directly.
- **`step-4-ritual-complete` includes human response time, by design.** It is real wall clock from this invocation's first log line to its last, and that necessarily spans however long the user took to answer the Step 1 and Step 2 prompts. `step-4-agent-active` (same block) derives the agent's own active time directly from the transcript, isolating the agent's own processing time. When investigating a slow ritual, compare both numbers before assuming a script regression — a large `step-4-ritual-complete` with a small `step-4-agent-active` means the user was away from the keyboard, not that anything got slower.
- **Respect the primer-only-commit rule.** If the user, after seeing the checklist, commits only the primer, the `PreToolUse` hook's nudge still applies — nothing to do here.
- **Zero arguments.** If the user passed text after `/session-continuity:end-session`, ignore it — session reflection provides all context needed.
- **Bound the prompt count.** The whole ritual must fit ≤2 user prompts in the common case: one Step 1 prompt (the full combined prompt when drift exists, or the lighter drift-clean close-candidate prompt when drift is clean but `appears-DONE` items exist), one batch confirm in Step 2 (only when candidates surface). Drift-clean + zero candidates = zero prompts; drift-clean + ≥1 candidate = exactly one (lightweight) prompt. Never split Step 1's prompt into two sequential asks. Never loop one-prompt-per-candidate in Step 2.
- **Always sign off.** Step 4's terminal line is non-negotiable — the user invoked an explicit close-out and must not be left ambiguous about whether the ritual is done.
- **Backlog verdicts never mutate the primer.** The verification in
  Step 1 only classifies and reports; an `appears-DONE` item is removed only if
  the user confirms it at a Step 1 prompt (full combined prompt or the
  drift-clean close-candidate prompt). Declining either prompt leaves the item
  as a standing ⚠️ in the checklist, never a silent deletion.
