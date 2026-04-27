# session-continuity v0.2 Public Release Implementation Plan

> **RESUMPTION STATE (as of 2026-04-27):** Paused mid-Task 11. Tasks 1-10 fully complete and committed. Two bugs found+fixed during smoke testing. The only remaining Task-11 item is a human verification in a `--plugin-dir` Claude session — see "Resumption checklist" at the bottom of this file before continuing.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the `session-continuity` skill into a Claude Code plugin, add slash commands + hooks + auto-update, publish to GitHub (`talgolan/session-continuity`), and submit to the Anthropic plugin marketplace.

**Architecture:** Plugin-shaped repo with `.claude-plugin/plugin.json` manifest, `skills/session-continuity/` (skill + templates), `commands/` (two slash commands), `hooks/` (three shell scripts + `hooks.json`), and `.github/workflows/release.yml` for tag-triggered GitHub Releases.

**Tech Stack:** Bash (hooks), Markdown (skill + commands + docs), JSON (manifest + hooks config), GitHub Actions (release workflow).

**Working directory:** `/Users/tal.golan/.claude/skills/session-continuity/`

**Spec reference:** [docs/superpowers/specs/2026-04-27-session-continuity-v0.2-public-release-design.md](../specs/2026-04-27-session-continuity-v0.2-public-release-design.md)

---

## File Structure

**Created:**
- `skills/session-continuity/SKILL.md` (moved from root, edited)
- `skills/session-continuity/templates/SESSION_PRIMER.md` (moved from root)
- `skills/session-continuity/templates/LEARNINGS.md` (moved from root)
- `commands/primer.md`
- `commands/learning.md`
- `hooks/hooks.json`
- `hooks/session-start.sh`
- `hooks/pre-commit-check.sh`
- `hooks/version-check.sh`
- `.github/workflows/release.yml`
- `CHANGELOG.md`
- `.gitignore`

**Modified:**
- `.claude-plugin/plugin.json` (bump version, add homepage/repository)
- `README.md` (rewrite)

**Deleted:**
- `SKILL.md` (top-level; moved)
- `templates/` (top-level; moved)
- `.cursor/` (empty)

**Preserved:**
- `LICENSE` (MIT)
- `docs/superpowers/` (spec + plan)

---

## Task 1: Prep — git init and safety commit of current state

**Files:**
- Create: `.gitignore`

- [ ] **Step 1.1: Verify we're in the right directory**

Run: `pwd`
Expected: `/Users/tal.golan/.claude/skills/session-continuity`

- [ ] **Step 1.2: Confirm no git repo exists yet**

Run: `git status 2>&1 | head -1`
Expected: `fatal: not a git repository (or any of the parent directories): .git`

- [ ] **Step 1.3: Initialize git repo on main branch**

Run: `git init -b main`
Expected: `Initialized empty Git repository in ...`

- [ ] **Step 1.4: Create `.gitignore`**

Create `.gitignore` with this exact content:

```
.DS_Store
*.log
node_modules/
.cache/
```

- [ ] **Step 1.5: Stage the current snapshot and commit it as the v0.1 baseline**

This preserves the "before" state in history. The v0.2 restructure comes in later commits.

Run:
```bash
git add -A
git status
```

Expected: staged files include `.claude-plugin/plugin.json`, `LICENSE`, `README.md`, `SKILL.md`, `templates/`, `.gitignore`, and the `docs/superpowers/` spec + plan. `.cursor/` is empty so it won't appear.

- [ ] **Step 1.6: Commit the baseline**

```bash
git commit -m "chore: import v0.1 layout as baseline before v0.2 restructure"
```

Expected: commit succeeds. `git log --oneline` shows one commit.

---

## Task 2: Restructure — move skill and templates into plugin layout

**Files:**
- Move: `SKILL.md` → `skills/session-continuity/SKILL.md`
- Move: `templates/SESSION_PRIMER.md` → `skills/session-continuity/templates/SESSION_PRIMER.md`
- Move: `templates/LEARNINGS.md` → `skills/session-continuity/templates/LEARNINGS.md`
- Delete: empty `.cursor/`

- [ ] **Step 2.1: Create the skill directory**

Run: `mkdir -p skills/session-continuity`
Expected: directory created, no output.

- [ ] **Step 2.2: Move SKILL.md via git mv**

Run: `git mv SKILL.md skills/session-continuity/SKILL.md`
Expected: silent success. `git status` shows rename.

- [ ] **Step 2.3: Move the templates directory**

Run: `git mv templates skills/session-continuity/templates`
Expected: silent success. Two renames shown in `git status`.

- [ ] **Step 2.4: Remove the empty `.cursor/` directory**

`.cursor/` is empty and untracked. Remove it directly:
```bash
rmdir .cursor
```
Expected: silent success. Verify with `ls -la | grep .cursor` → no output.

- [ ] **Step 2.5: Verify the new layout**

Run: `find . -path ./.git -prune -o -type f -print | sort`

Expected output (order may vary):
```
./.claude-plugin/plugin.json
./.gitignore
./LICENSE
./README.md
./docs/superpowers/plans/2026-04-27-session-continuity-v0.2-public-release.md
./docs/superpowers/specs/2026-04-27-session-continuity-v0.2-public-release-design.md
./skills/session-continuity/SKILL.md
./skills/session-continuity/templates/LEARNINGS.md
./skills/session-continuity/templates/SESSION_PRIMER.md
```

- [ ] **Step 2.6: Commit the restructure**

```bash
git add -A
git commit -m "refactor: move skill and templates into plugin layout

Prepare for plugin distribution. SKILL.md now lives at
skills/session-continuity/SKILL.md and templates move alongside it.
Removes empty .cursor/ directory."
```

Expected: commit succeeds.

---

## Task 3: Update SKILL.md — tighten description and add plugin-affordances note

**Files:**
- Modify: `skills/session-continuity/SKILL.md`

- [ ] **Step 3.1: Replace the frontmatter description**

In `skills/session-continuity/SKILL.md`, replace the current frontmatter description line with the tightened version.

Find this line (currently line 3):
```
description: Establish and maintain cross-session memory for a project via two complementary in-repo docs — docs/SESSION_PRIMER.md (current-state, refreshed alongside substantive commits) and docs/LEARNINGS.md (accumulated-wisdom, append-only for bugs that took 15+ min to diagnose). Use when starting work on a new project, when asked about "session memory" / "context handoff" / "continuity across sessions", when a commit is imminent and these files need refreshing, or when a hard-won bug has been resolved.
```

Replace with:
```
description: Establish and maintain cross-session memory for a project via two in-repo docs — docs/SESSION_PRIMER.md (current state, refreshed alongside substantive commits) and docs/LEARNINGS.md (append-only wisdom for bugs that took 15+ min). Use when starting work, before commits, or after hard-won bugs.
```

- [ ] **Step 3.2: Add plugin-affordances paragraph after the opening description**

Find this existing paragraph (currently around line 13):
```
The two files are complementary: primer is volatile current-state, LEARNINGS is durable wisdom. A fresh session reads the primer first to get oriented, then consults LEARNINGS when something surprising happens.
```

Immediately after it, insert a blank line and this new paragraph:
```
If installed as a plugin, two commands are available: `/session-continuity:primer` (init/refresh/check the primer) and `/session-continuity:learning` (append a new LEARNINGS entry interactively). Hooks in `hooks/hooks.json` remind Claude to read the primer on session start and nudge when a `git commit` lands without a primer refresh staged.
```

- [ ] **Step 3.3: Verify the changes render correctly**

Run: `head -20 skills/session-continuity/SKILL.md`

Expected: frontmatter shows the tightened description (under ~250 chars). Body shows the new plugin-affordances paragraph.

- [ ] **Step 3.4: Commit**

```bash
git add skills/session-continuity/SKILL.md
git commit -m "docs(skill): tighten description and document plugin affordances

Description shortened from ~450 chars to ~240 for marketplace display.
New paragraph points users at the slash commands and hooks shipped by
the plugin."
```

Expected: commit succeeds.

---

## Task 4: Update `plugin.json` — version bump, homepage, repository

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 4.1: Overwrite plugin.json with the v0.2 manifest**

Write `.claude-plugin/plugin.json` with this exact content:

```json
{
  "name": "session-continuity",
  "version": "0.2.0",
  "description": "Cross-session memory for Claude Code projects via two in-repo docs: SESSION_PRIMER.md (current state) and LEARNINGS.md (hard-won bugs).",
  "author": {
    "name": "Tal Golan"
  },
  "homepage": "https://github.com/talgolan/session-continuity",
  "repository": "https://github.com/talgolan/session-continuity",
  "license": "MIT",
  "keywords": [
    "memory",
    "session",
    "handoff",
    "continuity",
    "documentation",
    "onboarding",
    "post-mortem"
  ]
}
```

- [ ] **Step 4.2: Validate the JSON**

Run: `python3 -c "import json; print(json.load(open('.claude-plugin/plugin.json'))['version'])"`
Expected: `0.2.0`

- [ ] **Step 4.3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump plugin.json to 0.2.0 with homepage and repository

Adds homepage and repository URLs (GitHub). Tightens description
to match SKILL.md for marketplace display consistency."
```

Expected: commit succeeds.

---

## Task 5: Create `/session-continuity:primer` slash command

**Files:**
- Create: `commands/primer.md`

- [ ] **Step 5.1: Create the `commands/` directory**

Run: `mkdir -p commands`
Expected: silent success.

- [ ] **Step 5.2: Write `commands/primer.md`**

Create `commands/primer.md` with this exact content:

````markdown
---
description: Init, refresh, or check docs/SESSION_PRIMER.md — dispatches based on current state.
---

# /session-continuity:primer

You are responding to the `/session-continuity:primer` slash command.

**Your job: dispatch based on the current state of `docs/SESSION_PRIMER.md`.**

## Step 1 — Detect state

Run these checks:

1. Does `docs/SESSION_PRIMER.md` exist?
2. If yes, does the `git log --oneline -5` block inside it match the actual output of `git log --oneline -5` for the primary branch?
3. If yes, is the primer file's mtime newer than HEAD's commit date?

Three states result:

- **No primer** → init mode (Step 2)
- **Primer exists but stale** (log block drifted, or mtime older than HEAD) → refresh mode (Step 3)
- **Primer exists and current** → check mode (Step 4)

## Step 2 — Init mode

1. Create `docs/` if it doesn't exist.
2. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/SESSION_PRIMER.md` to `docs/SESSION_PRIMER.md`.
3. Copy the template from `${CLAUDE_PLUGIN_ROOT}/skills/session-continuity/templates/LEARNINGS.md` to `docs/LEARNINGS.md`.
4. Fill in placeholders Claude can derive automatically:
   - `{{PROJECT_NAME}}` — from `package.json` `name`, `Cargo.toml` `name`, `pyproject.toml` `name`, or the current directory basename.
   - `{{LATEST_COMMIT_HASH_N}}` / `{{LATEST_COMMIT_SUBJECT_N}}` — from `git log --oneline -5`.
   - `{{WORKING_DIRECTORY_ABSOLUTE_PATH}}` — from `pwd`.
   - `{{TEST_COMMAND_N}}` — from `package.json` `scripts.test` if present.
5. Ask the user for the blanks that can't be derived (layout summary, packages, outstanding items, workflow conventions).
6. Stage both files: `git add docs/SESSION_PRIMER.md docs/LEARNINGS.md`.
7. Tell the user: "Primer and LEARNINGS staged. Review and commit with `git commit -m 'docs: initialize session continuity'` when ready."

**Do not commit automatically.** The user commits when ready.

## Step 3 — Refresh mode

1. Read the current `docs/SESSION_PRIMER.md`.
2. Regenerate the `git log --oneline -5` block with current output.
3. If the primer has a test-counts section, run the test command(s) found there and update the counts to match current output.
4. Ask the user: "Outstanding items — anything to remove (finished) or add (new follow-ups flagged)?"
5. Apply the edits.
6. Stage the updated primer: `git add docs/SESSION_PRIMER.md`.
7. Tell the user: "Primer refreshed and staged. Include it in your next commit (same commit as the substantive change — do not primer-commit alone)."

## Step 4 — Check mode

Report:

```
docs/SESSION_PRIMER.md: up to date against HEAD (<short-sha>)
Last refresh: <primer mtime>
Outstanding items: <count from primer>
Learnings: <count from docs/LEARNINGS.md>
```

No changes made. Exit.

## Notes

- **Never commit automatically.** Stage only.
- **Never invent test counts or outstanding items.** If something can't be derived or isn't supplied, mark it `TBD` and tell the user.
- **Respect the primer-only-commit rule.** If the user asks you to commit only the primer, warn them per `skills/session-continuity/SKILL.md` and proceed only if they confirm it's a catch-up.
````

- [ ] **Step 5.3: Commit**

```bash
git add commands/primer.md
git commit -m "feat: add /session-continuity:primer slash command

State-dispatching command: init on missing primer, refresh on stale
primer, check on current. Never commits automatically — stages only."
```

Expected: commit succeeds.

---

## Task 6: Create `/session-continuity:learning` slash command

**Files:**
- Create: `commands/learning.md`

- [ ] **Step 6.1: Write `commands/learning.md`**

Create `commands/learning.md` with this exact content:

````markdown
---
description: Append a new entry to docs/LEARNINGS.md interactively. Takes next N+1 number, inserts at top of chosen section.
---

# /session-continuity:learning $ARGUMENTS

You are responding to the `/session-continuity:learning` slash command.

**Your job: help the user append a properly-formatted entry to `docs/LEARNINGS.md`.**

If `$ARGUMENTS` is non-empty, use it as the pre-filled title.

## Step 1 — Preflight

If `docs/LEARNINGS.md` does not exist, tell the user:

> "No `docs/LEARNINGS.md` found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

Exit.

## Step 2 — Gather the recipe

Prompt the user for each field. Show examples inline.

1. **Title** (pre-filled with `$ARGUMENTS` if provided): short noun phrase. E.g. "resource_dir() returns `_up_/` paths".
2. **The trap** (what seemed reasonable but was wrong): 1-3 sentences.
3. **Symptom** (what was observed, including misleading errors): 1-3 sentences.
4. **Fix** (what actually works): 1-3 sentences + optional code block.
5. **Diagnostic signal** (optional — how to recognize this next time): one sentence. Skip if user has nothing.

## Step 3 — Choose section

Read `docs/LEARNINGS.md`. List existing section headings (lines starting with `## ` but not `### `, excluding `## Security incidents`, `## Anti-patterns we were tempted by (and rejected)`, `## Checklist for a fresh dev-env setup` which are structural).

Ask the user:

> "Which section does this belong to?
> 1. <existing section 1>
> 2. <existing section 2>
> …
> N. Security incidents
> N+1. Anti-patterns we were tempted by (and rejected)
> N+2. New section (you'll name it)"

If they pick "new section", prompt for the heading and insert it above the existing sections (not above Security/Anti-patterns/Checklist, which stay at the bottom).

## Step 4 — Compute next number

Scan `docs/LEARNINGS.md` for all `### N.` headings (regex: `^### (\d+)\.`). Take the max, add 1. New entry gets that number.

## Step 5 — Insert at top of chosen section

Compose the entry:

```markdown
### <N>. <Title>

**The trap.** <trap text>

**Symptom.** <symptom text>

**Fix.** <fix text>

[optional code block]

**Diagnostic signal** *(optional)*. <diagnostic text if supplied>

---
```

Insert immediately after the section heading (and any HTML comments that follow it). Keep a blank line between the heading and the new entry.

## Step 6 — Stage

Run: `git add docs/LEARNINGS.md`

Tell the user: "Learning #<N> appended and staged. Commit when ready — typically alongside the fix or in its own commit if the fix already landed."

**Do not commit automatically.**

## Notes

- **Numbering is stable.** Never renumber existing entries. Old entries keep their numbers even when new entries arrive at the top.
- **Never invent details.** If the user says "I don't know" for a field, leave it blank or omit it (except trap/symptom/fix, which are required — push back gently if the user skips them).
- **Redact secrets.** Never put actual credential values in the file. Use `<redacted>` or a description.
````

- [ ] **Step 6.2: Commit**

```bash
git add commands/learning.md
git commit -m "feat: add /session-continuity:learning slash command

Interactive: prompts for trap/symptom/fix/diagnostic, computes next
N+1 number, inserts at top of chosen section, stages the change.
Numbering stays stable — old entries never renumbered."
```

Expected: commit succeeds.

---

## Task 7: Create hook scripts and `hooks.json`

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/session-start.sh`
- Create: `hooks/pre-commit-check.sh`
- Create: `hooks/version-check.sh`

- [ ] **Step 7.1: Create the `hooks/` directory**

Run: `mkdir -p hooks`
Expected: silent success.

- [ ] **Step 7.2: Write `hooks/hooks.json`**

Create `hooks/hooks.json` with this exact content:

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

- [ ] **Step 7.3: Write `hooks/session-start.sh`**

Create `hooks/session-start.sh` with this exact content:

```bash
#!/usr/bin/env bash
# SessionStart hook for session-continuity.
# Emits a read-reminder when docs/SESSION_PRIMER.md is present in cwd,
# then invokes version-check.sh (weekly freshness check). Silent otherwise.

set -eu

primer="docs/SESSION_PRIMER.md"

if [ ! -f "$primer" ]; then
  exit 0
fi

cat <<'EOF'
<system-reminder>
This project has docs/SESSION_PRIMER.md. Read it before any work — it's the fastest path to context. Also check docs/LEARNINGS.md if anything surprises you.
</system-reminder>
EOF

# Weekly freshness check (best-effort, silent on failure).
script_dir="$(dirname "$0")"
if [ -x "$script_dir/version-check.sh" ]; then
  bash "$script_dir/version-check.sh" || true
fi

exit 0
```

- [ ] **Step 7.4: Make `session-start.sh` executable**

Run: `chmod +x hooks/session-start.sh`
Verify: `ls -l hooks/session-start.sh` shows `-rwxr-xr-x`.

- [ ] **Step 7.5: Write `hooks/pre-commit-check.sh`**

Create `hooks/pre-commit-check.sh` with this exact content:

```bash
#!/usr/bin/env bash
# PreToolUse hook for session-continuity. Fires on Bash tool calls.
# If the tool is about to run `git commit` AND docs/SESSION_PRIMER.md
# exists AND is not staged AND the staged diff includes code, emit a
# non-blocking reminder. Never blocks.

set -eu

# CLAUDE_TOOL_INPUT is a JSON blob describing the tool call. Extract
# the command field with a cheap grep rather than requiring jq.
command_field="$(printf '%s' "${CLAUDE_TOOL_INPUT:-}" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 || true)"

if [ -z "$command_field" ]; then
  exit 0
fi

# Extract the quoted value of the command.
command_value="$(printf '%s' "$command_field" | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)"/\1/')"

# Only act on `git commit` invocations.
case "$command_value" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

primer="docs/SESSION_PRIMER.md"

if [ ! -f "$primer" ]; then
  exit 0
fi

# Is the primer already staged?
if git diff --cached --name-only 2>/dev/null | grep -Fxq "$primer"; then
  exit 0
fi

# Is there any staged file outside docs/, README*, CHANGELOG*, LICENSE*?
code_staged="$(git diff --cached --name-only 2>/dev/null \
  | grep -Ev '^(docs/|README|CHANGELOG|LICENSE)' || true)"

if [ -z "$code_staged" ]; then
  exit 0
fi

cat <<'EOF'
<system-reminder>
⚠️ docs/SESSION_PRIMER.md is not staged for this commit, but code files are. Consider `git add docs/SESSION_PRIMER.md` if outstanding items or landed commits need an update. Skip if the primer is genuinely unaffected by this change.
</system-reminder>
EOF

exit 0
```

- [ ] **Step 7.6: Make `pre-commit-check.sh` executable**

Run: `chmod +x hooks/pre-commit-check.sh`
Verify: `ls -l hooks/pre-commit-check.sh` shows `-rwxr-xr-x`.

- [ ] **Step 7.7: Write `hooks/version-check.sh`**

Create `hooks/version-check.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Weekly freshness check against GitHub Releases. Called by session-start.sh.
# Silent on offline, rate-limited, opted-out, or already-checked-this-week.

set -eu

# Opt-out.
if [ "${SESSION_CONTINUITY_SKIP_UPDATE_CHECK:-}" = "1" ]; then
  exit 0
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity"
cache_file="$cache_dir/last-check"

mkdir -p "$cache_dir"

# Skip if cache file exists and was touched within the last 7 days.
if [ -f "$cache_file" ]; then
  now="$(date +%s)"
  mtime="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)"
  age=$(( now - mtime ))
  if [ "$age" -lt 604800 ]; then
    exit 0
  fi
fi

# Update cache timestamp BEFORE the network call so failure doesn't
# cause retry-every-session.
touch "$cache_file"

# Read installed version from plugin.json (parent of this script's dir).
script_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_json="$script_dir/../.claude-plugin/plugin.json"

if [ ! -f "$plugin_json" ]; then
  exit 0
fi

installed="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$plugin_json" \
  | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

if [ -z "$installed" ]; then
  exit 0
fi

# Fetch latest release tag.
response="$(curl -sfm 3 https://api.github.com/repos/talgolan/session-continuity/releases/latest 2>/dev/null || true)"

if [ -z "$response" ]; then
  exit 0
fi

latest="$(printf '%s' "$response" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
  | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')"

if [ -z "$latest" ]; then
  exit 0
fi

# Compare using sort -V.
if [ "$installed" = "$latest" ]; then
  exit 0
fi

top="$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -1)"

if [ "$top" != "$latest" ]; then
  # Installed is newer than latest release (dev build). Nothing to do.
  exit 0
fi

cat <<EOF
<system-reminder>
💡 session-continuity v$latest is available (you have v$installed). Run \`/plugin update session-continuity\` to upgrade.
See: https://github.com/talgolan/session-continuity/releases/tag/v$latest
(Opt out: SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1)
</system-reminder>
EOF

exit 0
```

- [ ] **Step 7.8: Make `version-check.sh` executable**

Run: `chmod +x hooks/version-check.sh`
Verify: `ls -l hooks/version-check.sh` shows `-rwxr-xr-x`.

- [ ] **Step 7.9: Smoke-test each hook locally**

Test `session-start.sh` with no primer — should be silent:
```bash
cd /tmp && mkdir -p no-primer-test && cd no-primer-test
bash "/Users/tal.golan/.claude/skills/session-continuity/hooks/session-start.sh"
```
Expected: no output, exit 0.

Test `session-start.sh` with a primer — should emit reminder:
```bash
cd /tmp && mkdir -p primer-test/docs && cd primer-test
touch docs/SESSION_PRIMER.md
bash "/Users/tal.golan/.claude/skills/session-continuity/hooks/session-start.sh"
```
Expected: `<system-reminder>` block printed. (The version check also runs; if you have no cache file, it may make a network call — that's expected behavior.)

Test `pre-commit-check.sh` with a non-commit command — should be silent:
```bash
CLAUDE_TOOL_INPUT='{"command":"ls -la"}' \
  bash "/Users/tal.golan/.claude/skills/session-continuity/hooks/pre-commit-check.sh"
```
Expected: no output, exit 0.

Test `version-check.sh` with opt-out — should be silent:
```bash
SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1 \
  bash "/Users/tal.golan/.claude/skills/session-continuity/hooks/version-check.sh"
```
Expected: no output, exit 0.

Clean up test dirs:
```bash
rm -rf /tmp/no-primer-test /tmp/primer-test
cd /Users/tal.golan/.claude/skills/session-continuity
```

- [ ] **Step 7.10: Commit the hook suite**

```bash
git add hooks/
git commit -m "feat: add SessionStart, PreToolUse, and weekly freshness hooks

- session-start.sh: reminds Claude to read the primer on project entry.
- pre-commit-check.sh: non-blocking nudge when git commit lands without
  primer staged and code is in the diff.
- version-check.sh: weekly GitHub API check for newer releases; 7-day
  cache, 3s timeout, silent on failure, opt-out via
  SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1.

hooks.json registers the two event-level hooks. Hooks auto-enable when
the plugin is installed; disabling means uninstalling the plugin."
```

Expected: commit succeeds.

---

## Task 8: Create `.github/workflows/release.yml`

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 8.1: Create the workflows directory**

Run: `mkdir -p .github/workflows`
Expected: silent success.

- [ ] **Step 8.2: Write `release.yml`**

Create `.github/workflows/release.yml` with this exact content:

```yaml
name: Release on tag

on:
  push:
    tags:
      - 'v*'

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
          awk "/^## \\[${version}\\]/,/^## \\[/" CHANGELOG.md \
            | sed '$d' > RELEASE_NOTES.md
          if [ ! -s RELEASE_NOTES.md ]; then
            echo "No CHANGELOG section for ${version}." > RELEASE_NOTES.md
          fi
          cat RELEASE_NOTES.md

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          body_path: RELEASE_NOTES.md
          draft: false
          prerelease: false
```

- [ ] **Step 8.3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add tag-triggered GitHub Release workflow

On push of any v* tag, extract the matching CHANGELOG section and
create a GitHub Release with it as the body. Falls back to a
placeholder if the section is missing."
```

Expected: commit succeeds.

---

## Task 9: Write `CHANGELOG.md`

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 9.1: Write `CHANGELOG.md`**

Create `CHANGELOG.md` with this exact content:

```markdown
# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-04-27

### Added
- `/session-continuity:primer` slash command — init, refresh, or check the primer based on current state.
- `/session-continuity:learning` slash command — append a LEARNINGS entry interactively, with stable N+1 numbering.
- `SessionStart` hook — reminds Claude to read the primer on new sessions when `docs/SESSION_PRIMER.md` is present.
- `PreToolUse` hook on `Bash` — non-blocking nudge when `git commit` runs without primer refresh staged.
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
```

- [ ] **Step 9.2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG.md following keep-a-changelog format

Documents v0.1.0 baseline and the v0.2.0 changes: plugin layout,
slash commands, hooks, freshness check, release workflow."
```

Expected: commit succeeds.

---

## Task 10: Rewrite `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 10.1: Overwrite `README.md`**

Replace the entire `README.md` with this exact content:

````markdown
# session-continuity

Cross-session memory for Claude Code projects. Two in-repo docs, two slash commands, two hooks.

## Install

```bash
claude plugins install github:talgolan/session-continuity
```

Once the plugin is live on the Anthropic marketplace, you can also discover it there. Until then, the command above works from any Claude Code install.

## What you get

- **`docs/SESSION_PRIMER.md`** — current-state snapshot. Refreshed alongside substantive commits. The fastest path for a fresh session to get productive.
- **`docs/LEARNINGS.md`** — append-only wisdom. Numbered entries for bugs that took 15+ minutes to diagnose. Graveyard of hard-won knowledge.
- **`/session-continuity:primer`** — init / refresh / check the primer. State-dispatching, never commits automatically.
- **`/session-continuity:learning`** — append a new LEARNINGS entry interactively. Computes the next number, inserts at the top of the chosen section.
- **`SessionStart` hook** — reminds Claude to read the primer on new sessions.
- **`PreToolUse` hook** — non-blocking nudge when `git commit` runs without the primer staged.
- **Weekly freshness check** — one GitHub API call per 7 days per machine. Opt-out: `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## Usage

**New project:**

```
/session-continuity:primer
```

Detects no primer exists, copies templates into `docs/`, fills derivable placeholders, asks you for the rest, stages both files.

**Before a commit:**

```
/session-continuity:primer
```

Detects drift, regenerates the `git log --oneline -5` block, prompts for outstanding-items updates, stages the refreshed primer. Commit it alongside your substantive change — **not in a primer-only commit**.

**After a painful bug (15+ min to diagnose):**

```
/session-continuity:learning
```

Prompts for trap / symptom / fix / diagnostic signal. Appends the entry at the top of the section you pick, with the next sequential number.

**Picking up an existing project:**

The `SessionStart` hook reminds Claude to read `docs/SESSION_PRIMER.md` first. Follow its "First things first" list before touching anything.

## What goes where

| Observation | Where |
|---|---|
| "The latest commit is X" | `docs/SESSION_PRIMER.md` → Current state |
| "We should refactor Y" | `docs/SESSION_PRIMER.md` → Outstanding items |
| "Bun replaces the CA trust store" | `docs/LEARNINGS.md` → new numbered entry |
| "Always use Bun" | `CLAUDE.md` (durable project convention) |
| "Last session tried X and rejected it" | `docs/LEARNINGS.md` → Anti-patterns |

**Do not put in these files:** secrets (ever — use `<redacted>`), information trivially rederivable from code, narrative fluff.

## Philosophy

Primer answers "what is true **right now**?" LEARNINGS answers "what should I know to avoid rediscovering pain?" Two files, two questions, one habit.

## Updating

```bash
/plugin update session-continuity
```

The weekly freshness check in `SessionStart` will nudge you when a new version ships. Opt out with `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`.

## Platform notes

Hooks are bash scripts and rely on `git` on PATH. On Windows, use Git Bash or WSL. Native PowerShell support is not included in v0.2.

## Contributing

Issues and PRs welcome at [github.com/talgolan/session-continuity](https://github.com/talgolan/session-continuity). Please keep the scope tight: this skill ships a two-file pattern, not a framework. PRs that fit the existing shape will move quickly; PRs that expand scope will be declined or redirected.

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 10.2: Verify length**

Run: `wc -l README.md`
Expected: under 120 lines. (Spec target was ~100; some variance is fine.)

- [ ] **Step 10.3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README around plugin installation

Drops the now-obsolete 'Option 1 vs Option 2' install discussion and
the 'Choose a license' section. Adds Install, Usage, and Updating
sections oriented around /plugin install and the shipped affordances.
Target ~100 lines; actual ~110."
```

Expected: commit succeeds.

---

## Task 11: Local install smoke test

**Files:** none modified; verification only.

- [ ] **Step 11.1: Confirm `claude` CLI is available**

Run: `which claude && claude --version`
Expected: path to `claude` binary + a version string. If missing, install Claude Code first.

- [ ] **Step 11.2: Verify the plugin loads with `--plugin-dir`**

Run from a scratch directory (so we're not testing against this repo's own docs/):
```bash
mkdir -p /tmp/session-continuity-smoke-test
cd /tmp/session-continuity-smoke-test
git init -b main
echo "# Smoke test project" > README.md
git add README.md
git commit -m "init"
```

Now launch Claude Code with the plugin loaded:
```bash
claude --plugin-dir /Users/tal.golan/.claude/skills/session-continuity
```

Expected: Claude Code starts without errors. The skill, commands, and hooks should be recognized.

- [ ] **Step 11.3: Exercise `/session-continuity:primer` (init mode)**

In the Claude session, invoke: `/session-continuity:primer`

Expected: Claude detects no primer exists, copies templates, fills derivable fields, asks for the rest. After filling in, `docs/SESSION_PRIMER.md` and `docs/LEARNINGS.md` should be staged.

- [ ] **Step 11.4: Commit the primer in the smoke test repo, then exercise refresh mode**

In the smoke test repo:
```bash
git commit -m "docs: initialize session continuity"
```

Make a no-op change and stage it:
```bash
echo "# change" >> README.md
git add README.md
```

Invoke: `/session-continuity:primer` again.

Expected: Claude detects the primer is now stale (new commit added), regenerates the `git log` block, prompts for outstanding items, stages the primer.

- [ ] **Step 11.5: Exercise `/session-continuity:learning`**

Invoke: `/session-continuity:learning`

Expected: Claude prompts for trap / symptom / fix / diagnostic, picks a section, computes number 1 (first entry), inserts, stages.

- [ ] **Step 11.6: Exercise the `PreToolUse` hook**

With staged code but no primer staged (re-unstage the primer: `git reset HEAD docs/SESSION_PRIMER.md`), ask Claude to `git commit -m "test"`.

Expected: the hook emits the ⚠️ reminder. The commit does not block.

- [ ] **Step 11.7: Exit and clean up**

```bash
rm -rf /tmp/session-continuity-smoke-test
cd /Users/tal.golan/.claude/skills/session-continuity
```

- [ ] **Step 11.8: If anything failed, fix it and bump**

If any step failed, fix the issue, commit with a clear message, and bump `plugin.json` to `0.2.1`. Update `CHANGELOG.md` with a new `[0.2.1]` section describing the fix. Re-run the smoke test.

If everything passed: proceed to Task 12.

---

## Task 12: Publish to GitHub

**Files:** none modified; external action.

- [ ] **Step 12.1: Verify `gh` CLI is available and authenticated**

Run: `gh auth status`
Expected: signed in as `talgolan`. If not, run `gh auth login`.

- [ ] **Step 12.2: Create the GitHub repo**

```bash
gh repo create talgolan/session-continuity \
  --public \
  --description "Cross-session memory for Claude Code projects via two in-repo docs: SESSION_PRIMER.md (current state) and LEARNINGS.md (hard-won bugs)." \
  --source=. \
  --remote=origin \
  --push
```

Expected: repo created, remote added, all commits pushed.

- [ ] **Step 12.3: Add repo topics**

```bash
gh repo edit talgolan/session-continuity \
  --add-topic claude-code \
  --add-topic claude-code-plugin \
  --add-topic claude-skill \
  --add-topic session-memory \
  --add-topic documentation
```

Expected: topics added.

- [ ] **Step 12.4: Set homepage URL**

```bash
gh repo edit talgolan/session-continuity \
  --homepage "https://github.com/talgolan/session-continuity"
```

Expected: homepage set. (Points to repo itself since there's no separate site.)

- [ ] **Step 12.5: Tag and push v0.2.0**

```bash
git tag v0.2.0
git push origin v0.2.0
```

Expected: tag pushed. Within ~1 minute, the `Release on tag` workflow runs.

- [ ] **Step 12.6: Verify the release workflow ran**

```bash
gh run list --workflow=release.yml --limit=1
```

Expected: one run with status `completed` and conclusion `success`.

- [ ] **Step 12.7: Verify the GitHub Release exists with correct body**

```bash
gh release view v0.2.0
```

Expected: release exists, body matches the `[0.2.0]` section of `CHANGELOG.md`.

- [ ] **Step 12.8: If the workflow failed**

Check logs: `gh run view --log-failed`.

Most likely cause: `awk` extraction mismatch. Fix the workflow, commit, delete the tag (`git tag -d v0.2.0 && git push --delete origin v0.2.0`), re-tag, re-push.

---

## Task 13: Second-machine install verification

**Files:** none modified; verification only.

This verifies the install command in `README.md` actually works end-to-end. Critical for a public release.

- [ ] **Step 13.1: Choose a "second machine" target**

Options:
- A second laptop with Claude Code installed.
- A fresh Docker container with Claude Code.
- Ask a trusted user to run the install command.

If none are available, skip this task — but note in `CHANGELOG.md` under `[0.2.0]` that first-machine verification only was done.

- [ ] **Step 13.2: Run the install command**

On the second machine:
```bash
claude plugins install github:talgolan/session-continuity
```

Expected: plugin installs successfully.

- [ ] **Step 13.3: Run a smoke-test invocation**

Start a fresh Claude session in a test directory and invoke `/session-continuity:primer`.

Expected: command is recognized, works as in Task 11.

- [ ] **Step 13.4: If install fails**

Most likely causes: missing file from the repo (e.g., the skill is in the wrong place), malformed `plugin.json`, hook script not executable after clone (git preserves +x, but double-check).

Fix, commit, bump to 0.2.1, re-tag. Go back to Task 11.

---

## Task 14: Submit to Anthropic plugin marketplace

**Files:** none modified; external action.

- [ ] **Step 14.1: Find the current submission URL**

Try in this order:
1. `https://claude.ai/settings/plugins/submit`
2. `https://platform.claude.com/plugins/submit`
3. Ask in Claude Code Discord / support if both 404.

- [ ] **Step 14.2: Complete the submission form**

Required fields (copy from `plugin.json`):
- **Name:** `session-continuity`
- **Repository:** `https://github.com/talgolan/session-continuity`
- **Description:** `Cross-session memory for Claude Code projects via two in-repo docs: SESSION_PRIMER.md (current state) and LEARNINGS.md (hard-won bugs).`
- **Author:** Tal Golan
- **License:** MIT
- **Keywords:** memory, session, handoff, continuity, documentation, onboarding, post-mortem

- [ ] **Step 14.3: Record submission status**

Once submitted, note the date in `CHANGELOG.md` under an "Unreleased" section:

```markdown
## [Unreleased]

### Added
- Submitted to Anthropic plugin marketplace on <YYYY-MM-DD>. Awaiting review.
```

Commit:
```bash
git add CHANGELOG.md
git commit -m "docs: record marketplace submission date"
git push
```

- [ ] **Step 14.4: When approval lands**

Move the "Submitted to Anthropic plugin marketplace" line from `[Unreleased]` to a new `[0.2.1]` entry with "marketplace-available" note. Bump `plugin.json` version. Tag `v0.2.1`. Push.

The release workflow runs automatically.

---

## Task 15: Wrap up — verify everything is green

**Files:** none modified; final verification.

- [ ] **Step 15.1: Review the final repo state**

```bash
cd /Users/tal.golan/.claude/skills/session-continuity
git log --oneline
git status
```

Expected: clean working tree, all commits pushed, tag `v0.2.0` present.

- [ ] **Step 15.2: Verify GitHub repo is public and discoverable**

```bash
gh repo view talgolan/session-continuity --json visibility,description,topics,url
```

Expected: `visibility: PUBLIC`, description matches, topics include the five from Task 12, URL is accessible.

- [ ] **Step 15.3: Update `docs/SESSION_PRIMER.md` for this very repo**

Meta-test: now that the plugin is installed, use its own commands on its own repo.

```bash
claude
```

Then: `/session-continuity:primer`

Expected: detects no primer exists in this repo yet, offers to init. Accept, let it fill in fields, review, commit.

This doubles as a dogfooding check — if the skill is bad at initializing its own primer, it's bad at initializing anyone's.

- [ ] **Step 15.4: Final sanity sweep**

- [ ] Repo URL works: `https://github.com/talgolan/session-continuity`
- [ ] `v0.2.0` release page exists and has body.
- [ ] Install command in README works on the author's main machine.
- [ ] Marketplace submission sent.
- [ ] `CHANGELOG.md` reflects reality.
- [ ] No secrets, no personal info, no `<redacted>` placeholders anywhere in the repo.

- [ ] **Step 15.5: Done**

Tell the user: "v0.2.0 published. Repo live at https://github.com/talgolan/session-continuity. Marketplace submission sent on <date>. Ongoing: respond to issues within a week, bump version + CHANGELOG on fixes, push tags to trigger releases."

---

## Self-review

**Spec coverage:**

| Spec section | Task(s) |
|---|---|
| Repo layout | Task 2 (restructure), Task 7 (hooks dir), Task 8 (.github/workflows), Task 9 (CHANGELOG), Task 10 (README) |
| `plugin.json` | Task 4 |
| `SKILL.md` changes | Task 3 |
| `/session-continuity:primer` | Task 5 + Task 11 (smoke test) |
| `/session-continuity:learning` | Task 6 + Task 11 (smoke test) |
| `hooks/session-start.sh` | Task 7 + Task 11 |
| `hooks/pre-commit-check.sh` | Task 7 + Task 11 |
| `hooks/version-check.sh` | Task 7 |
| `hooks/hooks.json` | Task 7 |
| `.github/workflows/release.yml` | Task 8 + Task 12 (verify workflow ran) |
| `README.md` | Task 10 |
| `CHANGELOG.md` | Task 9 + Task 14 (submission note) |
| `.gitignore` | Task 1 |
| Distribution Step 1 (GitHub repo setup) | Task 12 |
| Distribution Step 2 (local smoke test) | Task 11 |
| Distribution Step 3 (marketplace submission) | Task 14 |
| Distribution Step 4 (passive promotion) | Covered by restraint — no explicit task needed |
| Distribution Step 5 (ongoing maintenance) | Task 15.5 hands off to user |
| Acceptance criteria | Verified across Tasks 11, 12, 13, 15 |

All spec sections have task coverage. Second-machine install verification (Task 13) exceeds the spec's acceptance criteria but matches its intent ("README install command works end-to-end on a second machine / fresh Claude Code install").

**Placeholder scan:** no TODOs, no "fill in later", no generic "add error handling". The plan contains every file's full content.

**Type/name consistency:**
- Command names: `/session-continuity:primer` and `/session-continuity:learning` used consistently throughout.
- Env var: `SESSION_CONTINUITY_SKIP_UPDATE_CHECK` (never `SESSION_CONTINUITY_NO_UPDATE_CHECK` or similar variants).
- Version: `0.2.0` used consistently; `0.2.1` reserved for post-release fixes.
- Cache path: `~/.cache/session-continuity/last-check` consistent between spec and plan.
- GitHub repo path: `talgolan/session-continuity` consistent.
- Primer path: `docs/SESSION_PRIMER.md` (uppercase, always).
- Plugin manifest location: `.claude-plugin/plugin.json` (always dot-prefixed).

No inconsistencies found.

---

## Resumption checklist (2026-04-27 pause point)

### What's done

- Tasks 1-10 fully committed on `main` (13 commits total, clean tree).
- `git log --oneline` as of pause:
  ```
  29ed6d8 chore: add project .claude/settings.json with minimal allowlist
  c5e7e93 fix(hooks): read tool input from stdin JSON, not env var
  4358009 fix(primer): treat staged code as drift, not current state
  89519f8 docs: rewrite README around plugin installation
  17292c2 docs: add CHANGELOG.md following keep-a-changelog format
  8d1cfc5 ci: add tag-triggered GitHub Release workflow
  3ea7866 feat: add SessionStart, PreToolUse, and weekly freshness hooks
  f5b085e feat: add /session-continuity:learning slash command
  20995b0 feat: add /session-continuity:primer slash command
  7414bf2 chore: bump plugin.json to 0.2.0 with homepage and repository
  93a6a0d docs(skill): tighten description and document plugin affordances
  baf57ea refactor: move skill and templates into plugin layout
  be46bca chore: import v0.1 layout as baseline before v0.2 restructure
  ```

### What was learned during Task 11 smoke testing (and fixed)

Two real bugs were caught by exercising the plugin in a live Claude session via `claude --plugin-dir`:

1. **Primer check mode ignored staged code.** `/session-continuity:primer` reported "up to date" while code files were staged and a commit was imminent. Fixed in commit `4358009` by adding a 4th state-detection check: any staged file outside `docs/`, `README*`, `CHANGELOG*`, `LICENSE*` now forces refresh mode.
2. **Hooks read env vars that don't exist.** The original hooks grep'd `$CLAUDE_TOOL_INPUT`, but Claude Code delivers hook payloads as **stdin JSON**, not env vars. Additionally, hooks run with cwd at `$CLAUDE_PROJECT_DIR` (the plugin root for `--plugin-dir` installs), not the user's repo. Both hooks now parse stdin and use the `cwd` field from the JSON payload. Fixed in commit `c5e7e93`. Re-verified with 6 bash-level smoke tests (including the previously-untested nudge fire scenario — TEST 5 correctly emits ⚠️, TEST 6 correctly stays silent when primer is staged).

### What's still pending

- **Task 11 final check (human):** In a restarted `claude --plugin-dir /Users/tal.golan/.claude/skills/session-continuity` session from `/tmp/sc-smoke-test` (recreate the dir with `mkdir -p /tmp/sc-smoke-test && cd /tmp/sc-smoke-test && git init -b main && echo '# t' > README.md && git add README.md && git commit -m init` if gone), exercise the PreToolUse nudge one more time in a live session to confirm the stdin fix works end-to-end, not just in bash smoke tests.
    - Setup: `/session-continuity:primer` to init, commit the primer, then edit/stage `src/foo.js` while leaving primer unstaged, then ask Claude to `git commit -m 'test'`. Expect a `<system-reminder>` with ⚠️ in the tool-result stream.
    - If it fires: Task 11 passes.
    - If it doesn't: likely another platform quirk; investigate with Agent(claude-code-guide) for current hook docs.
- **Task 12 — publish to GitHub.** Requires explicit user confirmation before running. Commands are in Task 12 of this plan, starting with `gh auth status` and ending with tag `v0.2.0` push. The release workflow should fire automatically.
- **Task 13 — second-machine install verification (human).**
- **Task 14 — marketplace submission (human).**
- **Task 15 — wrap-up verification, including Step 15.3 where this repo uses its own `/session-continuity:primer` to create its own primer (the dogfooding moment).**

### Quick resumption command

To verify everything is still where we left it:

```bash
cd /Users/tal.golan/.claude/skills/session-continuity
git status            # should be clean, on main
git log --oneline | head -15
bash hooks/pre-commit-check.sh < /dev/null ; echo $?   # should print 0
```

If those look right, read this file from the top, then say: "I want to resume the session-continuity v0.2 release. Continue from the pending Task 11 hook verification." The next agent should skip the brainstorming + planning skills (already done, committed to git) and go straight to executing Task 11's remaining check and then Task 12 after confirmation.

