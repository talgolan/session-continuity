# Project Context — session-continuity

Stable reference material for this project — layout, conventions, where to
look for what. Changes rarely; when it does, the change is usually the
point of a commit, not a side effect of one. For what changed recently and
what's outstanding, see `.session-continuity/SESSION_PRIMER.md` instead.

## Ground rules (how to work here)

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.

## Repo layout

Claude Code plugin. Key paths:

- `.claude-plugin/plugin.json` — plugin manifest (name, version, homepage, repository)
- `.claude-plugin/marketplace.json` — single-plugin marketplace catalog (what `/plugin marketplace add` reads)
- `skills/session-continuity/SKILL.md` — main skill description shown in marketplace
- `skills/session-continuity/templates/` — `SESSION_PRIMER.md`, `PROJECT_CONTEXT.md`, and `LEARNINGS.md` starter templates
- `commands/` — slash command skill files (`primer.md`, `learning.md`, `end-session.md`)
- `hooks/` — `SessionStart` and `PreToolUse` hook scripts
- `.session-continuity/` — this file, the primer, and LEARNINGS (the canonical location as of v0.5.0; was `docs/` in v0.4 and earlier)

No build step. Everything is Markdown and shell scripts. Install via (from inside Claude Code):
```
/plugin marketplace add talgolan/session-continuity
/plugin install session-continuity@session-continuity
/reload-plugins
```

## Working directory

```
/Users/tal.golan/active_development/TG/session-continuity-plugin
```

The repo also lives at `/Users/tal.golan/.claude/skills/session-continuity` as a symlink → `~/active_development/TG/session-continuity-plugin`. The symlink keeps the dev plugin auto-loaded by Claude Code while source-of-truth lives in the active_development tree. Edit either path; they resolve to the same files.

## The packages / modules

| Component | Purpose | Notes |
|---|---|---|
| `skills/session-continuity/SKILL.md` | Main skill (session-continuity) | Invoked at session start |
| `commands/primer.md` | `/session-continuity:primer` | Init / split / refresh / check state machine |
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

## Workflow conventions

- **Bun is the runtime** for any JS/TS tooling added to this repo.
- Semantic versioning: bump `plugin.json` + add a `CHANGELOG.md` `[X.Y.Z]` block in the same commit as the feature.
- Commit messages: conventional commits (`feat:`, `fix:`, `docs:`, `chore:`). No trailing co-author line needed unless explicitly requested.
- **Never commit the primer alone** — stage it alongside a substantive change. Primer-only commits are allowed only as a one-shot catch-up.
- **Read `.session-continuity/LEARNINGS.md` before blaming the code.** Half the bugs you hit are already documented there.

## Where to look for what

| Question | File |
|---|---|
| "Why does X work this way?" | `.session-continuity/LEARNINGS.md`, `CHANGELOG.md` |
| "What did the last session do?" | `git log`, `.session-continuity/SESSION_PRIMER.md` |
| "How do I configure the plugin?" | `plugin.json`, `skills/session-continuity/SKILL.md` |
| "How do the slash commands work?" | `commands/primer.md`, `commands/learning.md`, `commands/end-session.md` |
| "What hooks are installed?" | `hooks/` |
| "Who is the user?" | Global `~/.claude/CLAUDE.md` for cross-project context |

## If you get stuck

In order of cost:

1. Grep `.session-continuity/LEARNINGS.md` for your symptom.
2. Query the session memory system with your symptom.
3. Check for stale state (processes, caches, lockfiles) before
   assuming a code bug.
4. Ask the user.

## Maintenance (your responsibility)

This file changes rarely — only when the project's shape changes (new
module, new convention, moved directory). For the file that changes with
every substantive commit, see `.session-continuity/SESSION_PRIMER.md` and
its own "Primer maintenance" section.

When you do edit this file, stage it alongside the change that made the
edit necessary — same non-standalone-commit discipline as the primer.
