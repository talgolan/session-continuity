# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] — 2026-04-28

### Added
- `.claude-plugin/marketplace.json` — single-plugin marketplace catalog, required for `/plugin marketplace add talgolan/session-continuity` + `/plugin install session-continuity@session-continuity` to work. Previous `claude plugins install github:...` form in the README was incorrect.
- `SECURITY.md` — scope, reporting instructions (GitHub Security Advisories), and design notes relevant to security reviewers.
- Detailed in-file comments across all three hook scripts and the release workflow, explaining the Claude Code hook contract, the JSON-parsing design choices, and the security boundaries.

### Changed
- **`hooks/hooks.json`** — `PreToolUse` hook now uses the per-hook `if: "Bash(git commit *)"` field so the script only spawns on actual `git commit` invocations (previously it fired on every `Bash` tool call). Docs: <https://code.claude.com/docs/en/hooks.md>.
- **`commands/end-session.md` Step 1** — now runs a silent drift check before prompting. If the primer's `git log --oneline -5` block already matches reality, the step is a no-op and the user is not asked about outstanding items. Previously every `/session-continuity:end-session` invocation prompted even on clean repos.
- **`hooks/version-check.sh`** — reads the repository slug from `.claude-plugin/plugin.json`'s `repository` field instead of hardcoding it, so renaming or transferring the repo no longer silently breaks the update check. Defensive regex validation on the parsed slug; hardcoded default is still present as a fallback.
- **`.github/workflows/release.yml`** — validates `GITHUB_REF_NAME` against a strict semver regex before letting it reach `awk`, and switches the awk match from regex (`~`) to `index()` (string-literal) so crafted tag names can never become pattern metacharacters.
- **`skills/session-continuity/SKILL.md` "Quick start"** — now tells Claude to run `/session-continuity:primer` rather than walking through a manual template-copy dance that bit-rotted after the plugin layout refactor.
- **`README.md`** — corrected install instructions (`/plugin marketplace add` + `/plugin install`), clarified the `PreToolUse` hook scope, and updated the Updating section to match.
- **`hooks/*.sh`** — added `set -o pipefail` alongside `set -eu`, and rewrote the headers with full rationale for each design choice (JSON-parsing via `grep`/`sed` vs `jq`, failure-mode contract, security notes).
- Repo layout: `docs/administrative/` and `docs/superpowers/` moved under a new top-level `meta/` directory. `docs/` now contains only the two files the plugin ships (primer + LEARNINGS), matching what users see in their own projects.

### Fixed
- Curly apostrophe (U+2019) in `skills/session-continuity/templates/SESSION_PRIMER.md` replaced with a straight `'` — the template is the canonical text Claude copies into user projects, so it should be free of unicode decoration (per the project's own style guidance).
- `docs/SESSION_PRIMER.md` path reference now correctly shows `.claude-plugin/plugin.json`, not `plugin.json`.

## [0.3.0] — 2026-04-28

### Added
- `/session-continuity:end-session` slash command — zero-arg close-out ritual. Step 1 refreshes the primer (sharing logic with `/session-continuity:primer`'s refresh mode), Step 2 reflects on session context to surface LEARNINGS candidates and appends any the user accepts (delegating to `/session-continuity:learning`'s append flow), and Step 3 emits a ✓ / ⚠️ checklist of staged / unstaged / untracked / unpushed state with a suggested commit message. The checklist enumerates every file from each `git` probe — summaries or "primary file" reductions are explicitly disallowed so nothing gets overlooked before close.

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
