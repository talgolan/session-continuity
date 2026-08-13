# Project Context — {{PROJECT_NAME}}

Stable reference material for this project — layout, conventions, where to
look for what. Changes rarely; when it does, the change is usually the
point of a commit, not a side effect of one. For what changed recently and
what's outstanding, see `.session-continuity/SESSION_PRIMER.md` instead.

## Ground rules (how to work here)

{{GROUND_RULES}}

<!-- Example:
1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.
-->

## Repo layout

{{REPO_LAYOUT_SUMMARY}}

<!-- Key paths, one bullet each. Note any install/setup commands. -->

## Working directory

```
{{WORKING_DIRECTORY_ABSOLUTE_PATH}}
```

{{WORKING_DIRECTORY_NOTES}}
<!-- Symlinks, worktrees, or other non-obvious path facts. Delete this line if none. -->

## The packages / modules

{{MODULES_TABLE}}

<!-- | Component | Purpose | Notes |
     |---|---|---|
     | ... | ... | ... | -->

## Test expectations — these must stay green

{{TEST_COMMAND_SUMMARY}}

<!-- e.g. "`<your test command>` — N pass / 0 fail" or "No automated test
     suite; validation is manual: ..." -->

## End-to-end check (real integration)

{{END_TO_END_CHECK}}

## Workflow conventions

{{WORKFLOW_CONVENTIONS}}

<!-- e.g. runtime choice, versioning scheme, commit message style,
     "never commit X alone" rules. -->

## Where to look for what

| Question | File |
|---|---|
{{WHERE_TO_LOOK_ROWS}}

## If you get stuck

In order of cost:

{{STUCK_ESCALATION_STEPS}}

<!-- Example:
1. Grep `.session-continuity/LEARNINGS.md` for your symptom.
2. Query the session memory system with your symptom.
3. Check for stale state (processes, caches, lockfiles) before assuming a code bug.
4. Ask the user.
-->

## Maintenance (your responsibility)

This file changes rarely — only when the project's shape changes (new
module, new convention, moved directory). For the file that changes with
every substantive commit, see `.session-continuity/SESSION_PRIMER.md` and
its own "Primer maintenance" section.

When you do edit this file, stage it alongside the change that made the
edit necessary — same non-standalone-commit discipline as the primer.
