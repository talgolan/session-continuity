# session-continuity v0.2 — public release design

**Status:** Approved by user 2026-04-27. Ready for implementation plan.

## Goal

Ship `session-continuity` as a public Claude Code plugin on GitHub (`talgolan/session-continuity`), submit it to the official plugin marketplace, and keep a light-touch maintenance posture. Target audience: Claude Code users who want cross-session memory in their projects.

**Ambition level:** publish + promote with passive discovery. No launch post. A few hours of maintenance per month. Respond to issues within a week.

## Non-goals

- No website, docs site, or community spaces (Discord, Twitter).
- No dedicated CI beyond a release-automation workflow.
- No telemetry.
- No localization.
- No custom auto-update mechanism beyond GitHub's API + the Claude Code plugin update.

## Repo layout

```
session-continuity/
├── .claude-plugin/
│   └── plugin.json                    # manifest — name, version, description, repo, author, license
├── skills/
│   └── session-continuity/
│       ├── SKILL.md                   # moved from repo root; description tightened
│       └── templates/
│           ├── SESSION_PRIMER.md      # unchanged
│           └── LEARNINGS.md           # unchanged
├── commands/
│   ├── primer.md                      # /session-continuity:primer
│   └── learning.md                    # /session-continuity:learning
├── hooks/
│   ├── hooks.json                     # registers SessionStart + PreToolUse hooks
│   ├── session-start.sh               # read-on-entry reminder + weekly freshness check
│   ├── pre-commit-check.sh            # nudge on git commit without primer staged
│   └── version-check.sh               # called by session-start.sh; weekly GitHub API check
├── .github/
│   └── workflows/
│       └── release.yml                # tag-push → GitHub Release with CHANGELOG notes
├── LICENSE                            # unchanged (MIT 2026 Tal Golan)
├── README.md                          # rewritten around plugin install
├── CHANGELOG.md                       # keep-a-changelog format
└── .gitignore                         # standard
```

**Deleted from current layout:** top-level `SKILL.md`, top-level `templates/`, empty `.cursor/` directory.

## Component designs

### `plugin.json`

```json
{
  "name": "session-continuity",
  "version": "0.2.0",
  "description": "Cross-session memory for Claude Code projects via two in-repo docs: SESSION_PRIMER.md (current state) and LEARNINGS.md (hard-won bugs).",
  "author": { "name": "Tal Golan" },
  "homepage": "https://github.com/talgolan/session-continuity",
  "repository": "https://github.com/talgolan/session-continuity",
  "license": "MIT",
  "keywords": ["memory", "session", "handoff", "continuity", "documentation", "onboarding", "post-mortem"]
}
```

Version bumps from 0.1.0 to 0.2.0 because the layout restructure breaks anyone who installed 0.1.0 via `cp -R`.

### `skills/session-continuity/SKILL.md`

Two changes from the current `SKILL.md`:

1. **Description field tightened** from ~450 chars to ~240. New text:

    > Establish and maintain cross-session memory for a project via two in-repo docs — `docs/SESSION_PRIMER.md` (current state, refreshed alongside substantive commits) and `docs/LEARNINGS.md` (append-only wisdom for bugs that took 15+ min). Use when starting work, before commits, or after hard-won bugs.

2. **New paragraph near the top** pointing to the plugin affordances:

    > If installed as a plugin, two commands are available: `/session-continuity:primer` (init/refresh/check the primer) and `/session-continuity:learning` (append a new LEARNINGS entry interactively). Hooks in `hooks/hooks.json` remind Claude to read the primer on session start and nudge when a `git commit` lands without a primer refresh staged.

Everything else in the skill body stays as-is. Paths to `templates/` stay relative and still resolve correctly under the new layout (the templates move alongside the skill).

### Commands

Each command is a Markdown file with YAML frontmatter. Claude Code loads the body as a prompt when the user invokes the command; Claude uses its tools to do the actual work.

#### `commands/primer.md` → `/session-continuity:primer`

State-dispatching, no arguments. Behavior:

- **`docs/SESSION_PRIMER.md` doesn't exist** → init mode. Copy `skills/session-continuity/templates/SESSION_PRIMER.md` and `templates/LEARNINGS.md` into the project's `docs/`. Fill placeholders Claude can derive (project name from `package.json` / dir name, latest five commits from `git log`, test commands from `package.json` scripts if present). Ask the user for the rest. Commit both files together.
- **Primer exists and is stale** (any of: primer file mtime is older than HEAD commit, or `git log --oneline -5` block in primer doesn't match actual `git log`) → refresh mode. Regenerate the `git log --oneline -5` block. Re-run test commands and update counts if they drifted. Prompt the user about outstanding items. Stage the primer change.
- **Primer exists and is fresh** → check mode. Report: primer is up to date against HEAD, last refresh at commit `<sha>`, X outstanding items, Y learnings.

#### `commands/learning.md` → `/session-continuity:learning`

Interactive. Optional arg: short description, used to pre-fill the title. Behavior:

1. Prompt the user for each of: trap (what seemed reasonable but was wrong), symptom (what was observed), fix (what actually works), diagnostic signal (optional, how to recognize next time).
2. Read `docs/LEARNINGS.md`. List existing section headings. Ask which section this belongs to, offering "new section" as an option.
3. Compute next number: highest existing number + 1 across the whole file.
4. Insert the new entry at the top of the chosen section with the computed number.
5. Stage the change with `git add`.

### Hooks

`hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/pre-commit-check.sh" }
        ]
      }
    ]
  }
}
```

#### `hooks/session-start.sh`

Logic:

1. If the current working directory does not contain `docs/SESSION_PRIMER.md` → exit 0 silently. (Hook is a no-op on unrelated projects.)
2. Emit a `<system-reminder>`-style message via stdout:

    > "This project has `docs/SESSION_PRIMER.md`. Read it before any work — it's the fastest path to context. Also check `docs/LEARNINGS.md` if anything surprises you."

3. Invoke `version-check.sh` (see below). That script decides whether to emit anything based on the weekly cache.
4. Exit 0.

#### `hooks/pre-commit-check.sh`

Logic:

1. Parse `$CLAUDE_TOOL_INPUT` JSON to extract the bash command.
2. If the command doesn't match `git commit` (or `git commit -...`) → exit 0 silent.
3. If `docs/SESSION_PRIMER.md` doesn't exist → exit 0 silent.
4. `git diff --cached --name-only` → get staged files.
5. If `docs/SESSION_PRIMER.md` is staged → exit 0 silent (user is doing the right thing).
6. If the staged list contains any non-docs file (heuristic: anything outside `docs/`, `README`, `CHANGELOG`, `LICENSE`) → emit non-blocking reminder:

    > "⚠️ Primer not staged. This commit touches code — consider `git add docs/SESSION_PRIMER.md` if outstanding items or landing commits need an update. Skip if the primer is genuinely unaffected."

7. Exit 0 regardless. **Never blocks a commit.**

#### `hooks/version-check.sh`

Called by `session-start.sh`. Weekly GitHub API freshness check.

Logic:

1. If `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1` → exit 0 silent.
2. Compute cache path: `~/.cache/session-continuity/last-check`. Create parent dir if missing.
3. If cache file exists and its mtime is less than 7 days old → exit 0 silent.
4. `touch` the cache file (updates mtime). Do this *before* the network call so a failing call doesn't cause retry-every-session.
5. `curl -sfm 3 https://api.github.com/repos/talgolan/session-continuity/releases/latest` — 3-second timeout, silent fail.
6. On failure or empty response → exit 0 silent.
7. Parse `tag_name` from JSON (use a shell-only parser — no `jq` dependency; `grep -oE '"tag_name":"v[^"]+"' | cut` works).
8. Read installed version from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` (same grep trick on the `"version"` field).
9. Compare via `sort -V`:
    ```sh
    if [ "$(printf '%s\n%s' "$installed" "$latest" | sort -V | tail -1)" = "$latest" ] \
       && [ "$installed" != "$latest" ]; then
      emit_reminder
    fi
    ```
10. On newer version available, emit:

    > "💡 session-continuity v$latest available (you have v$installed). Run `/plugin update session-continuity` to upgrade. See: https://github.com/talgolan/session-continuity/releases/tag/v$latest"

11. Exit 0.

**Guarantees:** at most one GitHub API call per 7 days per machine. Silent on offline, rate-limited, or API-down. One env var opt-out.

### `.github/workflows/release.yml`

```yaml
name: Release on tag
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Extract CHANGELOG section for this tag
        id: changelog
        run: |
          version="${GITHUB_REF_NAME#v}"
          awk "/^## \[${version}\]/,/^## \[/" CHANGELOG.md | sed '$d' > RELEASE_NOTES.md
          cat RELEASE_NOTES.md
      - uses: softprops/action-gh-release@v2
        with:
          body_path: RELEASE_NOTES.md
          draft: false
          prerelease: false
```

Push a `vX.Y.Z` tag → workflow creates a release with the matching `CHANGELOG.md` section as the body.

### `README.md` (rewritten, target ~100 lines)

Structure:

1. Title + one-sentence pitch.
2. **Install.** Single command: `claude plugins install github:talgolan/session-continuity`. Note marketplace availability once live.
3. **What you get.** Bullet list: two docs (primer + learnings), two commands, two hooks, auto-release.
4. **Usage.** Typical flows — new project, existing project, pre-commit, post-bug. ~15 lines.
5. **What goes where.** Decision table from SKILL.md, condensed.
6. **Philosophy.** Two lines.
7. **Updating.** `/plugin update session-continuity`. Mention the weekly freshness nudge and the `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1` opt-out.
8. **Contributing.** Link to issues. Note scope policy (we don't expand beyond the two-file pattern).
9. **License.** MIT, link to LICENSE.

Drops from current README: the "Option 1 vs Option 2" installation discussion, the "Choose a license" section, the long maintenance rules (they're in `SKILL.md` + templates).

### `CHANGELOG.md`

Keep-a-Changelog format:

```markdown
# Changelog

## [0.2.0] — 2026-04-27

### Added
- `/session-continuity:primer` slash command — init, refresh, or check the primer.
- `/session-continuity:learning` slash command — append a LEARNINGS entry interactively.
- `SessionStart` hook — remind Claude to read the primer on new sessions.
- `PreToolUse` hook — nudge when `git commit` runs without primer refresh staged.
- Weekly freshness check inside `SessionStart` (opt-out: `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`).
- Auto-release workflow on tag push (`.github/workflows/release.yml`).
- `CHANGELOG.md`.

### Changed
- Restructured to Claude Code plugin layout (`skills/session-continuity/`). Skill lives at `skills/session-continuity/SKILL.md`; templates at `skills/session-continuity/templates/`.
- Tightened `SKILL.md` `description` for marketplace display.
- `README.md` rewritten around plugin installation.
- `plugin.json` bumped to 0.2.0; added `homepage` and `repository` fields.

### Removed
- Empty `.cursor/` directory.
- "Choose a license" section in README (LICENSE already exists).

## [0.1.0] — 2026-04-26

Initial release. Two-file session continuity pattern: `SESSION_PRIMER.md` + `LEARNINGS.md`.
```

### `.gitignore`

Standard. At minimum:

```
.DS_Store
*.log
node_modules/
.cache/
```

## Distribution plan

### Step 1 — GitHub repo setup

- `git init` in the current working directory.
- Stage all v0.2 files. First commit: `Initial public release (v0.2.0)`.
- Create `talgolan/session-continuity` on GitHub, public.
- Push `main`. Tag `v0.2.0`. Push tags.
- GitHub repo description: matches `plugin.json` `description`.
- Topics: `claude-code`, `claude-code-plugin`, `claude-skill`, `session-memory`, `documentation`.
- No branch protection (solo maintainer).

### Step 2 — Local install smoke test

Before announcing: `claude --plugin-dir ./session-continuity` and exercise both commands and both hooks against a real project that has a primer. Fix anything broken. If fixes are needed, bump to 0.2.1 and retag.

### Step 3 — Marketplace submission

Submit via `claude.ai/settings/plugins/submit` (or `platform.claude.com/plugins/submit`; verify live URL at submission time). Form fields are already in `plugin.json`. If the form asks for additional copy, reuse README sections.

### Step 4 — Passive promotion only

No blog post, no launch thread. Link to the repo when the topic comes up organically (issues, Discord, replies). That's the extent of active promotion.

### Step 5 — Ongoing maintenance

- Respond to GitHub issues within a week.
- Accept PRs that fit the two-file philosophy; decline scope expansion.
- Semver: patch for fixes, minor for new commands/hooks/templates, major for schema breaks.
- Keep `CHANGELOG.md` honest.
- Tag pushes trigger the release workflow — no manual GitHub Release editing.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Marketplace submission takes weeks | Repo still installable via GitHub URL. Not blocking. |
| Hooks fail on Windows without a bash shim | Documented in README. v0.3+ could rewrite in Node if demand surfaces. |
| GitHub API rate limits the freshness check | 7-day cache, 3s timeout, silent fail. At 60 req/hr unauth limit, non-issue for a single user. |
| User finds the SessionStart reminder noisy | It only fires when `docs/SESSION_PRIMER.md` exists. If noisy, disable the plugin or delete the file. |
| Version regression in a release | Local smoke test before tagging. CHANGELOG forces explicit discipline. |

## Acceptance criteria

- Repo structure matches the diagram above.
- `plugin.json` validates; `claude --plugin-dir ./session-continuity` loads the plugin without errors.
- `/session-continuity:primer` works in all three states (init, refresh, check) on a test project.
- `/session-continuity:learning` appends a correctly-numbered entry to `docs/LEARNINGS.md`.
- `SessionStart` hook emits the read-reminder on a project with `docs/SESSION_PRIMER.md`, is silent otherwise.
- `PreToolUse` hook emits the commit-reminder when `git commit` is staged without the primer, is silent otherwise.
- `version-check.sh` honors the 7-day cache and the env-var opt-out.
- Pushing `v0.2.0` tag triggers the release workflow and produces a GitHub Release with CHANGELOG notes.
- README install command works end-to-end on a second machine / fresh Claude Code install.
- Marketplace submission form filled and sent.
