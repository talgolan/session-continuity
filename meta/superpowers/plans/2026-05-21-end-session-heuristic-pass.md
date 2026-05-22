# End-Session Heuristic Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic candidate-surfacing heuristics to `/session-continuity:end-session` (§1 outstanding-items match in Step 1; §5 LEARNINGS heuristics in Step 2). Surfacing only — never auto-acts.

**Architecture:** Pure prose-skill change to `commands/end-session.md`. No new files, hooks, or schemas. The skill body documents heuristics that Claude applies at runtime. Transcript file at `~/.claude/projects/<encoded-cwd>/*.jsonl` is the preferred input source for §5 with context-window fallback.

**Tech Stack:** Markdown (skill body), Bash (validation), Git (commits). No code added — Claude executes heuristics by following skill prose at command-invocation time.

**Spec:** `meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `commands/end-session.md` | Modify | Add §1 overlay logic to Step 1 inheritance; replace Step 2 prose criteria with four explicit heuristics + transcript-resolution prose. |
| `.claude-plugin/plugin.json` | Modify | Bump version `0.5.1` → `0.6.0`. |
| `CHANGELOG.md` | Modify | Add `[0.6.0]` entry above `[0.5.1]`. |
| `.session-continuity/SESSION_PRIMER.md` | Modify | Refresh "Current state" + add new outstanding item for v0.6.0 follow-ups (the deferred-recommendations list shrinks). |
| `meta/superpowers/validation/2026-05-21-end-session-heuristics.md` | Create | Manual-validation log capturing the five fixture scenarios + dogfood test results. |

No source code files exist in this repo (markdown + shell scripts only). Each modification is self-contained and reviewable as a unit.

---

## Task 1: Document the §1 outstanding-items overlay in Step 1

**Files:**
- Modify: `commands/end-session.md` (Step 1, "Refresh flow" subsection)

- [ ] **Step 1.1: Read the current Step 1 prose.**

Open `commands/end-session.md`. Locate the section starting with `### Refresh flow (runs only when drift was detected)` and ending before `## Step 2 — Session reflection for learnings`.

The current numbered list has 6 items (after the v0.5.1 patch):

```
1. Regenerate the `git log --oneline -5` block with current output.
2. If the primer has a test-counts section and the counts changed (after the 3× retry), update them to match current output.
3. Surface the commits since the last primer refresh as a candidate list (per Step 5.4 of `commands/primer.md`): run `git log <last-primer-commit>..HEAD --oneline` and present the subjects so the user can decide whether any close outstanding items or warrant a new LEARNINGS entry.
4. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?" **Wait for their answer before continuing.** Do not preemptively edit the list, clear items you interpret as "stale," or proceed with Step 5 based on your own reading.
5. Apply the edits the user specified. If the user replied "nothing to change" (or similar), skip this step.
6. Stage the updated primer: `git add .session-continuity/SESSION_PRIMER.md`.
```

Item 3 is the v0.5.1 candidate-surfacing addition. Item 3 is the insertion point for the §1 overlay — it currently surfaces *raw* subjects; the overlay adds matched-item annotations.

- [ ] **Step 1.2: Replace item 3 with the overlay prose.**

Use the Edit tool. Replace this exact `old_string`:

```
3. Surface the commits since the last primer refresh as a candidate list (per Step 5.4 of `commands/primer.md`): run `git log <last-primer-commit>..HEAD --oneline` and present the subjects so the user can decide whether any close outstanding items or warrant a new LEARNINGS entry.
```

with this `new_string`:

```
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
```

- [ ] **Step 1.3: Renumber the items below item 3 if needed.**

The item numbers don't need renumbering — items 4–6 stay as 4–6 since item 3 is replaced in place (not split into 3a/3b).

- [ ] **Step 1.4: Verify the edit landed.**

Run:

```bash
grep -n "outstanding-items overlay" commands/end-session.md
```

Expected: one match line, around line 50-something. Confirms the new prose is in place.

- [ ] **Step 1.5: Commit Task 1.**

```bash
git add commands/end-session.md
git commit -m "feat(end-session): outstanding-items overlay in Step 1

Step 1's commit-subject candidate list (introduced in v0.5.1) now
includes a stem-intersection overlay against the primer's
'## Outstanding items' section. Subjects sharing ≥3 token stems with
an open item are flagged 'may close item #N' alongside the raw list.

Stopwords + threshold defined inline in the skill body so each
project can tune them without touching code. Refuses to auto-close;
user confirms before any item is removed.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md §1"
```

---

## Task 2: Document the §5 transcript-resolution preamble for Step 2

**Files:**
- Modify: `commands/end-session.md` (Step 2 introduction)

- [ ] **Step 2.1: Read the current Step 2 introduction.**

Locate the section starting with `## Step 2 — Session reflection for learnings` and ending at `### Presentation` (the existing menu format heading).

The current introduction reads:

```
## Step 2 — Session reflection for learnings

Review this session's conversation context and surface candidates for new LEARNINGS entries.

**A candidate is worth surfacing when:**
- A problem took multiple attempts or involved a wrong theory before the right fix landed.
- A platform or tool quirk surprised us (hook behavior, CLI defaults, API shape).
- The final code relies on a workaround whose reasoning isn't obvious from reading it.

**Not candidates:**
- Routine implementation ("wrote the endpoint, tests passed first try").
- Decisions that are already captured in commit messages or spec docs.
- Things the user already knew going in.
```

This will be replaced wholesale with the heuristic-driven version in Tasks 2 + 3 + 4.

- [ ] **Step 2.2: Replace the introduction with the transcript-resolution preamble.**

Use the Edit tool. Replace this exact `old_string`:

```
## Step 2 — Session reflection for learnings

Review this session's conversation context and surface candidates for new LEARNINGS entries.

**A candidate is worth surfacing when:**
- A problem took multiple attempts or involved a wrong theory before the right fix landed.
- A platform or tool quirk surprised us (hook behavior, CLI defaults, API shape).
- The final code relies on a workaround whose reasoning isn't obvious from reading it.

**Not candidates:**
- Routine implementation ("wrote the endpoint, tests passed first try").
- Decisions that are already captured in commit messages or spec docs.
- Things the user already knew going in.
```

with this `new_string`:

```
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

(Tasks 2 of this plan inserts the preamble; Task 3 inserts the four
heuristic specs that follow this anchor in subsequent edits.)
```

Note the closing parenthetical — Task 3 will replace it with the actual heuristic list.

- [ ] **Step 2.3: Verify the edit landed.**

Run:

```bash
grep -n "Resolution order" commands/end-session.md
```

Expected: one match. Confirms the preamble is in place.

- [ ] **Step 2.4: Commit Task 2.**

```bash
git add commands/end-session.md
git commit -m "feat(end-session): transcript-resolution preamble for Step 2

Step 2 now starts with explicit transcript-file resolution prose:
prefer ~/.claude/projects/<encoded-cwd>/*.jsonl, fall back to
context-window mode on any failure. URL-encoding rule documented
inline. Privacy section requires paraphrasing tool inputs/outputs
in heuristic evidence — never quote raw stdout/stderr.

The four heuristics themselves land in the next commit.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md §5"
```

---

## Task 3: Document the four §5 heuristics

**Files:**
- Modify: `commands/end-session.md` (Step 2, after the preamble from Task 2)

- [ ] **Step 3.1: Replace the placeholder parenthetical with the four heuristic specs.**

Use the Edit tool. Replace this exact `old_string`:

```
### Heuristics

(Tasks 2 of this plan inserts the preamble; Task 3 inserts the four
heuristic specs that follow this anchor in subsequent edits.)
```

with this `new_string`:

```
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
```

- [ ] **Step 3.2: Verify the edit landed.**

Run:

```bash
grep -nE "Heuristic [ABCD] —" commands/end-session.md
```

Expected: four matches, in order A → B → C → D.

- [ ] **Step 3.3: Commit Task 3.**

```bash
git add commands/end-session.md
git commit -m "feat(end-session): four LEARNINGS-candidate heuristics

Step 2 now applies four deterministic heuristics in sequence:
- Heuristic A: retry burst (≥3 identical normalized Bash commands)
- Heuristic B: revert/reset (git reset --hard, revert, etc.)
- Heuristic C: error recurrence (≥3× same error over ≥15 min)
- Heuristic D: fix burst (fix-commit preceded by ≥10 Bash calls)

Output is the union, deduplicated by title (>70% overlap), capped at
5 candidates. Zero candidates is a valid outcome — prints a no-op
message and proceeds to Step 3.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md §5"
```

---

## Task 4: Update the Step 2 presentation block to match heuristic output

**Files:**
- Modify: `commands/end-session.md` (Step 2, "Presentation" subsection)

- [ ] **Step 4.1: Read the current Presentation subsection.**

Locate the section starting with `### Presentation` under Step 2. The current content reads:

```
### Presentation

Show candidates as a numbered menu:

\`\`\`
A few things from this session looked like LEARNINGS candidates:

1. <one-line description of candidate 1>
2. <one-line description of candidate 2>

Capture any of these? (1, 2, both, none, or describe another)
\`\`\`

If you find **zero** candidates, skip the prompt and note "no new learnings" in Step 3's checklist.
```

Note: the actual file uses real triple-backticks, not escaped. Read the file before editing to see exact whitespace.

- [ ] **Step 4.2: Replace the presentation prose with the heuristic-annotated format.**

Use the Edit tool. Replace this exact `old_string` (with real backticks):

````
### Presentation

Show candidates as a numbered menu:

```
A few things from this session looked like LEARNINGS candidates:

1. <one-line description of candidate 1>
2. <one-line description of candidate 2>

Capture any of these? (1, 2, both, none, or describe another)
```

If you find **zero** candidates, skip the prompt and note "no new learnings" in Step 3's checklist.
````

with this `new_string`:

````
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
````

- [ ] **Step 4.3: Verify the edit landed.**

Run:

```bash
grep -n "heuristic-id" commands/end-session.md
```

Expected: at least one match within Step 2's Presentation subsection.

- [ ] **Step 4.4: Commit Task 4.**

```bash
git add commands/end-session.md
git commit -m "feat(end-session): heuristic-annotated candidate presentation

Step 2's candidate menu now tags each entry with [heuristic-id]
(retry-burst / revert / error-recurrence / fix-burst) and includes
indented evidence bullets. Cap-overflow notice and context-window-
mode caveat are explicit. Zero-candidates path prints an explicit
no-op message rather than silently skipping.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md §5"
```

---

## Task 5: Bump version + update CHANGELOG

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

- [ ] **Step 5.1: Bump plugin.json.**

Use the Edit tool on `.claude-plugin/plugin.json`. Replace:

```
  "version": "0.5.1",
```

with:

```
  "version": "0.6.0",
```

- [ ] **Step 5.2: Add the v0.6.0 CHANGELOG entry.**

Use the Edit tool on `CHANGELOG.md`. Replace this exact `old_string`:

```
## [0.5.1] — 2026-05-21
```

with this `new_string`:

```
## [0.6.0] — 2026-05-21

### Added
- **§1 outstanding-items overlay in `/session-continuity:end-session` Step 1.** v0.5.1 surfaces commit subjects since the last primer refresh; v0.6.0 adds an overlay that flags subjects sharing ≥3 token stems with an open outstanding item ("may close item #N"). Stopwords and threshold are documented inline in the skill body so projects can tune them. Strictly a candidate list — never auto-closes.
- **§5 four LEARNINGS-candidate heuristics in `/session-continuity:end-session` Step 2.** Replaces the prose criteria from earlier versions with deterministic detectors:
  - **Heuristic A — retry burst:** ≥3 identical normalized Bash commands (excluding pure-read commands like `cat`/`ls`/`grep`).
  - **Heuristic B — revert / reset:** any of `git reset --hard`, `git checkout -- <path>`, `git revert`, `git restore`, or `rm -rf` against a tracked file.
  - **Heuristic C — error recurrence:** the same normalized error string ≥3 times across ≥15 minutes (timestamps from JSONL; falls back to count-only in context-window mode).
  - **Heuristic D — fix burst:** a `fix(...): ` commit preceded by ≥10 Bash calls within the prior 30 minutes.
- **Transcript-file input source for Step 2 heuristics.** Step 2 now prefers the session transcript at `~/.claude/projects/<url-encoded-cwd>/<session-id>.jsonl` when resolvable, falling back to context-window mode on any failure (missing dir, stale mtime, encoding mismatch). The fallback prints a "session context may be compacted" caveat under the candidate list so the user knows the recall is bounded.

### Changed
- **Step 2 presentation format.** Candidates now carry a `[heuristic-id]` tag and indented evidence bullets. The cap is 5 candidates per invocation — additional triggers print a "+N more not shown" line and ask the user to capture these first and re-run.
- **Privacy guidance.** Step 2's preamble now says explicitly: heuristic evidence paraphrases tool inputs and never quotes raw stdout/stderr beyond the first error line of a failing call.

### Compatibility
- Pure prose-skill addition. No new files, hooks, schemas, or path changes. Existing v0.5.x installs upgrade with no migration. Old primers without an `^## Outstanding items` heading silently skip the §1 overlay; the raw subject list (v0.5.1 behavior) still appears.

## [0.5.1] — 2026-05-21
```

- [ ] **Step 5.3: Verify both files.**

Run:

```bash
grep '"version"' .claude-plugin/plugin.json
head -5 CHANGELOG.md
```

Expected: version line shows `0.6.0`; CHANGELOG starts with `# Changelog` then the v0.6.0 heading appears as the most recent entry.

- [ ] **Step 5.4: Commit Task 5.**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: bump to v0.6.0 + CHANGELOG entry

v0.6.0 adds the §1 outstanding-items overlay and §5 four-heuristic
LEARNINGS candidate surfacing to /session-continuity:end-session.
Pure prose-skill addition — no new files, hooks, or schemas. Existing
v0.5.x installs upgrade with no migration.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md"
```

---

## Task 6: Refresh primer for v0.6.0

**Files:**
- Modify: `.session-continuity/SESSION_PRIMER.md`

- [ ] **Step 6.1: Update the `git log --oneline -5` block.**

Run:

```bash
git log --oneline -5
```

Capture the output. Use the Edit tool on `.session-continuity/SESSION_PRIMER.md`. Replace the existing log block (find it under `**Current `git log --oneline -5` (primary branch):**`) with the new output verbatim.

The current block starts with `aff74c3 feat!: relocate session-continuity files to .session-continuity/` and contains five lines. After Task 5's commit, the block should start with the v0.6.0 chore commit and contain the five most recent commits including Tasks 1–5's commits. Some Task commits may roll off the bottom — that's fine.

- [ ] **Step 6.2: Update the "Current state" section.**

Use the Edit tool. Replace this exact `old_string`:

```
- v0.5.1 staged on `feat/primer-improvements` — quick-win refinements distilled from the `meta/superpowers/recommendations/improvements_20260521.md` feedback doc. Five changes: drop the mtime drift check, retry flaky test counts up to 3× before reporting drift, surface `git log <last-primer>..HEAD` as candidate prompts during refresh, harden `learning` skill numbering (uniqueness guard + max-across-all + auto-bumped footer), and emit a 4-line status block from the `SessionStart` hook. See the v0.5.1 CHANGELOG entry for the full diff.
- v0.5.0 (committed in `aff74c3`) relocated the two files from `docs/` to `.session-continuity/` with auto-migration support. v0.5.1 makes no path or schema changes — pure refinements.
```

with this `new_string`:

```
- v0.6.0 staged on `feat/end-session-heuristics` — adds the §1 outstanding-items overlay and §5 four-heuristic LEARNINGS candidate surfacing to `/session-continuity:end-session`. Pure prose-skill addition; no new files, hooks, or schemas. See the v0.6.0 CHANGELOG entry for the full diff.
- v0.5.1 (commit `f5013e1`) shipped quick-win refinements: drop the mtime drift check, 3× test-flake retry, `git log <last-primer>..HEAD` candidate surfacing, hardened `learning` numbering, and a 4-line `SessionStart` status block.
- v0.5.0 (commit `aff74c3`) relocated the two files from `docs/` to `.session-continuity/` with auto-migration support.
```

- [ ] **Step 6.3: Update the Outstanding items section.**

The outstanding-items list in the primer needs three updates:

1. Item #1 — "Land v0.5.1 on `main` and tag" — already shipped (commit `f5013e1` on main, tag `v0.5.1` pushed). Replace with the v0.6.0 equivalent.
2. Item #2 — "Submit to the Anthropic marketplace" — version reference bumps from 0.5.1 to 0.6.0.
3. Item #3 — "Deferred recommendations" — sub-bullets for §1 and §5 now done; remove them.

Use the Edit tool. Replace this exact `old_string`:

```
1. **Land v0.5.1 on `main` and tag.** Merge `feat/primer-improvements` into `main`, then `git tag v0.5.1 && git push origin v0.5.1` to fire the release workflow. v0.5.0 still untagged — the same release pass should cover v0.5.0 + v0.5.1 (or land v0.5.1 directly and skip the v0.5.0 tag, since they ship together to npm/marketplace).

2. **Submit to the Anthropic marketplace.** Form answers in `meta/administrative/marketplace-submission.md`. Bump the "Version at submission" field in that file to 0.5.1 before submitting.

3. **Deferred recommendations from `meta/superpowers/recommendations/improvements_20260521.md`** (rejected or not-yet-prioritized — see commit `<v0.5.1-sha>` for rationale):
   - §2 branch-aware primer-only rule (rejected: edge case, current escape hatch sufficient).
   - §4.2 slug-based cross-refs `[[name]]` in LEARNINGS (defer until cross-ref count >20).
   - §4.3 auto-generated symptoms index at top of LEARNINGS (defer; symptom grep already works).
   - §6 split primer into volatile/stable halves (rejected: doubles maintenance, "one file = one mental model").
   - §7 JSON sidecar lock for primer fields (rejected: kills `vim docs/SESSION_PRIMER.md` flow).
   - §8 caveman/cavecrew cross-plugin integration (skip; presumes §6).
   - §9.6 dev-mode plugin install template-path fallback (low priority bug, one-line fix when it bites).
   - §1 outstanding-items state machine + auto-close from commit subjects (research arc; for now v0.5.1 surfaces candidates only).
   - §5 end-session auto-trigger heuristics (research arc; manual `/end-session` covers the half that works).
```

with this `new_string`:

```
1. **Land v0.6.0 on `main` and tag.** Merge `feat/end-session-heuristics` into `main`, then `git tag v0.6.0 && git push origin v0.6.0` to fire the release workflow.

2. **Submit to the Anthropic marketplace.** Form answers in `meta/administrative/marketplace-submission.md`. Bump the "Version at submission" field in that file to 0.6.0 before submitting.

3. **Deferred recommendations from `meta/superpowers/recommendations/improvements_20260521.md`** (rejected or not-yet-prioritized — v0.5.1 + v0.6.0 shipped the items deemed high-value):
   - §2 branch-aware primer-only rule (rejected: edge case, current escape hatch sufficient).
   - §3 init-mode auto-derivation (deferred — friction is real but bounded).
   - §4.2 slug-based cross-refs `[[name]]` in LEARNINGS (defer until cross-ref count >20).
   - §4.3 auto-generated symptoms index at top of LEARNINGS (defer; symptom grep already works).
   - §6 split primer into volatile/stable halves (rejected: doubles maintenance, "one file = one mental model").
   - §7 JSON sidecar lock for primer fields (rejected: kills `vim docs/SESSION_PRIMER.md` flow).
   - §8 caveman/cavecrew cross-plugin integration (skip; presumes §6).
   - §9.1 merge primer with auto-memory `MEMORY.md` (deferred — separate-systems boundary worth keeping).
   - §9.5 outstanding-items as YAML (deferred — markdown sub-bullets work today).
   - §9.6 dev-mode plugin install template-path fallback (low priority bug, one-line fix when it bites).
```

- [ ] **Step 6.4: Verify the edits landed.**

Run:

```bash
grep -nE "v0\\.6\\.0" .session-continuity/SESSION_PRIMER.md
```

Expected: at least 3 matches (Current state line, Outstanding item #1, Outstanding item #2).

- [ ] **Step 6.5: Commit Task 6.**

```bash
git add .session-continuity/SESSION_PRIMER.md
git commit -m "docs(primer): refresh for v0.6.0

Update Current state to reference the v0.6.0 feature branch + the
new end-session heuristic-pass behavior. Reset Outstanding item #1
to point at the v0.6.0 release task; bump marketplace-submission
version reference. Trim §1 and §5 sub-bullets from the deferred
recommendations list (now shipped) and add §3, §9.1, §9.5 from the
recommendations doc that aren't planned for now.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md"
```

---

## Task 7: Run scenario 1 of the validation matrix (clean repo, no commits)

**Files:**
- Create: `meta/superpowers/validation/2026-05-21-end-session-heuristics.md`

- [ ] **Step 7.1: Verify the precondition.**

Run:

```bash
git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md
git rev-parse HEAD
```

Expected: the two SHAs may differ if there have been commits since Task 6 (there shouldn't be in this isolated work). For scenario 1's purpose, ensure the primer's last commit equals HEAD by running:

```bash
test "$(git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md)" = "$(git rev-parse HEAD)" && echo "match" || echo "mismatch"
```

If `mismatch`, scenario 1 cannot run as-is — note this in the validation log and proceed to scenario 2.

- [ ] **Step 7.2: Manually walk through `/session-continuity:end-session` Step 1 logic.**

Read `commands/end-session.md` Step 1's drift check. Compare the primer's `git log --oneline -5` block to current `git log --oneline -5` output. They must match (Task 6 just refreshed the primer with current output, then committed — so the block now lags by one commit).

Wait — that's a real issue. Task 6 commits the primer refresh, which itself is now the most recent commit. So the primer's block is *one commit behind* HEAD by the time Task 6 finishes.

This is the documented behavior: refresh-then-commit means `git log` will show the refresh-commit one above the block in the next session. That's why the rule is "refresh in the same commit as the substantive change." Task 6 violates that rule. Note this in the validation log as a known artifact of the plan structure (each task is its own commit for reviewability).

- [ ] **Step 7.3: Initialize the validation log.**

Create `meta/superpowers/validation/2026-05-21-end-session-heuristics.md` with this content:

```markdown
# Validation log — end-session heuristic pass (v0.6.0)

**Branch:** `feat/end-session-heuristics`
**Spec:** `meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md`
**Plan:** `meta/superpowers/plans/2026-05-21-end-session-heuristic-pass.md`

This log records the manual validation matrix runs for the v0.6.0
end-session heuristic pass. Each scenario is documented with: setup,
expected behavior, actual behavior, pass/fail.

---

## Scenario 1 — clean repo, no commits since last primer refresh

**Setup.** Branch `feat/end-session-heuristics` after Task 6 commits.
Note: Task 6's commit *is* the most recent commit, and the primer
block was regenerated *before* Task 6's commit, so the block is one
commit behind HEAD. This is a known artifact of the plan structure;
in practice the refresh would be bundled with the substantive commit.

**Expected.** Step 1 drift check fires (block does not match HEAD).
The §1 overlay finds no matches because there are no *new* commits
since the primer's referenced log block — the divergence is the
primer's own refresh commit, which would not match any outstanding
item by stem-intersection ≥3 (stopwords include `primer`).

**Actual.** _(filled in at validation time by walking through the skill prose against actual repo state)_

**Result.** _(pass / fail / note)_
```

- [ ] **Step 7.4: Commit the initial validation log.**

```bash
git add meta/superpowers/validation/2026-05-21-end-session-heuristics.md
git commit -m "docs(validation): scaffold validation log for v0.6.0

Initial validation log captures Scenario 1 (clean repo) setup +
expected behavior. Subsequent tasks add scenarios 2-5 + dogfood
results.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md"
```

---

## Task 8: Run scenarios 2–5 of the validation matrix

**Files:**
- Modify: `meta/superpowers/validation/2026-05-21-end-session-heuristics.md`

- [ ] **Step 8.1: Walk through scenario 2 — commits without matches.**

Mental simulation: after Tasks 1–6's commits, the repo has 6 new commits since the primer was last in canonical form. Stem-intersection between commit subjects and the outstanding items will be tested below.

For each commit subject, tokenize and intersect against each outstanding item. Walk through this manually:

- Task 1 commit: `feat(end-session): outstanding-items overlay in Step 1` → tokens `end-session, outstanding-items, overlay, step` (after stopword removal: `end, session, outstanding, items, overlay, step` — actually `end-session` doesn't split on `-` if we use the spec's "split on non-alphanumeric" rule, so split → `end, session, outstanding, items, overlay, step`).
- Outstanding item #1 (post-Task 6): "Land v0.6.0 on `main` and tag. Merge `feat/end-session-heuristics`..." → tokens `land, main, merge, feat, end, session, heuristics, tag, then, git, fire, workflow, release` (after stopwords: `land, main, merge, end, session, heuristics, then, git, fire, workflow`).
- Intersection: `{end, session}` = cardinality 2. **Below threshold.** Correctly does NOT flag.

- Task 5 commit: `chore: bump to v0.6.0 + CHANGELOG entry` → tokens `chore, bump, changelog, entry` (after stopwords: `bump, changelog, entry`).
- Item #1: above. Intersection: `{}` = cardinality 0. **Below threshold.**

This matches the expectation: scenario 2's "no matches" outcome.

- [ ] **Step 8.2: Walk through scenario 3 — commit with match.**

To test the §1 overlay actually fires on a real match, construct a hypothetical commit subject that *should* match item #1.

Subject: `release: tag v0.6.0 and push to main`
Tokens after stopwords: `release, tag, push, main`. Wait — `release` and `tag` are in the stopword list. After stopword removal: `push, main`. Cardinality 2. Misses.

Try: `feat(release): merge feat/end-session-heuristics into main`
Tokens: `feat, release, merge, feat, end-session, heuristics, into, main` → split on non-alphanumeric: `feat, release, merge, end, session, heuristics, main` → after stopwords (which include `feat, release, into`): `merge, end, session, heuristics, main`. Item #1 tokens: `land, main, merge, end, session, heuristics, then, git, fire, workflow`. Intersection: `{merge, end, session, heuristics, main}` = cardinality 5. **Above threshold — fires.**

Document this in the validation log as scenario 3's expected output: the synthetic subject `feat(release): merge feat/end-session-heuristics into main` should appear under "May close outstanding items → item #1."

- [ ] **Step 8.3: Walk through scenarios 4 and 5 — heuristic firing.**

These require an actual session to test against. Mental simulation only:

- Scenario 4 (retry burst): if a session ran `bun run smoke-test` 4 times, the normalized command `bun run smoke-test` appears ≥3 times → Heuristic A fires with title `bun run smoke-test — investigated for 4 retries.` Evidence cites the four invocations.
- Scenario 5 (revert): if a session ran `git reset --hard HEAD~1`, Heuristic B fires with title `Reverted approach: <subject of reverted commit>.` Evidence cites the reset invocation and looks up the reverted commit's subject.

These pass mental review. Real-session validation happens in Task 9 (dogfood).

- [ ] **Step 8.4: Append scenarios 2–5 to the validation log.**

Use the Edit tool on `meta/superpowers/validation/2026-05-21-end-session-heuristics.md`. Append after scenario 1:

```markdown

---

## Scenario 2 — commits without matches

**Setup.** Branch state after Tasks 1–5 + 6 commits, with primer
outstanding items as updated in Task 6.

**Expected.** Step 1 surfaces the raw subject list of all commits
since the primer's referenced log block. The §1 overlay computes
stem-intersection for each subject against each outstanding item;
all intersections are <3 because the commit subjects share at most
2 stems with any item ("end, session" with item #1; nothing with
items #2, #3). No "may close outstanding items" block appears.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 3 — commit with stem-intersection match

**Setup.** Hypothetical synthetic commit subject:
`feat(release): merge feat/end-session-heuristics into main`.
Tokenized + stopword-filtered, this yields
`{merge, end, session, heuristics, main}`. Outstanding item #1's
text yields `{land, main, merge, end, session, heuristics, then, git, fire, workflow}`. Intersection cardinality = 5 ≥ 3.

**Expected.** Step 1 surfaces the subject in the raw list AND
appends a "May close outstanding items" block citing
`<sha> → item #1 ("Land v0.6.0 on main and tag")`.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 4 — retry burst (Heuristic A)

**Setup.** Hypothetical session with 4 invocations of
`bun run smoke-test` over a 30-minute window.

**Expected.** Heuristic A normalizes the command (no transformation
needed — it's already canonical), counts 4 occurrences ≥ 3, fires
with title `bun run smoke-test — investigated for 4 retries.`
Evidence bullets cite the four timestamps + exit codes.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_

---

## Scenario 5 — revert / reset (Heuristic B)

**Setup.** Hypothetical session with one `git reset --hard HEAD~1`
invocation following a commit subject `feat: try X for Y`.

**Expected.** Heuristic B fires with title
`Reverted approach: feat: try X for Y.` (the abandoned commit's
subject). Evidence cites the reset invocation and the reverted
commit's SHA.

**Actual.** _(filled in at validation time)_

**Result.** _(pass / fail / note)_
```

- [ ] **Step 8.5: Commit Task 8.**

```bash
git add meta/superpowers/validation/2026-05-21-end-session-heuristics.md
git commit -m "docs(validation): scenarios 2-5 walkthrough

Mental simulation of the four remaining matrix scenarios:
- Scenario 2: commits without matches (current branch state)
- Scenario 3: commit with synthetic stem-intersection match
- Scenario 4: retry-burst heuristic (Heuristic A)
- Scenario 5: revert/reset heuristic (Heuristic B)

Each scenario documents setup, expected behavior, and a placeholder
for actual run-time results captured during dogfood validation.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md"
```

---

## Task 9: Dogfood test — run `/session-continuity:end-session` on this very session

**Files:**
- Modify: `meta/superpowers/validation/2026-05-21-end-session-heuristics.md`

- [ ] **Step 9.1: Identify the transcript file for this session.**

Run:

```bash
ls -lat ~/.claude/projects/-Users-tal-golan--claude-skills-session-continuity/*.jsonl | head -3
```

Expected: at least one `.jsonl` file. The most recent is the live session.

If the directory does not exist, this dogfood test runs in context-window fallback mode — note that in the log.

- [ ] **Step 9.2: Mentally walk through Step 1 against the dogfood session.**

Run:

```bash
git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md
git log --oneline <sha-from-above>..HEAD
```

Expected: the SHA from `git log -1 ... -- ...` is Task 6's commit. The `<sha>..HEAD` range yields Tasks 7 + 8's commits.

For each subject, compute stem-intersection against current outstanding items (which were updated in Task 6 but not since). Document the intersections in the log.

The smoking-gun success case from the spec is the v0.6.0 feature commit subject matching item #1. After the plan's commits, item #1 reads "Land v0.6.0 on main and tag. Merge feat/end-session-heuristics..." — Task 1's commit subject "feat(end-session): outstanding-items overlay in Step 1" tokenizes to `{end, session, outstanding, items, overlay, step}`; intersection with item #1 is `{end, session}` = 2. **Below threshold.**

This is actually the documented limit of the heuristic — Task 1's subject describes the *change*, not the *outstanding work*. The match is expected to fire on a future merge or release commit, not on the development commits.

Document this finding in the log.

- [ ] **Step 9.3: Mentally walk through Step 2 against the dogfood session.**

Apply each heuristic to the session transcript (or context):

- **Heuristic A (retry burst):** Were any Bash commands repeated ≥3 times? Likely candidates: `git log --oneline -5`, `git status`. These are pure-read commands and excluded by the spec. So Heuristic A likely fires zero candidates from this session.
- **Heuristic B (revert):** Did this session run `git reset --hard`, `git revert`, etc? No. Zero candidates.
- **Heuristic C (error recurrence):** Did the same normalized error appear ≥3 times? Some `Read` tool calls may have errored on missing files. Count these in the transcript. If ≥3, Heuristic C fires.
- **Heuristic D (fix burst):** Did this session land a `fix(...): ` commit preceded by ≥10 Bash calls? The session's commits are all `feat`/`docs`/`chore` — no `fix:`. Heuristic D fires zero candidates.

Expected total: 0–1 candidates. Most likely outcome: zero candidates, prints
`No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.`

Document the actual count in the log.

- [ ] **Step 9.4: Append the dogfood results to the validation log.**

Use the Edit tool. Append after scenario 5:

```markdown

---

## Dogfood test — this session

**Setup.** Branch `feat/end-session-heuristics` after Tasks 1–8.
The session in question is the one developing and implementing the
v0.6.0 feature.

### Step 1 outcome

- Last primer commit: _(SHA from Task 6)_
- Commits in the `<last-primer>..HEAD` range: _(list)_
- Stem-intersection results for each subject:
  - _(per-subject details)_
- §1 overlay fires: _(yes/no)_

**Expected matches.** None — the development commits describe the
*change*, not the outstanding work. A real release-merge commit
("merge feat/end-session-heuristics into main") would fire item #1.

**Actual.** _(filled in at validation time)_

### Step 2 outcome

- Transcript file resolved: _(path or "fallback")_
- Heuristic A (retry burst) — candidates: _(count)_
- Heuristic B (revert) — candidates: _(count)_
- Heuristic C (error recurrence) — candidates: _(count)_
- Heuristic D (fix burst) — candidates: _(count)_
- Union after dedup: _(count)_

**Expected.** 0–1 candidates total. Most likely: zero, with the
no-op message printed.

**Actual.** _(filled in at validation time)_

### Acceptance gate

Per the spec's acceptance criteria:
- ✓ All five matrix scenarios produce expected output. _(after manual run)_
- ✓ §1 stem-match has zero false-positives across this branch's commits. _(verified in scenarios 2 + dogfood)_
- ✓/✗ §5 surfaces ≥1 candidate in dogfood test, OR zero is acceptable if the session genuinely had no friction. _(circumstance-dependent)_
- ✓ No regression in Step 3 checklist output — verified by inspecting `commands/end-session.md` Step 3 (unchanged in this plan).

**Verdict.** _(filled in at validation time)_
```

- [ ] **Step 9.5: Commit Task 9.**

```bash
git add meta/superpowers/validation/2026-05-21-end-session-heuristics.md
git commit -m "docs(validation): dogfood test scaffolding

Walks through the v0.6.0 heuristics applied to this very session.
Step 1 expects zero §1 matches (development commits describe the
change, not the outstanding work — a release-merge would match).
Step 2 expects 0-1 LEARNINGS candidates (this session ran mostly
read-only Bash; no reverts, no fix-commits).

Documents acceptance-gate verification against the spec criteria.

Spec: meta/superpowers/specs/2026-05-21-end-session-heuristic-pass-design.md"
```

---

## Task 10: Final verification + push

**Files:**
- Read-only verification of all modified files.

- [ ] **Step 10.1: Verify no `{{PLACEHOLDER}}` tokens leaked.**

Run:

```bash
grep -rn '{{' commands/ .session-continuity/ meta/superpowers/ meta/superpowers/validation/ CHANGELOG.md
```

Expected: only legitimate references to `{{...}}` syntax in `commands/primer.md` (which documents placeholder substitution as part of init mode prose). No actual unsubstituted placeholders.

- [ ] **Step 10.2: Verify the commit chain.**

Run:

```bash
git log --oneline main..HEAD
```

Expected: 9 commits on `feat/end-session-heuristics`:

1. Spec doc (already committed before Task 1).
2. Task 1: outstanding-items overlay.
3. Task 2: transcript-resolution preamble.
4. Task 3: four heuristics.
5. Task 4: presentation format.
6. Task 5: version bump + CHANGELOG.
7. Task 6: primer refresh.
8. Task 7: validation log scaffold.
9. Task 8: scenarios 2–5.
10. Task 9: dogfood.

(That's 10 commits total counting the spec — adjust if Task 1 was bundled with the spec.)

- [ ] **Step 10.3: Verify the skill body parses cleanly.**

Run:

```bash
grep -nE "^### Heuristic [ABCD] —" commands/end-session.md
grep -nE "^## Step [0-9]+" commands/end-session.md
grep -nE "outstanding-items overlay|transcript file" commands/end-session.md | head -10
```

Expected: 4 heuristic headers, the existing step headers, and ≥3 references to the new prose markers.

- [ ] **Step 10.4: Run the smoke test on the SessionStart hook.**

The v0.5.1 hook prints a 4-line status block; v0.6.0 doesn't change the hook, but verify it still works after the plan's churn:

```bash
echo '{"cwd":"'$(pwd)'"}' | bash hooks/session-start.sh
```

Expected: `<system-reminder>` block with the 4-line status. Outstanding-items count should reflect the post-Task 6 list (3 top-level items). LEARNINGS count: 4 (unchanged).

- [ ] **Step 10.5: Push the branch.**

```bash
git push -u origin feat/end-session-heuristics
```

- [ ] **Step 10.6: Open a PR draft (optional — delegate to user).**

Tell the user: "v0.6.0 ready on `feat/end-session-heuristics`. 10 commits, branch pushed. Open a PR + merge + tag when you're ready, or run the manual validation matrix first."

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task:

- Spec architecture → Tasks 1–4 (skill body modifications).
- Spec heuristic specs §1 → Task 1 (overlay prose with stopword list and threshold).
- Spec heuristic specs §5 (input source) → Task 2.
- Spec heuristic specs §5 (four heuristics) → Task 3.
- Spec presentation (Step 1 + Step 2 output formats) → Tasks 1 (Step 1 part) + 4 (Step 2 part).
- Spec transcript resolution → Task 2.
- Spec edge cases → Task 2 (compaction caveat, no-op session, no Outstanding items section, privacy, cross-platform — all in skill body prose) + Task 1 (skip condition for missing Outstanding items heading).
- Spec testing + validation → Tasks 7, 8, 9.
- Spec compatibility (version bump) → Task 5.

**Placeholder scan.** Searched for `TBD`, `TODO`, `implement later`, `add appropriate`, `similar to Task`. None present. The validation log uses `_(filled in at validation time)_` italicized markers, which are legitimate runtime-fill-in fields, not plan placeholders.

**Type consistency.** No types or method signatures (markdown-only edits). The `[heuristic-id]` tag values (`retry-burst`, `revert`, `error-recurrence`, `fix-burst`) appear consistently in Tasks 3 + 4 + 8 + 9.

**Stopword consistency.** The stopword list in Task 1 (`the and for fix add update from with into feat chore docs primer learnings session continuity tag version release`) is the same list referenced in Task 8's intersection walk-through (`feat`, `release`, `into`, `tag` all appear in the list and are correctly removed in the walkthrough). No drift.

**Known plan artifact.** Task 6's primer refresh creates a one-commit lag (the refresh is itself a commit). This is documented in Task 7's log notes. In a real workflow, the refresh would bundle with a substantive commit, but a per-task-commits plan structure can't avoid this.
