# GitHub Issues Backlog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `.session-continuity/BACKLOG.md` with open GitHub Issues labeled `backlog`; LEARNINGS stays a local file; no markdown fallback.

**Architecture:** One helper (`hooks/lib/backlog-issues.sh`) lists/counts via `${GH_BIN:-gh}`. `render.sh`, `session-start.sh`, and `primer-status.sh` call it. Write/close stays in command prose (`gh issue create` / `gh issue close`). Tests mock `GH_BIN`.

**Tech Stack:** bash, `gh`, `timeout(1)`, zsh smoke suites under `meta/superpowers/validation/`.

## Global Constraints

- Spec: `meta/superpowers/specs/2026-09-07-github-issues-backlog-design.md`
- Label name is `backlog`. No env var for the label.
- Origin must contain `github.com` (HTTPS or SSH). No GitHub Enterprise in v1.
- Operational failure: exit 0, one warning line (list mode) or `?` (count mode). Never stall SessionStart.
- Tests never call the live GitHub API. Inject `GH_BIN`.
- Do not use the whole words `proven` or `verified` in specs/plans without `Real path:` / `Stubbed:` (commit gates).
- Plugin version bump: `0.28.0` → `0.29.0`.
- Spec artifacts live under `meta/superpowers/`, not `docs/`.

---

### Task 1: `backlog-issues.sh` + smoke

**Files:**
- Create: `hooks/lib/backlog-issues.sh`
- Create: `meta/superpowers/validation/2026-09-07-backlog-issues-smoke.zsh`

**Interfaces:**
- Consumes: `GH_BIN` (default `gh`), `BACKLOG_ISSUES_TIMEOUT` (default `3`), git origin under `<project-dir>`
- Produces:
  - `backlog-issues.sh [--count] <project-dir>`
  - list stdout: `N. #NUMBER Title` per open issue, or `No open backlog issues.`, or the warning line
  - `--count` stdout: integer or `?`
  - always exit 0 on operational failure
  - warning line exact text: `Backlog unavailable: GitHub Issues required (gh, github.com remote, auth). Run /session-continuity:doctor.`
  - `gh` invocation: `issue list --label backlog --state open --json number,title --jq '.[] | "#\(.number)\t\(.title)"' --limit 100`

- [ ] **Step 1: Write the failing smoke**

Create `meta/superpowers/validation/2026-09-07-backlog-issues-smoke.zsh` that:
1. Builds a temp git repo with `origin` = `https://github.com/example/repo.git`
2. Installs a mock `GH_BIN` that prints `#12\tAlpha` and `#15\tBeta` (the `--jq` shape)
3. Asserts list mode: `$'1. #12 Alpha\n2. #15 Beta'`
4. Asserts `--count` prints `2`
5. Empty mock stdout → `No open backlog issues.` / count `0`
6. Origin `https://gitlab.com/example/repo.git` → warning line / count `?`
7. `GH_BIN=/nonexistent/gh` → warning / `?`
8. Mock exit 1 → warning / `?`

- [ ] **Step 2: Run it; expect fail** (script missing)

```bash
zsh meta/superpowers/validation/2026-09-07-backlog-issues-smoke.zsh
```

Expected: fail because `hooks/lib/backlog-issues.sh` does not exist.

- [ ] **Step 3: Write `hooks/lib/backlog-issues.sh`**

`CONTRACT_VERSION=1`. `set -u`. Parse `--count`. Default dir `.` if missing after flags.

Detect github.com:

```bash
url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
case "$url" in
  *github.com*) ;;
  *) warn_or_question_mark; exit 0 ;;
esac
```

`command -v` / executable check on `${GH_BIN:-gh}`. Wrap the `gh` call in `timeout "${BACKLOG_ISSUES_TIMEOUT:-3}"`. On non-zero, warn. Split `--jq` TSV on tab; number 1..N as `1. #12 Title`.

- [ ] **Step 4: Re-run smoke; expect all pass**

- [ ] **Step 5: Commit** (only if the user asked for commits; otherwise skip)

---

### Task 2: Wire render / session-start / primer-status; rewrite smokes; delete awk

**Files:**
- Modify: `hooks/lib/render.sh` — `render_backlog` calls `backlog-issues.sh`, `check_sibling backlog-issues.sh`
- Modify: `hooks/lib/primer-status.sh` — `BACKLOG_COUNT` from `backlog-issues.sh --count`
- Modify: `hooks/session-start.sh` — stop reading `BACKLOG.md`; inject helper lines matching `^[0-9]+\. #`; keep old-format migration nudges
- Delete: `hooks/lib/render-backlog.awk`
- Modify: `meta/superpowers/validation/2026-09-02-render-smoke.zsh`
- Modify: `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh`
- Modify: `meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh`

**Interfaces:**
- Consumes: Task 1 helper
- Produces: `/backlog` and SessionStart shortlist from GitHub; `BACKLOG_COUNT` is `?` when GitHub is unavailable (not `0`)

- [ ] **Step 1: Rewrite render-smoke backlog cases to mock `GH_BIN`**

Drop markdown heading fixtures (noncontig, dup, closed stub, fenced, commented, real BACKLOG.md copy). Keep LEARNINGS / help / update / unknown-subcommand / missing-learnings-file cases.

Backlog cases:
- Two mocked issues render `1. #12 …` / `2. #15 …`, exit 0
- Empty mock → `No open backlog issues.`
- Missing sibling `backlog-issues.sh` → exit 2
- Contract-skewed sibling → exit 2
- No project-dir / missing dir: helper warning (exit 0), not primer pointer

Install-fault: copy `render.sh` + `backlog-issues.sh` (or omit it) into an orphan dir as today.

- [ ] **Step 2: Run render-smoke; expect backlog cases fail**

- [ ] **Step 3: Switch `render.sh` `render_backlog`** to `check_sibling backlog-issues.sh` and `bash "$SCRIPT_DIR/backlog-issues.sh" "$dir"`. Delete `render-backlog.awk`. Update the file header comment (four files + GitHub Issues; help text in `render_help` too).

- [ ] **Step 4: Switch `primer-status.sh`**

```bash
issues_helper="$HERE/backlog-issues.sh"
if [ -f "$issues_helper" ]; then
  backlog_count="$(bash "$issues_helper" --count "$DIR" 2>/dev/null || echo '?')"
else
  backlog_count="?"
fi
```

LEARNINGS still uses `count-entries.sh`.

Rewrite primer-status-smoke: missing GitHub → `BACKLOG_COUNT=?` (temp repo has no origin). With origin + `GH_BIN` mock returning two lines → `2`. LEARNINGS still `0`/`1` from `count-entries.sh`.

- [ ] **Step 5: Switch `session-start.sh`**

Remove `outstanding_path` / grep `###`. After status lines:

```bash
issues_helper="$(dirname "$0")/lib/backlog-issues.sh"
if [ -f "$issues_helper" ]; then
  outstanding_items="$(bash "$issues_helper" "$cwd" 2>/dev/null || true)"
else
  outstanding_items=""
fi
if printf '%s\n' "$outstanding_items" | grep -qE '^[0-9]+\. #'; then
  outstanding_block=$'\nBacklog:\n'"$outstanding_items"$'\n\nPresent these to the user as a numbered list, numbered starting at 1 (never 0), showing each item as `#N Title`, and ask which of these (if any) they want to tackle this session.\n'
  status_outstanding="$status_backlog_count"
elif grep -q '^## Outstanding items' "$cwd/$primer_path" 2>/dev/null; then
  ... keep existing migration nudge ...
elif [ -f "$cwd/.session-continuity/OUTSTANDING_ITEMS.md" ]; then
  ... keep existing nudge ...
else
  status_outstanding="${status_backlog_count:-?}"
  outstanding_block=""
fi
```

If helper returns the warning line, it does not match `^[0-9]+\. #`, so no shortlist. Count stays `?`.

Rewrite session-start-smoke case 1 to init git+origin+`GH_BIN` mock (two issues). Case 3 empty mock → count `0`, no shortlist. Case 4 no origin → count `?`, no shortlist (not `0`). Drop case 8 (BACKLOG.md template). Keep cases 2, 5, 6, 7 (legacy path / inline heading / OUTSTANDING_ITEMS.md).

Export `GH_BIN` in the smoke so the helper never hits real `gh`.

- [ ] **Step 6: Run all three smokes plus the new helper smoke. Expect green.**

```bash
zsh meta/superpowers/validation/2026-09-07-backlog-issues-smoke.zsh
zsh meta/superpowers/validation/2026-09-02-render-smoke.zsh
zsh meta/superpowers/validation/2026-08-12-session-start-smoke.zsh
zsh meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh
```

---

### Task 3: Commands, skill, docs, template deletion, version bump

**Files:**
- Modify: `commands/primer.md`, `commands/doctor.md`, `commands/backlog.md`, `commands/end-session.md`
- Modify: `skills/session-continuity/SKILL.md`, `skills/session-continuity/REFERENCE.md`
- Modify: `skills/session-continuity/templates/SESSION_PRIMER.md`, `ROADMAP.md`, `CLAUDE_MD_SNIPPET.md`
- Delete: `skills/session-continuity/templates/BACKLOG.md`
- Modify: `README.md`, `PRIVACY.md`, `CHANGELOG.md`, `CONTRIBUTING.md` (if it lists five files), `.claude-plugin/plugin.json`
- Modify: `hooks/lib/render.sh` `render_help` copy (THE FIVE FILES → four files + GitHub Issues)

Init: copy four templates, not five. Drop `{{BACKLOG}}` prompt; ask which GitHub issues to file (`gh issue create --label backlog`). Stage four files. Placeholder grep omits `BACKLOG.md`.

New primer Step 3d (after 3c): if `BACKLOG.md` exists and origin contains `github.com`, migrate open dated headings to issues, `git rm` the file. If no github.com, leave the fossil and tell the user `doctor` will warn.

Doctor: files loop is four names. Gather also: `command -v gh`, `gh auth status` (best-effort), `git remote get-url origin`, `backlog-issues.sh --count .`. New warning row for the GitHub queue. Disclosure: backlog titles/bodies go to GitHub.

end-session: list via helper; identify by `#N`; close with `gh issue close N --reason completed`; never edit `BACKLOG.md`.

SKILL/README/REFERENCE/help text: four in-repo files + labeled GitHub Issues. Identity is `#N`. `/backlog` renders open `backlog` issues.

PRIVACY.md Last updated 2026-09-07. External calls: weekly unauthenticated version-check **and** authenticated `gh` for the backlog (list on SessionStart/`/backlog`; create/close when filing). Public repo → public issues.

plugin.json version `0.29.0`; description drops BACKLOG.md.

CHANGELOG `## [0.29.0]` Changed/Removed/Migration notes.

- [ ] **Step 1: Apply the command and docs edits**
- [ ] **Step 2: Delete the BACKLOG.md template**
- [ ] **Step 3: Re-run helper + render + session-start + primer-status smokes** (help text / version pin in render-smoke)

---

### Task 4: Migrate this repo

**Files:**
- Create GitHub label `backlog` and 11 issues on `talgolan/session-continuity`
- Modify hex-tag refs in specs, plans, primer, ROADMAP, LEARNINGS, CHANGELOG, RESUME
- Delete: `.session-continuity/BACKLOG.md`

Live tags migrated: `d7f5`→#35, `8906`→#36, `6176`→#37, `9eec`→#38, `e8e2`→#39, `c9a4`→#40, `b93c`→#41, `c60e`→#42, `d24b`→#43, `f58a`→#44, `9d17`→#45. Bodies copied from the then-current file. Closed stubs not migrated.

`gh` must run outside the tool sandbox (GraphQL Forbidden inside it).

After create, grep each tag and rewrite live refs to `#N`. Leave historical CHANGELOG mentions of old filenames if they describe past releases.

- [ ] **Step 1: `gh label create backlog --description "Agent backlog (session-continuity)" --force`**
- [ ] **Step 2: Create the 11 issues, record numbers**
- [ ] **Step 3: Rewrite refs, `git rm` BACKLOG.md**
- [ ] **Step 4: `gh issue list --label backlog --state open` shows 11**

---

## Spec coverage

| Spec section | Task |
|---|---|
| Helper contract, timeout, GH_BIN, warning text | 1 |
| render.sh / session-start / primer-status | 2 |
| Primer/doctor/end-session/backlog commands, privacy, version | 3 |
| This-repo 11-item cut | 4 |
| LEARNINGS unchanged, no markdown fallback | 1–3 (absence of fallback) |
