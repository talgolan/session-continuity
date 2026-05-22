# Design — `/session-continuity:end-session` heuristic pass

**Date:** 2026-05-21
**Target version:** 0.6.0
**Source:** `meta/superpowers/recommendations/improvements_20260521.md` §1 + §5

## Problem

`/session-continuity:end-session` does two things today:

1. Refresh the primer (Step 1).
2. Surface LEARNINGS candidates from the session (Step 2).

Both rely on the user (and Claude) to remember what mattered. v0.5.1
already surfaces commit subjects since the last primer refresh, but does
not connect them to outstanding items. Step 2 is prose criteria —
"problems that took multiple attempts," "platform quirks that
surprised us" — applied via Claude's general judgment over a context
window that may have been compacted.

Two concrete misses observed in the wild (per the recommendations doc):

- A commit subject obviously closing an outstanding item is not
  flagged as such — the user has to spot the connection unaided.
- A 6-hour session that included a 47-minute DNS investigation and
  a 15-minute build regression generated zero LEARNINGS candidates.
  Both deserved entries.

## Goal

Add explicit, deterministic heuristics inside the existing
`/end-session` flow that surface candidates the user might miss. Never
auto-act — surfacing only.

## Non-goals

- No auto-close of outstanding items.
- No auto-append of LEARNINGS entries (capture flow remains the
  existing one in `commands/learning.md`).
- No new files, hooks, or schemas. The patch is skill-body prose.
- No Stop-hook auto-trigger of `/end-session` — Claude Code does not
  expose a reliable session-end event today. Manual invocation only.

## Architecture

Single change locus: `commands/end-session.md`. Two existing steps
gain heuristic logic; no new files, no new hooks, no schema changes.

- **Step 1 (Refresh)** already inherits Step 5 of `commands/primer.md`
  (v0.5.1 git-log subject surfacing). §1 adds an outstanding-items
  overlay on top of the existing subject list — for each subject,
  compute stem-intersection ≥3 against each open outstanding item and
  surface matches as "may close item #N" candidates. No behavior
  change when no matches are found (raw subject list still shown).
- **Step 2 (Session reflection)** today is prose. §5 replaces the
  prose with four explicit heuristics. Skill body instructs Claude to
  (a) locate the session transcript file at
  `~/.claude/projects/<url-encoded-cwd>/<latest-mtime>.jsonl` if
  accessible, fall back to context window, (b) apply each heuristic,
  (c) present the union of matches as a numbered candidate list using
  the existing presentation format.

Both additions surface candidates only — never auto-act. Outstanding
items are not closed without user confirmation; LEARNINGS entries are
not appended without going through the existing capture flow.

## Heuristic specs

### §1 outstanding-items match (Step 1 overlay)

Input: list of commit subjects from
`git log <last-primer>..HEAD --oneline`, list of outstanding items
(top-level numbered entries in primer's "Outstanding items" section).

Algorithm per subject:

1. Tokenize subject: lowercase, split on non-alphanumeric, drop tokens
   of length <3, drop stopwords.
2. For each outstanding item: tokenize the same way (full item text
   including sub-bullets, capped at first 200 chars).
3. Intersect token sets. Match if `|intersection| ≥ 3`.
4. On match, attach: `commit <sha>: <subject> — may close item #<N>
   ("<first 60 chars of item>")`.

**Stopwords** (lives in skill body as a comment block — easy to
extend per project; cap ~20 to keep skill readable):

```
the and for fix add update from with into feat chore docs primer
learnings session continuity tag version release
```

**Presentation:** subjects with no match still printed in raw list
(existing v0.5.1 behavior). Subjects with match printed under the
existing list with the "may close" annotation. User confirms before
any item is removed.

### §5 LEARNINGS heuristics (Step 2 replacement)

**Input source order:**

1. Read most recent
   `~/.claude/projects/<url-encoded-cwd>/*.jsonl` if path resolvable +
   readable.
2. Else fall back to current context window.

**Heuristic A — retry burst.** Group consecutive Bash tool calls by
normalized command (strip trailing args after first newline; collapse
whitespace; drop pure-read commands `cat`/`ls`/`grep`/`find`/`stat`/
`pwd`/`which`/`echo`). Trigger: same normalized command appears ≥3
times. Candidate title: "<command> — investigated for N retries."

**Heuristic B — revert / reset.** Trigger: any of `git reset --hard`,
`git checkout -- `, `git revert`, `git restore`, or `rm -rf` against
a path that appears in `git ls-files`. Candidate title:
"Reverted approach: <commit subject of reverted commit if available,
else 'unrecorded'>."

**Heuristic C — error recurrence.** Parse tool results for first
non-empty line of stderr OR `Error:`-prefixed line in tool output.
Normalize (strip absolute paths, line numbers, timestamps, hex
addresses). Trigger: same normalized error string appears ≥3 times
AND first/last occurrences span ≥15 minutes (use tool-call timestamps
from JSONL; skip the wall-clock gate in fallback mode). Candidate
title: "<error string> — recurred N times over M minutes."

**Heuristic D — fix burst.** Trigger: a commit with subject matching
`^fix(\(.+\))?: ` preceded by ≥10 Bash tool calls within the prior
30 minutes. Candidate title: "<commit subject> — fix preceded by
N-action investigation."

**Output:** union of triggers, deduplicated by title. Each candidate
carries: heuristic ID (A/B/C/D), title, supporting evidence (1-3
bullet citations from transcript). Capped at 5 candidates total — if
more, present 5 highest-evidence and note "+N more not shown; re-run
after capturing these."

Presentation reuses Step 2's existing menu format. User picks which
to capture; capture flow is unchanged.

### Refusals

- §1: never closes an item without user confirmation. The skill body
  must say so explicitly.
- §5: never appends a LEARNINGS entry from heuristic alone — always
  routes through existing capture flow which itself never invents
  details (per `commands/learning.md` notes).
- Both: zero candidates is a valid outcome. Skill prints "no §1
  matches" / "no LEARNINGS candidates" and proceeds.

## Presentation

### Step 1 (Refresh) output

After v0.5.1's existing "since last primer refresh, these commits
landed" block, append matched-item sub-list when matches exist. If no
matches, this section is omitted entirely (no empty block).

```
Since the last primer refresh, these commits landed:
- aff74c3 feat!: relocate session-continuity files to .session-continuity/
- f5013e1 feat: v0.5.1 — primer drift refinements + learning numbering hardening

May close outstanding items (≥3-stem match — confirm before closing):
- f5013e1 → item #1 ("Land v0.5.1 on `main` and tag")
- f5013e1 → item #3 ("Deferred recommendations from improvements_20260521.md")

Any of these resolve outstanding items, or warrant a new LEARNINGS entry?
```

User answers free-form. Skill applies edits per Step 1.5 of v0.5.1
flow (which awaits user input).

### Step 2 (Session reflection) output

Replaces the current "1. <one-line> / 2. <one-line>" menu with
annotated heuristic blocks:

```
LEARNINGS candidates from this session:

1. [retry-burst] `bun run smoke-test` — investigated for 4 retries.
   Evidence:
   - Bash @ 14:02 → exit 1 ("connection refused")
   - Bash @ 14:08 → exit 1 ("connection refused")
   - Bash @ 14:11 → exit 1 ("connection refused")
   - Bash @ 14:19 → exit 0 (after editing hosts file)

2. [error-recurrence] "ENOTFOUND archive.ubuntu.com" — recurred 6 times over 47 minutes.
   Evidence: 6 Bash invocations across docker build steps; resolved by adding --network host.

3. [revert] Reverted approach: "feat: try X for Y" (commit 8af31a2 → git reset --hard).

Capture any? (1, 2, 3, all, none, or describe another)
```

If zero candidates: print
`No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.`
and skip to Step 3.

### Cap behavior

When >5 candidates trigger, sort by evidence count (descending) and
show top 5. Append a single line:
`+N more candidates not shown — capture these first, then re-run /session-continuity:end-session.`

### Step 3 checklist updates

Final checklist's "New learnings" row already says
`"N LEARNINGS entries captured (#X, '<title>'…)" OR "No new learnings"`.
No change needed — heuristic surfacing is a Step 2 internal, not a
Step 3 row.

## Transcript resolution

Path convention (Claude Code):
`~/.claude/projects/<url-encoded-cwd>/<session-id>.jsonl`. URL-encoding
rule: `/` → `-`, leading `/` becomes leading `-`. Example: cwd
`/Users/tal.golan/repo` → dir `-Users-tal-golan-repo`.

Resolution order:

1. Compute expected dir from `pwd` using the encoding rule.
2. If dir exists, pick the `.jsonl` with the most recent mtime
   (assumed to be the live session).
3. If dir missing OR no `.jsonl` files OR most-recent file's mtime
   older than 5 minutes (stale, probably wrong session), fall back to
   context-window mode.
4. Skill body documents this as best-effort. No error if any step
   fails.

Skill instructs Claude to inspect the file via `Read` tool (JSONL is
line-delimited JSON; large but greppable). For sessions long enough
that reading the whole file blows context, use `grep`/`wc` via Bash to
filter relevant entries (Bash tool calls, errors, commits) before
pulling them into context.

## Edge cases

- **Compaction between session start and end-session.** Context-window
  fallback misses early-session events. Skill notes this:
  "if the session has been compacted, transcript-file mode is
  recommended; context-window mode will undercount candidates." User-
  facing note — not a silent failure.
- **Session reflection on a no-op session.** User runs `/end-session`
  immediately after `/primer`. Zero Bash calls, zero commits. All four
  heuristics return empty. Print `No LEARNINGS candidates` and proceed.
- **Outstanding-items section structure varies.** Some primers nest
  sub-bullets under numbered items. Stem-match runs against the full
  item text (numbered line + indented continuation lines until next
  top-level number). Sub-bullet matches roll up to parent item.
- **No outstanding items section in primer.** Skill uses the heading
  `^## Outstanding items` as anchor. If absent (custom-modified
  primer), §1 overlay is skipped silently — only the raw subject list
  shows.
- **Stem-intersection on common scope words.** Mitigation: stopword
  list (above).
- **Privacy.** Transcripts may contain prompts/secrets. Heuristic
  candidates' "evidence" bullets paraphrase tool inputs, never quote
  raw stdout/stderr beyond the first error line. Skill body includes
  an explicit redaction note.
- **Cross-platform.** Path encoding rule above is macOS/Linux. Windows
  untested. Skill body says: "if `~/.claude/projects/` doesn't exist
  or the encoding mismatches, fall back to context-window mode" —
  same fallback path.

## Testing + validation

No automated test suite (per primer). Validation is manual +
dogfood-driven.

### Manual validation matrix

Run `/session-continuity:end-session` against five fixture scenarios:

1. **Clean repo, no commits since last primer refresh.** Expect:
   Step 1 prints "Primer already current (no-op)"; Step 2 either zero
   candidates or whatever the session genuinely contains. No
   regression vs v0.5.1.
2. **Repo with 3 commits since last primer refresh, none matching
   outstanding items.** Expect: Step 1 prints raw subject list, no
   "may close" overlay. Same as v0.5.1.
3. **Repo with a commit whose subject shares ≥3 stems with an
   outstanding item.** Expect: subject appears under both the raw
   list AND the "may close" overlay with item number citation.
4. **Long session with retry burst (≥3 identical Bash invocations).**
   Expect: Step 2 surfaces a `[retry-burst]` candidate. Capture flow
   routes through existing `commands/learning.md` Step 5/6/7.
5. **Session with `git reset --hard` after a commit.** Expect: Step 2
   surfaces a `[revert]` candidate citing the reset and the abandoned
   commit subject.

Each scenario validated against both transcript-file mode (`.jsonl`
resolvable) and context-window fallback (force fallback by `mv`-ing
the dir aside).

### Dogfood test

Run `/end-session` on the actual session that develops this feature.
The §1 match between the v0.6.0 feature commit subject and outstanding
item ("End-session heuristic pass") is the smoking-gun success case.
If the stem-intersection threshold or stopword list is wrong, this
match will fail to fire.

### Acceptance criteria

- All five scenarios produce expected output. No false positives in
  scenarios 1–2.
- §1 stem-match has zero false-positives in a hand-tested repo of ≥10
  outstanding items + ≥10 unrelated commits.
- §5 heuristics surface ≥1 candidate in dogfood test. Zero is also
  acceptable IF the dogfood session genuinely had no friction.
- No regression in Step 3 checklist output — same rows, same markers.

## Compatibility

- v0.5.x → v0.6.0. Pure prose-skill addition; no schema, no path, no
  hook changes. Existing v0.5.x installs upgrade with no migration.
  Old primers without an "Outstanding items" section silently skip
  the §1 overlay.
- Version bump: minor (0.6.0) — new user-visible behavior in
  `/end-session`, no breaking change.
