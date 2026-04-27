# Session Primer — {{PROJECT_NAME}}

You are picking up work on {{PROJECT_NAME}} from a previous session.
This file is the shortest path to productive context. Read it in order.

## First things first (read these before touching anything)

1. **`CLAUDE.md`** at the repo root — project conventions, runtime
   choices, never-commit-secrets rules.
2. **`docs/LEARNINGS.md`** — graveyard of subtle bugs, grouped by
   layer. If you hit something weird, grep this file first.
3. **Session memory system** (MemPalace, or whatever the user has in
   place) — prior sessions may have left searchable context. Query
   before guessing.

## Repo layout

{{PROJECT_LAYOUT_SUMMARY}}

Describe here anything unusual about the repo structure: monorepo vs
polyrepo, gitlink/submodule tricks, worktree conventions, non-standard
merge flows. A fresh session should not discover these by hitting
surprises.

## Working directory

```
{{WORKING_DIRECTORY_ABSOLUTE_PATH}}
```

Call out any "don't edit here, edit there" conventions.

## The packages / modules

| Package | Purpose | Notes (URL, port, etc.) |
|---|---|---|
| `{{PACKAGE_1}}` | {{PURPOSE_1}} | {{NOTES_1}} |
| `{{PACKAGE_2}}` | {{PURPOSE_2}} | {{NOTES_2}} |

## Test expectations — these must stay green

```
{{TEST_COMMAND_1}}   # {{EXPECTED_COUNT_1}}
{{TEST_COMMAND_2}}   # {{EXPECTED_COUNT_2}}
```

If any of those regress, something is broken. Fix before adding
new work.

Keep the counts honest — update on every commit that touches test
code. See "Primer maintenance" at the end of this file.

## End-to-end check (real integration)

```bash
{{SMOKE_TEST_COMMAND}}
{{STATUS_COMMAND}}
```

Call out any preconditions: credentials, external services, costs.
If the smoke test spends money or touches production, say so loudly.

## Current state

- {{HIGH_LEVEL_PROJECT_STATUS}}
- {{SECOND_HIGH_LEVEL_STATUS}}

**Current `git log --oneline -5` (primary branch):**

```
{{LATEST_COMMIT_HASH_1}} {{LATEST_COMMIT_SUBJECT_1}}
{{LATEST_COMMIT_HASH_2}} {{LATEST_COMMIT_SUBJECT_2}}
{{LATEST_COMMIT_HASH_3}} {{LATEST_COMMIT_SUBJECT_3}}
{{LATEST_COMMIT_HASH_4}} {{LATEST_COMMIT_SUBJECT_4}}
{{LATEST_COMMIT_HASH_5}} {{LATEST_COMMIT_SUBJECT_5}}
```

Regenerate this block whenever you commit — see "Primer maintenance"
below.

## Outstanding items (explicitly deferred — not bugs, decisions)

1. **{{ITEM_1_TITLE}}.** {{ITEM_1_BODY}}

2. **{{ITEM_2_TITLE}}.** {{ITEM_2_BODY}}

Keep the list short and concrete. When you finish one, remove it.
When code review or the user flags a new follow-up, add it.

## Workflow conventions

- {{CONVENTION_1}}
- {{CONVENTION_2}}
- **Read `docs/LEARNINGS.md` before blaming the code.** Half the bugs
  you hit are already documented there.
- **Commit messages end with:**
  ```
  {{COMMIT_SIGNATURE}}
  ```

## Where to look for what

| Question | File |
|---|---|
| "Why does X work this way?" | `docs/LEARNINGS.md`, design docs |
| "What did the last session do?" | `git log`, session memory system |
| "How do I configure Y?" | `.env.example`, `config.{{EXT}}` |
| "How do I test Z?" | "Test expectations" section above |
| "What processes are running?" | {{STATUS_COMMAND}} |
| "Who is the user?" | Global `~/.claude/CLAUDE.md` for cross-project context |

## If you get stuck

In order of cost:

1. Grep `docs/LEARNINGS.md` for your symptom.
2. Query the session memory system with your symptom.
3. Check for stale state (processes, caches, lockfiles) before
   assuming a code bug.
4. Ask the user.

## Primer maintenance (your responsibility)

Refresh this file **alongside substantive commits**, not as a standalone
follow-up. Two sections are the usual targets:

- **Current state** — regenerate the `git log --oneline -5` block so
  a future session sees the real latest commits.
- **Outstanding items** — if you finished one, remove it. If a code
  review flagged a new follow-up, add it.

**When to update** — stage primer edits in the same commit as the
real change that made them necessary. If a feature commit lands five
lines of code, the `git log` block in the primer should be refreshed
as part of that same commit.

**When NOT to update** — do NOT commit the primer by itself just to
record the previous primer refresh. That creates a self-referential
chain: every primer-only commit would invite another one. A
primer-only commit is fine when you are genuinely out-of-sync and not
about to touch code (rare); but treat it as a one-shot catch-up, not
a habit.

Other sections (layout, packages, test expectations, conventions)
change less often but are fair game when they drift. Test counts in
particular: if you add or remove a test, bump the count so it matches
your test runner output.

When a bug takes more than 15 minutes to diagnose, update
`docs/LEARNINGS.md` too (see that file's footer for numbering rules).
The primer and LEARNINGS are complementary: primer is current-state,
LEARNINGS is accumulated-wisdom.
