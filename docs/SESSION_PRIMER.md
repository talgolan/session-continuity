# Session Primer — session-continuity

You are picking up work on session-continuity from a previous session.
This file is the shortest path to productive context. Read it in order.

## Ground rules (how to work here)

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.

## First things first (read these before touching anything)

1. **`CLAUDE.md`** at the repo root — project conventions, runtime
   choices, never-commit-secrets rules.
2. **`docs/LEARNINGS.md`** — graveyard of subtle bugs, grouped by
   layer. If you hit something weird, grep this file first.
3. **Session memory system** (MemPalace, or whatever the user has in
   place) — prior sessions may have left searchable context. Query
   before guessing.

## Repo layout

Claude Code plugin. Key paths:

- `.claude-plugin/plugin.json` — plugin manifest (name, version, homepage, repository)
- `.claude-plugin/marketplace.json` — single-plugin marketplace catalog (what `/plugin marketplace add` reads)
- `skills/session-continuity/SKILL.md` — main skill description shown in marketplace
- `skills/session-continuity/templates/` — `SESSION_PRIMER.md` and `LEARNINGS.md` starter templates
- `commands/` — slash command skill files (`primer.md`, `learning.md`, `end-session.md`)
- `hooks/` — `SessionStart` and `PreToolUse` hook scripts
- `docs/` — this primer and LEARNINGS

No build step. Everything is Markdown and shell scripts. Install via (from inside Claude Code):
```
/plugin marketplace add talgolan/session-continuity
/plugin install session-continuity@session-continuity
/reload-plugins
```

## Working directory

```
/Users/tal.golan/.claude/skills/session-continuity
```

## The packages / modules

| Component | Purpose | Notes |
|---|---|---|
| `skills/session-continuity/SKILL.md` | Main skill (session-continuity) | Invoked at session start |
| `commands/primer.md` | `/session-continuity:primer` | Init / refresh / check state machine |
| `commands/learning.md` | `/session-continuity:learning` | Append a LEARNINGS entry interactively |
| `commands/end-session.md` | `/session-continuity:end-session` | Close-out ritual: refresh + LEARNINGS candidates + git checklist |
| `hooks/` | SessionStart + PreToolUse | Remind Claude to read primer; nudge on git commit without primer staged |

## Test expectations — these must stay green

No automated test suite. Validation is manual: install the plugin in a test project and exercise each slash command.

## End-to-end check (real integration)

```bash
# Install in a scratch project and run all three commands:
/session-continuity:primer    # init → fill → stage
/session-continuity:learning  # append entry → stage
/session-continuity:end-session  # refresh + checklist
```

No external credentials or costs.

## Current state

- v0.4.1 staged — prose fixes for placeholder leakage and premature outstanding-items edits, both caught by the v0.4.0 clean-machine acceptance test. See the 0.4.1 and 0.4.0 CHANGELOG entries for the full diff story.
- Three slash commands are stable (`primer`, `learning`, `end-session`).
- `hooks/hooks.json` uses `if: "Bash(git commit *)"` to scope the `PreToolUse` hook; it does not fire on every Bash call.
- `.claude-plugin/marketplace.json` present so the repo is installable via `/plugin marketplace add talgolan/session-continuity`.
- `docs/` holds only `SESSION_PRIMER.md` and `LEARNINGS.md`. Dev artifacts (marketplace-submission notes, specs, plans) live under `meta/`.
- No known open bugs; outstanding items are feature-level.

**Current `git log --oneline -5` (primary branch):**

```
90d9d18 docs(primer): refresh for v0.4.0 — update git log block and outstanding items
59dcb89 feat: v0.4.0 — marketplace-submission hardening pass
c1571bd docs: streamline marketplace-submission.md by removing redundant content
f840d68 docs: update CONTRIBUTING.md for clarity in contribution guidance
c66e354 docs: add CONTRIBUTING.md with scope policy and authoring conventions
```

Regenerate this block whenever you commit — see "Primer maintenance" below.

## Outstanding items (explicitly deferred — not bugs, decisions)

1. **Tag v0.4.1 and push.** v0.4.1 ships the two prose fixes from the clean-machine acceptance test (placeholder-leakage + premature-apply in end-session). `git tag v0.4.1 && git push origin v0.4.1` to fire the release workflow.

2. **Submit to the Anthropic marketplace.** v0.4.1 is ready. Form answers in `meta/administrative/marketplace-submission.md`. Bump the "Version at submission" field in that file to 0.4.1 before submitting.

3. **Automated integration tests.** Manual validation only right now. Consider a bats or similar shell test harness to exercise the slash commands against a fixture repo.

4. **Add captured learnings from the v0.4.0 session.** Three candidates still open (install-command-form verification via WebFetch, pipefail+grep/head/sed regression, `.claude/settings.json` auto-population hygiene, `GITHUB_REF_NAME` awk injection) — worth a `/session-continuity:learning` pass each. Placeholder-leakage already captured as LEARNINGS #4.

## Workflow conventions

- **Bun is the runtime** for any JS/TS tooling added to this repo.
- Semantic versioning: bump `plugin.json` + add a `CHANGELOG.md` `[X.Y.Z]` block in the same commit as the feature.
- Commit messages: conventional commits (`feat:`, `fix:`, `docs:`, `chore:`). No trailing co-author line needed unless explicitly requested.
- **Never commit the primer alone** — stage it alongside a substantive change. Primer-only commits are allowed only as a one-shot catch-up.
- **Read `docs/LEARNINGS.md` before blaming the code.** Half the bugs you hit are already documented there.

## Where to look for what

| Question | File |
|---|---|
| "Why does X work this way?" | `docs/LEARNINGS.md`, `CHANGELOG.md` |
| "What did the last session do?" | `git log`, this primer |
| "How do I configure the plugin?" | `plugin.json`, `skills/session-continuity/SKILL.md` |
| "How do the slash commands work?" | `commands/primer.md`, `commands/learning.md`, `commands/end-session.md` |
| "What hooks are installed?" | `hooks/` |
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
real change that made them necessary.

**When NOT to update** — do NOT commit the primer by itself just to
record the previous primer refresh.

When a bug takes more than 15 minutes to diagnose, update
`docs/LEARNINGS.md` too (see that file's footer for numbering rules).
