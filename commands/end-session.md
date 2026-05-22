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

If either is missing, check the pre-v0.5.0 legacy path (`docs/SESSION_PRIMER.md`, `docs/LEARNINGS.md`):

- If either legacy file exists, tell the user:

  > "Found session-continuity files at `docs/` (the pre-v0.5.0 location). Run `/session-continuity:primer` first — it will migrate the files to `.session-continuity/`. Then re-run `/session-continuity:end-session`."

  Exit.
- Else tell the user:

  > "No `.session-continuity/SESSION_PRIMER.md` (or `.session-continuity/LEARNINGS.md`) found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

  Exit. Do not proceed.

## Step 1 — Refresh the primer (drift-gated)

Before prompting the user for anything, run a drift check. The goal: if the primer is already in sync with the repo, do nothing and record a no-op. Only enter the refresh flow when something actually changed.

### Drift check (silent — no user prompt)

Read `.session-continuity/SESSION_PRIMER.md` and compare its `git log --oneline -5` block to the actual output of `git log --oneline -5` against the primary branch. Two outcomes:

- **Block matches.** Treat the primer as current. Do NOT prompt for outstanding-items changes. Skip the rest of Step 1. In Step 3's checklist, record the Primer refresh row as ✓ "Primer already current (no-op)".
- **Block differs** (any line differs — subjects, hashes, or ordering). Enter the refresh flow below.

If the primer has a test-counts section, optionally re-run the test command(s) to confirm the counts are still accurate. **Retry flaky suites up to 3× before reporting drift** (per Step 5.3 of `commands/primer.md`); pin to the count seen in ≥2 of 3 runs and only flag drift if all three runs agree on a number that differs from the primer. Count mismatches that survive the retry count as drift.

### Refresh flow (runs only when drift was detected)

Follow the logic in **Step 5 of `commands/primer.md`** (refresh mode):

1. Regenerate the `git log --oneline -5` block with current output.
2. If the primer has a test-counts section and the counts changed (after the 3× retry), update them to match current output.
3. **Surface commits since the last primer refresh, with outstanding-items overlay.** Run `git log <last-primer-commit>..HEAD --oneline` (where `<last-primer-commit>` is the output of `git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md`, falling back to `docs/SESSION_PRIMER.md` for legacy repos). Present the subject list as candidate prompts.

   Then compute an **outstanding-items overlay** for each subject:

   - Tokenize the subject: lowercase, split on non-alphanumeric, drop tokens of length <3, drop the stopword list below.
   - For each top-level numbered item under the primer's `## Outstanding items` heading: tokenize the item text the same way, capped at the first 200 characters of the item (numbered line plus indented continuation lines until the next top-level number; sub-bullets roll up to their parent item).
   - Match if the intersection of subject tokens and item tokens has cardinality ≥ 3.

   **Stopwords** (extend per project as needed):

   ```
   the and for fix add update from with into feat chore docs primer learnings session continuity tag version release
   ```

   **Presentation.** When matches exist, append a "May close outstanding items" block under the raw subject list, citing each `<sha> → item #<N> ("<first 60 chars of item>")`. When no matches exist, omit the block entirely (do not print an empty section). Then ask: "Any of these resolve outstanding items, or warrant a new LEARNINGS entry?"

   **Refusal.** Never close an outstanding item without explicit user confirmation. The overlay is a candidate list, not an auto-close.

   **Skip conditions.** If the primer lacks an `^## Outstanding items` heading (custom-modified primer), skip the overlay silently — the raw subject list still appears.
4. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?" **Wait for their answer before continuing.** Do not preemptively edit the list, clear items you interpret as "stale," or proceed with Step 5 based on your own reading.
5. Apply the edits the user specified. If the user replied "nothing to change" (or similar), skip this step.
6. Stage the updated primer: `git add .session-continuity/SESSION_PRIMER.md`.

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

Group consecutive Bash tool calls by **normalized command**:

- Strip arguments after the first newline (heredocs collapse to their
  command head).
- Collapse runs of whitespace to single spaces.
- Drop pure-read commands: `cat`, `ls`, `grep`, `find`, `stat`,
  `pwd`, `which`, `echo`. (These are noise — not investigatory
  retries.)

**Trigger:** the same normalized command appears ≥3 times in the
session.

**Candidate title:** `<command> — investigated for N retries.`

**Evidence:** up to 3 of the invocation timestamps + exit codes
(redact stdout/stderr beyond the first error line).

#### Heuristic B — revert / reset

**Trigger:** any Bash invocation matching one of:

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

For each tool result with non-empty stderr OR a tool output line
prefixed `Error:`, extract the **error string**:

- First non-empty line of stderr, or
- The `Error:`-prefixed line, whichever appears first.

**Normalize the error string:**

- Strip absolute paths to basenames.
- Strip line:column references (e.g. `:42:7`).
- Strip ISO-8601 and `HH:MM:SS` timestamps.
- Strip hex addresses (`0x[0-9a-f]+`).

**Trigger:** the same normalized error string appears ≥3 times AND
the first and last occurrences span ≥15 minutes (use timestamps from
the JSONL `timestamp` field; in context-window fallback skip the
wall-clock gate and trigger on count alone).

**Candidate title:** `<error string> — recurred N times over M minutes.`

**Evidence:** up to 3 invocation citations spanning the timeline.

#### Heuristic D — fix burst

**Trigger:** a commit with subject matching `^fix(\(.+\))?: ` (Bash
invocation matching `git commit -m "fix...` or `git commit ... -m`
with such a subject) preceded by ≥10 Bash tool calls within the prior
30 minutes (count both successful and failing invocations; use
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

### Capture flow for each accepted candidate

For each candidate the user picks, compose the LEARNINGS entry following `commands/learning.md`'s structure. Replace its Step 2 (field-by-field prompting) with pre-drafting:

- Pre-fill the **Title** from the candidate description.
- Pre-draft **The trap**, **Symptom**, **Fix**, and **Diagnostic signal** from session context where you can, then present the full draft to the user in one go for confirmation / revision. Do not invent details the session does not support — leave a field blank and ask if unclear.
- Choose section per **Step 3 of `commands/learning.md`**.
- Compute the next number per **Step 4 of `commands/learning.md`**.
- Insert at the top of the chosen section per **Step 5 of `commands/learning.md`**.
- Stage per **Step 6 of `commands/learning.md`**: `git add .session-continuity/LEARNINGS.md`.

If the user describes "another" candidate not on your list, treat that description as a pre-filled title and follow the same flow.

**Do not** commit. Staging only.

## Step 3 — Final checklist

Run real git commands and emit a structured checklist. Every item must reflect actual repo state, not an assertion.

### Gather the facts

Run each of these and record the results:

```bash
git diff --cached --name-only          # staged files
git diff --name-only                    # unstaged modifications
git ls-files --others --exclude-standard   # untracked (ignoring .gitignore'd)
git rev-parse --abbrev-ref HEAD         # current branch (or "HEAD" if detached)
git rev-parse --abbrev-ref @{u} 2>/dev/null  # upstream branch, or empty if none
git rev-list --count @{u}..HEAD 2>/dev/null  # unpushed commits, empty if no upstream
```

Handle these edge cases explicitly:

- **Not a git repo.** If `git rev-parse` fails, the precondition in Step 0 should have caught this, but belt-and-suspenders: report "⚠️ not inside a git repo" once and skip git-dependent rows.
- **Detached HEAD.** `git rev-parse --abbrev-ref HEAD` returns `HEAD`. Note "⚠️ detached HEAD at `<short-sha>`" in the unpushed-commits row.
- **No upstream.** `git rev-parse --abbrev-ref @{u}` fails. Note "⚠️ branch `<name>` has no upstream — set one with `git push -u origin <name>`" in the unpushed-commits row.

### Emit the checklist

**List every file enumerated by the git commands — do not summarize, filter, or pick a "primary" one.** If `git diff --cached --name-only` returns three files, the "Staged files" row lists all three. Same rule for the Unstaged and Untracked rows. The suggested-commit message may emphasize one theme, but the checklist rows are inventories, not summaries.

Output using this structure. Use ✓ (green), ⚠️ (yellow), or → (suggestion):

| Row | Marker | Content |
|---|---|---|
| Primer refresh | ✓ | "Primer refreshed and staged" OR "Primer already current (no-op)" |
| New learnings | ✓ | "N LEARNINGS entry/entries captured (#X, \"<title>\" …)" OR "No new learnings" |
| Staged files | ✓ | "Staged: <file1>, <file2>, …" OR "Nothing staged" |
| Unstaged modifications | ✓ if none, else ⚠️ | "No unstaged modifications" OR "⚠️ Unstaged: <file1>, <file2>, …" |
| Untracked files | ✓ if none, else ⚠️ | "No untracked files" OR "⚠️ N untracked: <file1>, <file2>, … — ignore, add, or delete?" |
| Unpushed commits | ✓ / ⚠️ | "Up to date with origin/<branch>" OR "⚠️ Branch <name> is N commits ahead of origin — push before closing?" OR the detached-HEAD / no-upstream variants |
| Suggested commit | → | Derived from staged files + captured learnings. Omit row entirely if nothing is staged. |

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
✓ Staged: .session-continuity/SESSION_PRIMER.md, .session-continuity/LEARNINGS.md, .github/workflows/release.yml
✓ No unstaged modifications
⚠️ 2 untracked files: scratch.md, tmp/debug.log — ignore, add, or delete?
⚠️ Branch "main" is 3 commits ahead of origin — push before closing?
→ Suggested:
    git commit -m "fix(ci): extract CHANGELOG section with proper awk range"
```

## Notes

- **Never commit automatically.** Stage only, across both Step 1 and Step 2.
- **Never push.** The checklist flags unpushed commits; the user decides.
- **Never invent LEARNINGS details.** If you can't draft a field from session context, leave it blank and ask the user — same rule as `/session-continuity:learning`.
- **Reflection is bounded by the current session.** Step 2 looks only at this conversation's context. Bugs from prior sessions, parallel worktrees, or separate Claude instances (subagents, different windows) aren't visible and won't be proposed. For those, the user should invoke `/session-continuity:learning` directly.
- **Respect the primer-only-commit rule.** If the user, after seeing the checklist, commits only the primer, the `PreToolUse` hook's nudge still applies — nothing to do here.
- **Zero arguments.** If the user passed text after `/session-continuity:end-session`, ignore it — session reflection provides all context needed.
