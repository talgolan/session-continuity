---
description: Refresh the primer, surface LEARNINGS candidates from this session, and report a close-out checklist. Zero args.
---

# /session-continuity:end-session

You are responding to the `/session-continuity:end-session` slash command.

**Your job: run a close-out ritual that (1) refreshes `docs/SESSION_PRIMER.md`, (2) surfaces LEARNINGS candidates from this session's conversation, and (3) reports a structured ✓ / ⚠️ checklist of the repo's state so the user can walk away knowing nothing is forgotten.**

Zero arguments. Never commits. Never pushes.

## Step 0 — Preconditions

Check both files exist:

1. `docs/SESSION_PRIMER.md`
2. `docs/LEARNINGS.md`

If either is missing, tell the user:

> "No `docs/SESSION_PRIMER.md` (or `docs/LEARNINGS.md`) found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

Exit. Do not proceed.

## Step 1 — Refresh the primer

Follow the logic in **Step 3 of `commands/primer.md`** (refresh mode):

1. Read the current `docs/SESSION_PRIMER.md`.
2. Regenerate the `git log --oneline -5` block with current output.
3. If the primer has a test-counts section, run the test command(s) found there and update the counts to match current output.
4. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?"
5. Apply the edits.
6. Stage the updated primer: `git add docs/SESSION_PRIMER.md`.

If the primer is already current (`git log` block matches, no test counts to update, user has no outstanding-items changes), skip the prompt and note in Step 3's checklist that primer refresh was a no-op (still ✓).

**Do not** commit. Staging only.

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

### Presentation

Show candidates as a numbered menu:

```
A few things from this session looked like LEARNINGS candidates:

1. <one-line description of candidate 1>
2. <one-line description of candidate 2>

Capture any of these? (1, 2, both, none, or describe another)
```

If you find **zero** candidates, skip the prompt and note "no new learnings" in Step 3's checklist.

### Capture flow for each accepted candidate

For each candidate the user picks, follow **Steps 2-6 of `commands/learning.md`**:

- Pre-fill the **Title** from the candidate description.
- Pre-draft **The trap**, **Symptom**, **Fix**, and **Diagnostic signal** from session context where you can, then present the draft to the user for confirmation / revision. Do not invent details the session does not support — leave a field blank and ask if unclear.
- Choose section per Step 3 of `commands/learning.md`.
- Compute the next number per Step 4.
- Insert at the top of the chosen section per Step 5.
- Stage: `git add docs/LEARNINGS.md` per Step 6.

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

- Only `docs/` staged → `docs: update session continuity`.
- `docs/LEARNINGS.md` is staged with code → pick the most prominent captured learning's title (or the primary code-change theme) and use conventional-commit style: `<type>(<scope>): <subject>`. Keep subject line ≤ 72 chars.
- Only code staged (no docs) → should not happen if Step 1 ran; if it does, suggest based on the file paths.

Prefix with `→ Suggested:` and wrap in a fenced code block so the user can copy-paste.

### Example output

```
✓ Primer refreshed and staged
✓ 1 LEARNINGS entry captured (#7, "awk range collapse on single-version CHANGELOG")
✓ Staged: docs/SESSION_PRIMER.md, docs/LEARNINGS.md, .github/workflows/release.yml
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
- **Respect the primer-only-commit rule.** If the user, after seeing the checklist, commits only the primer, the `PreToolUse` hook's nudge still applies — nothing to do here.
- **Zero arguments.** If the user passed text after `/session-continuity:end-session`, ignore it — session reflection provides all context needed.
