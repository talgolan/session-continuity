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
- No `.claude-plugin/marketplace.json` in this repo — the marketplace catalog moved to the separate `talgolan/claude-plugins` repo (see README's "Install" section)
- `skills/session-continuity/SKILL.md` — main skill description shown in marketplace
- `skills/session-continuity/templates/` — `SESSION_PRIMER.md`, `PROJECT_CONTEXT.md`, `ROADMAP.md`, and `LEARNINGS.md` starter templates
- `commands/` — slash command skill files (`primer.md`, `learning.md`, `end-session.md`)
- `hooks/` — `SessionStart` and `PreToolUse` hook scripts
- `.session-continuity/` — this file, the primer, ROADMAP, and LEARNINGS. The work queue is GitHub Issues labeled `backlog`.

No build step. Everything is Markdown and shell scripts. Install via (from inside Claude Code):
```
/plugin marketplace add talgolan/claude-plugins
/plugin install session-continuity@talgolan
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
| `skills/session-continuity/templates/` | Thin primer + PROJECT_CONTEXT + ROADMAP + LEARNINGS | Banlist: no embedded `git log` in primer |
| `commands/primer.md` | `/session-continuity:primer` | Init / split / slim-migrate / refresh / check via `primer-detect.sh` |
| `commands/learning.md` | `/session-continuity:learning` | Append a LEARNINGS entry interactively |
| `commands/end-session.md` | `/session-continuity:end-session` | Freshness-gated refresh + LEARNINGS candidates + git checklist |
| `commands/doctor.md` | `/session-continuity:doctor` | Shape + peers + freshness diagnostic |
| `hooks/lib/primer-freshness.sh` | `STALE=0\|1\|?` | Source of truth for substantive drift |
| `hooks/lib/primer-detect.sh` | Dispatch `STEPS=` | Maps freshness → `LOG_DRIFT`; never reimplements ignore policy |
| `hooks/lib/primer-validate.sh` / `peer-probes.sh` | Shape + engrim/graphify | SessionStart / doctor hard-incomplete on peer fail |
| `hooks/` | SessionStart + PreToolUse gates | Seven commit-time content gates + retrieval + nudge |

## Test expectations — these must stay green

Hermetic zsh smokes under `meta/superpowers/validation/` (no live MCP /
live GitHub required for the core helpers). Confirm block in the dogfood
primer lists the load-bearing ones. Notable:

```bash
zsh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-freshness-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-peer-probes-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-validate-smoke.zsh
```

Manual: install via `--plugin-dir` in a scratch repo and exercise primer /
doctor / end-session.

## End-to-end check (real integration)

```bash
# Install in a scratch project and run:
/session-continuity:primer    # init → Mid-flight/Confirm → stage
/session-continuity:doctor    # peers + shape + freshness
/session-continuity:learning  # append entry → stage
/session-continuity:end-session  # freshness-gated refresh + checklist
```

Peers: local `engrim` on PATH; commit non-empty `graphify-out/graph.json`.
No external paid APIs required.

## Workflow conventions

- **Bun is the runtime** for any JS/TS tooling added to this repo.
- Semantic versioning: bump `plugin.json` + add a `CHANGELOG.md` `[X.Y.Z]` block in the same commit as the feature.
- Commit messages: conventional commits (`feat:`, `fix:`, `docs:`, `chore:`). No trailing co-author line needed unless explicitly requested.
- **Never commit the primer alone** — stage it alongside a substantive change. Primer-only commits are allowed only as a one-shot catch-up.
- **Read `.session-continuity/LEARNINGS.md` before blaming the code.** Half the bugs you hit are already documented there.

## Where to look for what

| Question | File |
|---|---|
| "What's in flight / how do I confirm it?" | `.session-continuity/SESSION_PRIMER.md` (Mid-flight + Confirm) |
| "Did the primer drift?" | `bash hooks/lib/primer-freshness.sh .` |
| "Why does X work this way?" | `.session-continuity/LEARNINGS.md`, `CHANGELOG.md` |
| "How do I configure the plugin?" | `.claude-plugin/plugin.json`, `skills/session-continuity/SKILL.md` |
| "How do the slash commands work?" | `commands/*.md` |
| "What hooks are installed?" | `hooks/hooks.json`, `hooks/` |
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
module, new convention, moved directory). On substantive commits, refresh
Mid-flight + Confirm in `.session-continuity/SESSION_PRIMER.md` and stage
it with the commit.

When you do edit this file, stage it alongside the change that made the
edit necessary — same non-standalone-commit discipline as the primer.
