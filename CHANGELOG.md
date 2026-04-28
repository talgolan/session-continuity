# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-04-28

### Added
- `/session-continuity:end-session` slash command — zero-arg close-out ritual. Refreshes the primer (Step 1 delegates to `/session-continuity:primer` refresh mode), reflects on session context to surface LEARNINGS candidates and appends any the user accepts (Step 2 delegates to `/session-continuity:learning`), then emits a ✓ / ⚠️ checklist of staged / unstaged / untracked / unpushed state with a suggested commit message. The checklist enumerates every file from each `git` probe — summaries or "primary file" reductions are explicitly disallowed so nothing gets overlooked before close.

### Changed
- `README.md` lists the new command.
- `SKILL.md` plugin-affordances paragraph mentions the new command.

## [0.2.0] — 2026-04-27

### Added
- `/session-continuity:primer` slash command — init, refresh, or check the primer based on current state.
- `/session-continuity:learning` slash command — append a LEARNINGS entry interactively, with stable N+1 numbering.
- `SessionStart` hook — reminds Claude to read the primer on new sessions when `docs/SESSION_PRIMER.md` is present.
- `PreToolUse` hook on `Bash` — non-blocking nudge when `git commit` runs without primer refresh staged. Uses `hookSpecificOutput.additionalContext` JSON so the reminder reaches Claude's context (plain stdout is ignored for `PreToolUse`).
- Weekly freshness check inside `SessionStart` — one GitHub API call per 7 days per machine, opt-out via `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.
- Auto-release workflow on tag push (`.github/workflows/release.yml`).
- `CHANGELOG.md`.

### Changed
- Restructured to Claude Code plugin layout. Skill now at `skills/session-continuity/SKILL.md`; templates at `skills/session-continuity/templates/`.
- Tightened `SKILL.md` `description` for marketplace display (~240 chars, down from ~450).
- `README.md` rewritten around plugin installation.
- `plugin.json` bumped to 0.2.0; added `homepage` and `repository` fields.

### Removed
- Empty `.cursor/` directory.
- "Choose a license" section in `README.md` (`LICENSE` already exists).

## [0.1.0] — 2026-04-26

Initial release. Two-file session continuity pattern: `docs/SESSION_PRIMER.md` (current state) + `docs/LEARNINGS.md` (append-only wisdom).
