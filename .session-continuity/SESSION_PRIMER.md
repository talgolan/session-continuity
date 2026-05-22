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
2. **`.session-continuity/LEARNINGS.md`** — graveyard of subtle bugs,
   grouped by layer. If you hit something weird, grep this file first.
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
- `.session-continuity/` — this primer and LEARNINGS (the canonical location as of v0.5.0; was `docs/` in v0.4 and earlier)

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

- v0.6.0 shipped (merged to `main` as `7bc25c3`, tag `v0.6.0` pushed; PR #1 closed). Adds the §1 outstanding-items overlay and §5 four-heuristic LEARNINGS candidate surfacing to `/session-continuity:end-session`. Pure prose-skill addition; no new files, hooks, or schemas. See the v0.6.0 CHANGELOG entry for the full diff.
- New project-local `CLAUDE.md` redirects superpowers skills' default `docs/superpowers/{specs,plans}/` paths to `meta/superpowers/`, matching the v0.3 layout. Added after the brainstorming-skill default re-introduced the duplicate `docs/superpowers/` directory.
- v0.5.1 (commit `f5013e1`) shipped quick-win refinements: drop the mtime drift check, 3× test-flake retry, `git log <last-primer>..HEAD` candidate surfacing, hardened `learning` numbering, and a 4-line `SessionStart` status block.
- v0.5.0 (commit `aff74c3`) relocated the two files from `docs/` to `.session-continuity/` with auto-migration support.
- Three slash commands are stable (`primer`, `learning`, `end-session`).
- `hooks/hooks.json` uses `if: "Bash(git commit *)"` to scope the `PreToolUse` hook; it does not fire on every Bash call.
- `.claude-plugin/marketplace.json` present so the repo is installable via `/plugin marketplace add talgolan/session-continuity`.
- `.session-continuity/` holds only `SESSION_PRIMER.md` and `LEARNINGS.md` (v0.5.0 moved them from `docs/`). Dev artifacts (marketplace-submission notes, specs, plans, recommendation docs) live under `meta/`.
- No known open bugs; outstanding items are feature-level.

**Current `git log --oneline -5` (primary branch):**

```
7bc25c3 docs: project CLAUDE.md — agent artifacts under meta/superpowers/
b938250 chore: relocate spec/plan from docs/superpowers/ to meta/superpowers/
125087b docs(validation): dogfood test results
8f2f931 docs(validation): scenarios 2-5 walkthrough
6769cc9 docs(validation): scaffold validation log for v0.6.0
```

Regenerate this block whenever you commit — see "Primer maintenance" below.

## Outstanding items (explicitly deferred — not bugs, decisions)

1. **Submit to the Anthropic marketplace.** Form answers in `meta/administrative/marketplace-submission.md`. Bump the "Version at submission" field in that file to 0.6.0 before submitting.

2. **Deferred recommendations from `meta/superpowers/recommendations/improvements_20260521.md`** (rejected or not-yet-prioritized — v0.5.1 + v0.6.0 shipped the items deemed high-value):
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

3. **Automated integration tests.** Manual validation only right now. Consider a bats or similar shell test harness to exercise the slash commands against a fixture repo. The auto-migration code path in primer's Migrate mode and the new `learning`-skill duplicate-detection guard are good candidates.

4. **Plan to drop the `docs/` fallback in hooks.** v0.5.0 keeps dual-path support indefinitely. A future v1.0.0 can remove the fallback once the auto-migration has had time to land in every user's repo.

5. **Add captured learnings from the v0.4.0 session.** Three candidates still open (install-command-form verification via WebFetch, pipefail+grep/head/sed regression, `.claude/settings.json` auto-population hygiene, `GITHUB_REF_NAME` awk injection) — worth a `/session-continuity:learning` pass each. Placeholder-leakage already captured as LEARNINGS #4.

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
| "What did the last session do?" | `git log`, this primer |
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
`.session-continuity/LEARNINGS.md` too (see that file's footer for numbering rules).
