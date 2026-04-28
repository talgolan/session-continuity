# `/session-continuity:end-session` — Design Spec

**Date:** 2026-04-28
**Target release:** v0.3.0
**Status:** approved, ready for implementation plan

## Problem

Session-continuity v0.2 ships two slash commands:

- `/session-continuity:primer` — init/refresh/check the primer
- `/session-continuity:learning` — append one LEARNINGS entry

Neither asks *"before you walk away, did today produce a learning, and is the working tree in a sane state to be left overnight?"* Users have to remember to refresh the primer, reflect on whether anything was painful enough to capture, and check git hygiene (staged/unstaged/untracked/unpushed) as separate manual steps. The `PreToolUse` hook catches the primer-not-staged case, but only reactively during a commit — not as a proactive close-out check.

## Goal

Add a third command, `/session-continuity:end-session`, that combines primer refresh, learnings reflection, and a final-state checklist into a single zero-arg ritual. Fills the gap between `/primer` (current-state maintenance) and `/learning` (post-hoc wisdom capture) with a close-out flow that forces Claude to look at every concern before the user closes the laptop.

## Non-goals

- Automatic commits. The primer-only-commit rule and the "user commits when ready" contract from `/primer` and `/learning` extend here. End-session never commits.
- Automatic pushes. It flags unpushed commits; the user pushes.
- Replacement for `/primer` or `/learning`. Both remain independently usable.
- Flags / escape hatches. No `--skip-learnings`, no `--no-push-check`. Users who want a subset run the primitive commands directly.
- Arguments. Session reflection (see Step 2) provides all context needed. No `$ARGUMENTS`.

## Command surface

**Name:** `/session-continuity:end-session`
**Invocation:** zero args.
**File:** `commands/end-session.md`
**Frontmatter description:** one sentence, marketplace-friendly. Suggested: "Refresh the primer, prompt for new LEARNINGS based on session context, and report a close-out checklist."

## Behavior

### Precondition

If either `docs/SESSION_PRIMER.md` or `docs/LEARNINGS.md` is missing, refuse with a pointer and exit:

> "No `docs/SESSION_PRIMER.md` (or `docs/LEARNINGS.md`) found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

Same contract as `/learning`. No degraded mode.

### Step 1 — Refresh the primer

Delegate to `/session-continuity:primer` refresh-mode logic as a subroutine:

1. Regenerate the `git log --oneline -5` block.
2. If the primer has a test-counts section, run the test command(s) and update counts.
3. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?"
4. Apply edits.
5. Stage the primer: `git add docs/SESSION_PRIMER.md`.

**Implementation note.** The end-session command's prose instructs Claude to execute the refresh-mode steps from `commands/primer.md`'s Step 3, not to literally `/session-continuity:primer` as a nested slash-command invocation (which may or may not be supported by Claude Code). Keep the refresh logic documented in one place — `commands/primer.md` — and reference it by section name from `end-session.md`.

If the primer is already current (no drift), skip the prompt and note the checklist will mark primer refresh as ✓-no-op.

### Step 2 — Session reflection for learnings

The distinctive novel behavior. Claude reviews the current conversation's context and surfaces learning candidates.

**Heuristic (Claude's judgment):** a candidate is worth surfacing when a problem in this session (a) took multiple attempts or involved a wrong theory, (b) involved a platform / tool quirk that would surprise a future developer, or (c) produced a workaround that isn't obvious from the final code. Mundane work ("wrote the new endpoint, tests passed first try") produces zero candidates and that's fine.

**Presentation.** Numbered menu, user picks any subset:

```
A few things from this session looked like LEARNINGS candidates:

1. <one-line description of candidate 1>
2. <one-line description of candidate 2>

Capture any of these? (1, 2, both, none, or describe another)
```

Zero candidates → skip silently, note "no new learnings" in the checklist.

**For each candidate the user accepts:** follow `commands/learning.md`'s flow (Steps 2-6 — gather trap/symptom/fix/diagnostic, choose section, compute next number, insert, stage). Pre-fill the title from the candidate description; Claude may also pre-draft trap/symptom/fix based on the session context and present them for the user to confirm or revise. Do not invent details the session doesn't support; leave blanks and ask the user if unclear.

**User-described "another" candidate.** If the user offers a topic not on Claude's list, treat it the same as `/learning $ARGUMENTS` with that topic as the pre-filled title.

### Step 3 — Final checklist

Emit a structured checklist with ✓ / ⚠️ / → markers. Every item must be actually checked against the current repo state, not asserted.

**Required items:**

| Item | Check | Marker |
|---|---|---|
| Primer refreshed and staged | Primer was updated in Step 1 OR was already current | ✓ |
| New LEARNINGS entries captured | Count entries added in Step 2 | ✓ with count, or ✓ "none needed" |
| Staged files | `git diff --cached --name-only` | ✓ with list, or ✓ "none" |
| Unstaged modifications | `git diff --name-only` | ⚠️ with list if any, else ✓ |
| Untracked files (ignoring `.gitignore`d) | `git ls-files --others --exclude-standard` | ⚠️ with list if any, else ✓ |
| Unpushed commits on current branch | `git rev-list --count @{u}..HEAD` (guard for detached HEAD / no upstream) | ⚠️ with count if any, ✓ "up to date" if 0, ⚠️ "no upstream" if branch not tracking |
| Suggested commit message | Derived from staged files + Step 2 captures | → (suggestion only, not a verdict) |

**Edge cases to handle explicitly:**

- **Detached HEAD:** note in the unpushed-commits row ("⚠️ detached HEAD at `<sha>`").
- **No upstream configured:** note "⚠️ branch `<name>` has no upstream — set one with `git push -u origin <name>`".
- **Non-git directory:** the precondition check catches this via missing primer, but belt-and-suspenders: if `git rev-parse` fails, skip git-dependent rows with a single "⚠️ not inside a git repo".

**Suggested commit message:** derive from the pattern of staged files. If `docs/SESSION_PRIMER.md` + code files are staged, suggest `"<scope>: <change summary>"` where `<change summary>` is drawn from session context and/or the captured learning titles. If only `docs/` is staged, suggest `docs: update session continuity`. Never a hard rule — it's a suggestion, user can ignore.

**Example output:**

```
✓ Primer refreshed and staged
✓ 1 LEARNINGS entry captured (#7, "awk range collapse on single-version CHANGELOG")
✓ Staged: docs/SESSION_PRIMER.md, docs/LEARNINGS.md, .github/workflows/release.yml
✓ No unstaged modifications
⚠️ 2 untracked files: scratch.md, tmp/debug.log — ignore, add, or delete?
⚠️ Branch "main" is 3 commits ahead of origin — push before closing?
→ Suggested: git commit -m "fix(ci): extract CHANGELOG section with proper awk range"
```

### Non-behaviors (explicit)

- Does not run tests independently. The primer refresh may run a test command if the primer's test-counts section exists; end-session adds nothing beyond that.
- Does not auto-resolve `⚠️` items. It reports them so the user can act.
- Does not check for stashes. (Added as a "maybe later" — see Open questions.)

## Architecture

### Single-file command, subroutine-by-reference

`commands/end-session.md` is a prose command file. Like the existing two commands, it's a set of instructions for Claude to follow, not executable code. The "subroutine" pattern is documentary: end-session.md says *"follow Step 3 of commands/primer.md"* rather than re-specifying the refresh steps.

**Why this shape:**

- Consistent with `/primer` and `/learning` — three prose commands, same pattern.
- Avoids drift: one definition of "refresh the primer" lives in `primer.md`.
- Claude can read referenced command files at runtime if needed.
- No new file types, no shared-steps abstraction, no new conventions.

**Tradeoff accepted:** if `primer.md`'s refresh logic is refactored in a way that breaks the reference, `end-session.md` silently inherits the breakage. Mitigation: `end-session.md` explicitly names the step ("Step 3 of `commands/primer.md`") so a refactor that renumbers steps surfaces in review.

### No new hooks, no new templates

- Hooks stay untouched. End-session is invoked explicitly by the user; no need for a new SessionEnd-style hook.
- Templates (`SESSION_PRIMER.md`, `LEARNINGS.md`) unchanged.
- `plugin.json` version bumps to `0.3.0`.
- `CHANGELOG.md` gains a `[0.3.0]` section.

## Versioning & release

- Bump `plugin.json` version to `0.3.0`.
- Add `[0.3.0]` to `CHANGELOG.md` describing the new command.
- Update `README.md` "What you get" and "Usage" sections to mention end-session.
- Tag `v0.3.0`, push. The existing release workflow publishes automatically.

## Testing strategy

Three layers, ordered cheap → expensive.

### Layer 1 — Prose consistency check

Read `commands/end-session.md` top-to-bottom and verify:

- All referenced sections of other files exist by the names given.
- The numbered-menu format is internally consistent.
- The checklist table in the prose matches the example output.

This is a review step, not an automated test.

### Layer 2 — Live smoke test in a scratch repo

Same pattern used for `/primer` and `/learning` during v0.2:

1. `/tmp/sc-end-session-smoke` — fresh git repo, `/session-continuity:primer` run, `/session-continuity:learning` seeded with one entry.
2. Make a code change, stage it, leave primer unchanged.
3. Invoke `/session-continuity:end-session`.
4. Verify:
   - Primer refresh is offered (since the new commit drifted the log block).
   - Learnings reflection surfaces zero or more candidates based on session context.
   - Checklist reports correctly: staged code ✓, primer refresh ✓, unstaged none, untracked none, unpushed count correct.
5. Vary the scenario: add an untracked file, create an unpushed commit, repeat. Checklist markers flip to ⚠️.

### Layer 3 — Dogfood in the session-continuity repo itself

Once shipped, run `/session-continuity:end-session` on this repo at the end of the v0.3 release session. Matches the Task 15 dogfooding pattern from v0.2.

## Acceptance criteria

The v0.3 release is "done" when:

1. `commands/end-session.md` exists and loads as a slash command in `claude --plugin-dir` sessions.
2. All three precondition / step / checklist behaviors from this spec are exercised in a live smoke test.
3. `plugin.json` is `0.3.0`, `CHANGELOG.md` has a `[0.3.0]` section, `README.md` mentions the new command.
4. Tag `v0.3.0` is pushed, the release workflow publishes a release with the CHANGELOG body.
5. The dogfood run on this repo completes without exposing new bugs.

## Open questions (not blocking)

- **Stashes.** Should the checklist check `git stash list` and flag non-empty stashes as ⚠️? Lean no — stashes are intentional. Reconsider if real users ask.
- **Worktree-level state.** If the user has multiple worktrees, should end-session check the other worktrees' staged/unstaged state? Lean no — single-worktree behavior covers 95%; cross-worktree checking adds complexity for a narrow case.
- **Commit message length.** The suggested commit message: strict ≤ 72 chars, or free-form? Lean strict (follows git convention) but not a hard rule; Claude picks.

These can be revisited post-ship based on feedback.

## Out-of-scope (decided during brainstorm)

- `/resume-session` command. Rejected as redundant with `/primer` check-mode + `SessionStart` hook.
- Freeform `$ARGUMENTS`. Session reflection already provides the needed context.
- Structured flags (`--skip-learnings` etc.). Premature; can be added if needed.
- Git-signal heuristics for learnings (scanning commit messages for "fix:" / "revert" markers). Too noisy; session reflection is the better signal.
