# Design: GitHub Issues replace BACKLOG.md

Date: 2026-09-07
Status: approved (brainstorming complete)

## Problem

`.session-continuity/BACKLOG.md` is the wrong tool for a work queue.

Observed in this repo: 18 headings, ~7 of them closed stubs that could
not be deleted because a tag still appeared somewhere in the tree.
Positions 1..N mixed live work and graves. Identity was rewritten twice
(permanent numbers, then hex tags plus ephemeral positions). The file
diffs, merge-conflicts, and sits uncommitted. Agents file and close it
unreliably. There is no discussion, no PR link, no assignee.

The markdown file also fights the plugin's own product pitch in a
different way than we first thought: a queue wants stable IDs, close
semantics, and a UI humans already use. GitHub Issues already have those.
A local recipe book (LEARNINGS.md) does not — that file stays.

## Goals

1. Open GitHub Issues with the label `backlog` are the plugin's backlog
   for every consuming project whose origin is github.com.
2. `/session-continuity:backlog`, SessionStart injection, and
   `primer-status.sh`'s `BACKLOG_COUNT` read that list. Zero *model*
   calls still hold; the helper shells out to `gh`.
3. File with `gh issue create --label backlog`. Close with
   `gh issue close N --reason completed`, only after the item is checked
   against the actual code (same ritual as today — Issues do not prove
   the code shipped).
4. Delete `.session-continuity/BACKLOG.md` from the shipped template,
   from primer init, and from this repo after migrating the 11 live
   items. No markdown fallback.
5. LEARNINGS.md, SESSION_PRIMER.md, PROJECT_CONTEXT.md, and ROADMAP.md
   stay in-repo files. Fire-before-action still greps local LEARNINGS.

## Non-goals

- LEARNINGS.md as GitHub Issues (even with a local cache).
- ROADMAP.md as GitHub Milestones or Projects.
- GitHub Enterprise remotes (`github.com` only for v1).
- Live `gh` in CI. Tests mock `gh`.
- A `SESSION_CONTINUITY_BACKLOG_LABEL` env var. The label name is
  `backlog`.
- Dual-write to a leftover `BACKLOG.md`.

## Decisions

- **Label filter, not all-open.** SessionStart must not dump every bug
  in a consuming repo into the prompt. Only issues labeled `backlog`
  count. A human promotes a bug into the agent queue by adding the
  label. If a repo already uses that label for 80 tickets, those *are*
  the agent queue — document it, do not paper over it.
- **GitHub-or-bust. No markdown fallback.** Two sources of truth is how
  the first week's `gh` outage silently revives the file we are killing.
  No GitHub remote / no `gh` / auth failure → `/backlog` and SessionStart
  injection no-op with a `doctor` warning. Do not read a leftover
  `BACKLOG.md`.
- **Fail open on SessionStart.** The helper has a ~3s timeout. Slow API
  or stale auth skips injection and warns. Never stall the session.
- **Identity is `#N`.** Cross-references in specs, primer, ROADMAP, and
  LEARNINGS use the GitHub issue number. Hex tags die with the file.
- **Length cap stays a skill rule.** Title + 1–3 sentences; longer
  discussion lives in a spec and is linked from the issue body. Not a
  commit gate.
- **Create the `backlog` label if missing** on first `gh issue create`.
- **Privacy is a material change.** Filing sends title + body to GitHub;
  SessionStart and `/backlog` read them back with authenticated `gh`.
  Public repo → public issues. `PRIVACY.md`, README, and `doctor` each
  say this in one sentence.

## Runtime

One helper, three call sites.

### `hooks/lib/backlog-issues.sh`

`CONTRACT_VERSION=1`.

```
backlog-issues.sh [--count] <project-dir>
```

Resolves `origin` under `<project-dir>`. Origin must contain `github.com`
(HTTPS or SSH). Invokes `${GH_BIN:-gh}`:

```
gh issue list --label backlog --state open --json number,title \
  --limit 100
```

Default list output, one line per issue, in the order `gh` returns:

```
1. #12 Title
2. #15 Other title
```

`--count` prints a single integer (the number of those issues), or `?`
on any failure.

Timeout: `${BACKLOG_ISSUES_TIMEOUT:-3}` seconds, via `timeout(1)`.

Always exit 0 on operational failure (no git, origin not github.com,
`gh` missing, non-zero, timeout, unparseable JSON). Print exactly one
warning line on stdout in the list mode:

```
Backlog unavailable: GitHub Issues required (gh, github.com remote, auth). Run /session-continuity:doctor.
```

Empty-but-working: `No open backlog issues.` (list mode) / `0` (count
mode).

Tests inject a mock by setting `GH_BIN`. No live GitHub API in CI.

Broken install (the script itself missing when a caller expects it) is
the caller's problem — `render.sh` keeps the sibling +
`CONTRACT_VERSION` gate and exits 2.

### Call sites

| Caller | Behavior |
|---|---|
| `hooks/lib/render.sh` `backlog` | `check_sibling backlog-issues.sh`, print helper stdout. Stop reading `BACKLOG.md`. Delete `hooks/lib/render-backlog.awk`. |
| `hooks/session-start.sh` | Inject helper list lines when they match `^[0-9]+\. #`. On warning / empty / fail, skip the shortlist (do not stall). Stop grepping `BACKLOG.md`. Keep the old-format migration nudges (`## Outstanding items` in the primer, leftover `OUTSTANDING_ITEMS.md`) pointing at `/session-continuity:primer`. |
| `hooks/lib/primer-status.sh` | `BACKLOG_COUNT` from `backlog-issues.sh --count`. LEARNINGS still uses `count-entries.sh`. |

### Write path (skill + commands, not a daemon)

File:

```
gh label create backlog --description "Agent backlog (session-continuity)" --force
gh issue create --label backlog --title "..." --body "..."
```

`--force` on `label create` is idempotent if the label already exists.

Close, only after checking the claim against the actual code:

```
gh issue close N --reason completed
```

## Primer, doctor, commands

### Primer init

Stop copying `skills/session-continuity/templates/BACKLOG.md`. Delete
that template. Init stages four files: `SESSION_PRIMER.md`,
`PROJECT_CONTEXT.md`, `ROADMAP.md`, `LEARNINGS.md`.

### Primer migrate

- Consumer has `BACKLOG.md` **and** a github.com origin: one-shot
  migrate. Open items (heading has `[YYYY-MM-DD]`, not a `— closed.`
  stub) become issues labeled `backlog`. Stubs skipped. File deleted
  (`git rm`). Hex-tag mentions in the same repo should be rewritten to
  `#N` when the agent can map them; leftover tags in historical docs
  are acceptable.
- Consumer has `BACKLOG.md` and **no** github.com origin: leave the
  file. `doctor` warns the queue is inactive. The file is a fossil, not
  a backend.
- `OUTSTANDING_ITEMS.md` / inline `## Outstanding items`: existing
  rename/extract steps still run, then the GitHub migrate step above
  applies to the resulting `BACKLOG.md`.

### Doctor

Drop `BACKLOG.md` from the required-files loop (four files remain).
Add warning-level checks, not a hard install break: `gh` on PATH, `gh
auth status` succeeds, origin contains `github.com`, helper returns a
count that is not `?`. Mention that backlog titles/bodies go to GitHub.

### `/session-continuity:backlog` and `/end-session`

`commands/backlog.md` still runs `render.sh backlog`. Failure copy
points at `doctor`, not at a missing file.

`commands/end-session.md` lists open `backlog` issues via the helper,
checks each appears-done item against the code, and closes via
`gh issue close`. It never edits `BACKLOG.md`.

## Privacy

Today: nothing leaves the machine except one weekly unauthenticated
version-check GET.

After: filing a backlog item sends title + body to GitHub; SessionStart
and `/backlog` read them back with authenticated `gh`. Public repository
→ public issues. Version-check is unchanged.

Update `PRIVACY.md` (Last updated date, short version, "What data",
"External network calls", "Third-party services"). Same one-sentence
disclosure in README and `doctor`.

## This repo's cut

11 live items become issues, then the file is deleted:

| Tag | Issue | Title |
|---|---|---|
| `d7f5` | #35 | Submit to the Anthropic marketplace |
| `8906` | #36 | Automated integration tests |
| `6176` | #37 | Scratch-project smoke test for the primer split |
| `9eec` | #38 | Global docs-current hooks check "touched," not "accurate" |
| `e8e2` | #39 | `agent-active.sh` fallback treats every transcript as if it has `turn_duration` records |
| `c9a4` | #40 | `overlap()` dedup in `candidate-extract.jq` is an asymmetric Jaccard |
| `b93c` | #41 | Determinism Phase 4 — `end-session` Step 3 checklist assembly |
| `c60e` | #42 | Determinism Phase 5 — backlog mechanics and the commit-overlap gate |
| `d24b` | #43 | Determinism Phase 6 — `primer` detect, migrate, init, drift |
| `f58a` | #44 | Determinism Phase 7 — the commit gate that keeps the invariant true |
| `9d17` | #45 | File the concrete `/session-continuity:doctor` retrofit once `4a9d` is decided |

Closed stubs (`6258`, `3b71`, `5c2d`, `8e4a`, `a17f`, `4a9d`, `52dc`)
stay in git history only. Create the `backlog` label on
`talgolan/session-continuity`. Rewrite live hex-tag refs to `#N`.

Phase 5 of the determinism program (#42) was "backlog mechanics"
(hex-tag minting, position renumber, grep-before-delete). That work is
moot for a GitHub-backed queue; the issue stays open until Phase 5 is
re-scoped against this design.

## Tests

New: `meta/superpowers/validation/2026-09-07-backlog-issues-smoke.zsh`.
Mock `GH_BIN`. Cases: two issues render as `1. #12 …` / `2. #15 …`;
`--count`; empty list; origin not github.com; `gh` missing; `gh`
non-zero; timeout (optional if the mock can sleep past the timeout).

Rewrite backlog cases in:

- `meta/superpowers/validation/2026-09-02-render-smoke.zsh` — drop
  markdown-heading fixtures; mock `GH_BIN`; keep LEARNINGS / help /
  update cases; sibling-missing now targets `backlog-issues.sh`.
- `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh` —
  inject via mock `gh`, not `BACKLOG.md` contents. Keep old-format
  migration nudges. Fresh-install template case goes away with the
  template.
- `meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh` —
  `BACKLOG_COUNT` comes from the mock, not `count-entries.sh`. Missing
  GitHub → `?`, not `0`.

`hooks/lib/count-entries.sh` stays. Its smoke stays. LEARNINGS still
uses it.

## Docs / version

0.x breaking change. Bump `.claude-plugin/plugin.json` to `0.29.0`.
CHANGELOG entry. README, SKILL.md, REFERENCE.md, CONTRIBUTING.md,
`commands/help.md`, `templates/CLAUDE_MD_SNIPPET.md`,
`.claude-plugin/plugin.json` description: four in-repo files + GitHub
Issues for the queue.

## Out of scope

LEARNINGS as Issues. ROADMAP as milestones. GitHub Enterprise. Live
`gh` in CI. Label-name configuration. Dual-write.
