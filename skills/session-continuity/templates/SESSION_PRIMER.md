# Session Primer — {{PROJECT_NAME}}

You are picking up work on {{PROJECT_NAME}} from a previous session. This
file is the shortest path to what changed recently and what's outstanding.
For stable repo context (layout, conventions, modules), read
`.session-continuity/PROJECT_CONTEXT.md` once per session — it changes
rarely.

## First things first (read these before touching anything)

1. **`.session-continuity/PROJECT_CONTEXT.md`** — stable repo context:
   layout, conventions, where to look for what.
2. **`.session-continuity/LEARNINGS.md`** — graveyard of subtle bugs,
   grouped by layer. If you hit something weird, grep this file first.
3. **Session memory system** (if the user has one in place) — prior
   sessions may have left searchable context. Query before guessing.

## Current state

{{CURRENT_STATE_SUMMARY}}

**Current `git log --oneline -5` (primary branch):**

```
{{LATEST_COMMIT_HASH_1}} {{LATEST_COMMIT_SUBJECT_1}}
{{LATEST_COMMIT_HASH_2}} {{LATEST_COMMIT_SUBJECT_2}}
{{LATEST_COMMIT_HASH_3}} {{LATEST_COMMIT_SUBJECT_3}}
{{LATEST_COMMIT_HASH_4}} {{LATEST_COMMIT_SUBJECT_4}}
{{LATEST_COMMIT_HASH_5}} {{LATEST_COMMIT_SUBJECT_5}}
```

Regenerate this block whenever you commit — see
`.session-continuity/PROJECT_CONTEXT.md`'s "Maintenance" section.

## Outstanding items (explicitly deferred — not bugs, decisions)

{{OUTSTANDING_ITEMS}}

<!-- Numbered list. One decision/deferral per item, with a one-line reason. -->
