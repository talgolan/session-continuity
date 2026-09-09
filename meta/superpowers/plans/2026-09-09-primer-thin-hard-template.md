# Thin hard-template SESSION_PRIMER Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the thin hard-template SESSION_PRIMER contract from `meta/superpowers/specs/2026-09-09-primer-thin-hard-template-design.md`: validator + peer probes, SessionStart/doctor hard-incomplete on missing engrim/graphify, slim-migrate for fat primers, banlist git-log blocks.

**Architecture:** Two new `CONTRACT_VERSION=1` helpers (`peer-probes.sh`, `primer-validate.sh`) plus a freshness helper used by doctor/SessionStart. Template and command prose shrink to Mid-flight/Confirm only. SessionStart gains a missing-primer nudge and a peer hard-stop (**inject-only** — never mutates the primer file). Tests are hermetic zsh smokes with injectable `ENGRIM_BIN` and fixture `graphify-out/graph.json`.

**Tech Stack:** bash, zsh smokes under `meta/superpowers/validation/`, `engrim` CLI (`engrim context`), graphify artifact `graphify-out/graph.json`, existing `require_script` / `primer-status.sh` patterns.

## Global Constraints

- Spec: `meta/superpowers/specs/2026-09-09-primer-thin-hard-template-design.md` (revised post-review).
- Paths: `.session-continuity/SESSION_PRIMER.md`, `LEARNINGS.md`, `PROJECT_CONTEXT.md`, `ROADMAP.md`.
- Graphify probe target is **only** `graphify-out/graph.json` (non-empty file).
- **graph.json policy (locked):** consuming repos **commit** `graphify-out/graph.json` (regenerate via `/graphify` / `graphify` update when code shape changes). Do **not** gitignore it. Fresh clone must probe green without a local graphify rebuild. Dogfood in Task 8 commits the file.
- Engrim probe: `timeout "${PEER_PROBES_TIMEOUT:-2}" "${ENGRIM_BIN:-engrim}" context -b 200` (exit 0 → ok). Injectable `ENGRIM_BIN` for tests (same pattern as `GH_BIN`).
- Validator is the only shape gate. Agent prose may not be the sole enforcement.
- `commands/primer.md` / `commands/doctor.md` / `commands/end-session.md` must call new helpers through `require_script … 1` (same pattern as `primer-detect.sh`), not bare `bash` paths alone.
- Line budget: ≤80 lines **excluding** the Confirm fenced block.
- Confirm count: non-empty, non-`#` lines inside the single `bash` fence under `## Confirm`.
- Freshness: ⚠️ only (substantive commits after last primer touch). Hard-fail = shape + peers.
- Freshness ignore list matches on **basename only** (`$(basename "$path")`): `README*`, `CHANGELOG*`, `LICENSE*`. So `docs/README.md` is ignored; `src/foo.sh` is not.
- SessionStart: missing primer → one-line nudge, exit 0. Primer present + peer fail → hard-stop text. **Never writes** SESSION_PRIMER (Peers status inject-only into the reminder).
- No live MCP / live GitHub / live engrim DB required in CI — mock `ENGRIM_BIN`.
- Plugin version bump: `0.35.0` → `0.36.0` (minor: consuming-primer contract change).
- Product copy: update `PRIVACY.md` + README (one sentence each) that boot expects local engrim + committed `graphify-out/graph.json`.
- Spec/plan artifacts under `meta/superpowers/`, not `docs/`.
- Do not commit unless the user asked; task Commit steps are optional gates.
- Smoke fixtures live **inside each smoke’s `mktemp` tree** (or heredocs). Do **not** add a new `validation/fixtures/` convention.

## File map

| File | Role |
|---|---|
| `hooks/lib/peer-probes.sh` | ENGRIM/GRAPHIFY probes; always exit 0 |
| `hooks/lib/primer-validate.sh` | Shape/banlist/caps; exit 0/1 |
| `hooks/lib/primer-freshness.sh` | STALE=0\|1\|?; always exit 0 |
| `hooks/session-start.sh` | Missing-primer nudge; peer hard-stop; freshness line (inject-only) |
| `skills/session-continuity/templates/SESSION_PRIMER.md` | Thin template |
| `skills/session-continuity/templates/PROJECT_CONTEXT.md` | Drop git-log maintenance |
| `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md` | Boot order + peers |
| `commands/primer.md` | Init/refresh/slim-migrate/check + `require_script` |
| `commands/doctor.md` | Validate + peers + freshness; drop git-log compare |
| `commands/end-session.md` | Thin refresh; no git-log regen |
| `hooks/pre-commit-check.sh` | Reminder text only (Mid-flight/Confirm) |
| `PRIVACY.md` / `README.md` | Peer disclosure sentences |
| `.session-continuity/SESSION_PRIMER.md` | Dogfood slim-migrate |
| `.session-continuity/PROJECT_CONTEXT.md` | Dogfood Maintenance edit |
| `graphify-out/graph.json` | Committed dogfood artifact |
| `CHANGELOG.md` / plugin manifests | `0.36.0` |
| Smokes | new validation scripts listed per task |

---

### Task 1: `peer-probes.sh` + smoke

**Files:**
- Create: `hooks/lib/peer-probes.sh`
- Create: `meta/superpowers/validation/2026-09-09-peer-probes-smoke.zsh`

**Interfaces:**
- Consumes: project dir (default `.`), `ENGRIM_BIN` (default `engrim`), `PEER_PROBES_TIMEOUT` (default `2`)
- Produces stdout (exactly two lines, order fixed):
  - `ENGRIM=ok|missing|error`
  - `GRAPHIFY=ok|missing|error`
- Always exit 0

- [ ] **Step 1: Write failing smoke**

`2026-09-09-peer-probes-smoke.zsh` hermetic temp repo (fixtures created in `mktemp`, not a shared fixtures dir):

1. No `graphify-out/graph.json`, `ENGRIM_BIN=/nonexistent/engrim` → `GRAPHIFY=missing`, `ENGRIM=missing`
2. Create non-empty `graphify-out/graph.json` → `GRAPHIFY=ok`
3. Empty `graphify-out/graph.json` → `GRAPHIFY=missing`
4. Mock `ENGRIM_BIN` script `exit 0` → `ENGRIM=ok`
5. Mock `exit 1` → `ENGRIM=error`
6. Mock `sleep 5` with `PEER_PROBES_TIMEOUT=1` → `ENGRIM=error` (timeout)
7. Always exit 0 from helper even when peers fail

- [ ] **Step 2: Run smoke; expect fail** (helper missing)

```bash
zsh meta/superpowers/validation/2026-09-09-peer-probes-smoke.zsh
```

- [ ] **Step 3: Implement `hooks/lib/peer-probes.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# peer-probes.sh — ENGRIM + GRAPHIFY probes. Always exit 0.
# Usage: peer-probes.sh [<project-dir>]
# Stdout order (locked): ENGRIM line, then GRAPHIFY line.
set -u
DIR="${1:-.}"
ENGRIM_BIN="${ENGRIM_BIN:-engrim}"
TIMEOUT="${PEER_PROBES_TIMEOUT:-2}"

# ENGRIM — path with / must be -x; bare name uses command -v
if [[ "$ENGRIM_BIN" == */* ]]; then
  if [[ ! -x "$ENGRIM_BIN" ]]; then
    echo "ENGRIM=missing"
  elif timeout "$TIMEOUT" "$ENGRIM_BIN" context -b 200 >/dev/null 2>&1; then
    echo "ENGRIM=ok"
  else
    echo "ENGRIM=error"
  fi
elif ! command -v "$ENGRIM_BIN" >/dev/null 2>&1; then
  echo "ENGRIM=missing"
elif timeout "$TIMEOUT" "$ENGRIM_BIN" context -b 200 >/dev/null 2>&1; then
  echo "ENGRIM=ok"
else
  echo "ENGRIM=error"
fi

# GRAPHIFY
if [[ -s "$DIR/graphify-out/graph.json" ]]; then
  echo "GRAPHIFY=ok"
else
  echo "GRAPHIFY=missing"
fi
exit 0
```

- [ ] **Step 4: Re-run smoke; all pass**

- [ ] **Step 5: Commit** (only if user asked)

```bash
git add hooks/lib/peer-probes.sh meta/superpowers/validation/2026-09-09-peer-probes-smoke.zsh
git commit -m "feat: peer-probes.sh for engrim + graphify-out/graph.json"
```

---

### Task 2: `primer-validate.sh` + smoke

**Files:**
- Create: `hooks/lib/primer-validate.sh`
- Create: `meta/superpowers/validation/2026-09-09-primer-validate-smoke.zsh`

**Interfaces:**
- Consumes: path to primer file (required)
- Exit 0 if valid; non-zero if invalid
- Stderr: one reason per line, prefixed `INVALID: `

Checks:
1. Exactly one H1 matching `^# Session Primer — `
2. `##` headings ⊆ {`Boot order`,`Mid-flight`,`Confirm`,`Peers`} and all four present
3. Lines outside Confirm fence ≤80 (strip the first ` ```bash ` … closing ` ``` ` under Confirm)
4. Mid-flight bullets (`^ - ` or `^- ` under Mid-flight section) ≤5
5. Confirm counted commands ≤5
6. Banlist (avoid over-broad `git log -` substring). File matches any of:
   - `git log --oneline`
   - `git log --oneline -`
   - line matching `^git log( |$)` inside a fenced block body
   - `## Outstanding`
   - `## Current state` (old heading)
   - fenced block whose body contains `git log`

Thin/fat primer bodies are **heredocs inside the smoke** (written into `mktemp`), not checked-in fixture files.

- [ ] **Step 1: Write failing smoke** (heredoc thin/fat into temp files)

Cases:
1. Thin primer → exit 0
2. Fat primer (unknown `##` + git-log fence) → exit ≠0, stderr has `INVALID:`
3. Thin + 6th Mid-flight bullet → fail
4. Confirm fence with 6 command lines → fail
5. Unknown `## History` → fail
6. `#` comment lines in Confirm do not count
7. Confirm line `git log -1 --oneline` inside fence → fail (banlist)
8. Prose mentioning “see git history” without `git log` → still pass

- [ ] **Step 2: Run smoke; expect fail** (script missing)

- [ ] **Step 3: Implement `primer-validate.sh`**

`CONTRACT_VERSION=1`. Use awk/sed for section slicing; keep it bash-only (no python). **Collect all reasons** then exit 1 so doctor can show them.

- [ ] **Step 4: Re-run smoke; all pass**

- [ ] **Step 5: Commit** (if asked)

```bash
git add hooks/lib/primer-validate.sh meta/superpowers/validation/2026-09-09-primer-validate-smoke.zsh
git commit -m "feat: primer-validate.sh hard-template + banlist gate"
```

---

### Task 3: `primer-freshness.sh` + smoke

**Files:**
- Create: `hooks/lib/primer-freshness.sh`
- Create: `meta/superpowers/validation/2026-09-09-primer-freshness-smoke.zsh`

**Interfaces:**
- Consumes: project dir
- Stdout: `STALE=0|1|?`
- Always exit 0

Algorithm:
1. If no primer file → `STALE=?`
2. `base=$(git -C "$DIR" log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md)` — empty → `STALE=?`
3. For each unique path in `git log ${base}..HEAD --name-only --pretty=format:`:
   - Ignore if path is under `.session-continuity/` (prefix match)
   - Let `base=$(basename "$path")`; ignore if `base` matches `README*` or `CHANGELOG*` or `LICENSE*` (bash `[[ $base == README* ]]` etc.)
   - **Therefore `docs/README.md` is ignored; `src/readme_utils.sh` is not** (basename `readme_utils.sh` ≠ `README*`)
   - Any other path → `STALE=1`
4. Else `STALE=0`

- [ ] **Step 1: Failing smoke** in temp git repo:
  1. Commit thin primer only → `STALE=0`
  2. Commit `src/foo.sh` after primer → `STALE=1`
  3. Commit only `CHANGELOG.md` after primer → `STALE=0`
  4. Commit only `docs/README.md` after primer → `STALE=0` (basename ignore)
  5. Commit only `.session-continuity/LEARNINGS.md` → `STALE=0`
  6. No primer → `STALE=?`

- [ ] **Step 2: Run; expect fail**

- [ ] **Step 3: Implement helper** (basename-only ignore as above)

- [ ] **Step 4: Re-run; pass**

- [ ] **Step 5: Commit** (if asked)

---

### Task 4: Thin template + copy churn (templates only)

**Files:**
- Replace: `skills/session-continuity/templates/SESSION_PRIMER.md`
- Modify: `skills/session-continuity/templates/PROJECT_CONTEXT.md` (Maintenance)
- Modify: `skills/session-continuity/templates/CLAUDE_MD_SNIPPET.md`

- [ ] **Step 1: Write thin SESSION_PRIMER template** exactly per spec (placeholders `{{PROJECT_NAME}}`; Confirm fence with one example `true` command; Mid-flight one placeholder bullet)

- [ ] **Step 2: Assert template passes validator**

```bash
sed 's/{{PROJECT_NAME}}/Example/' skills/session-continuity/templates/SESSION_PRIMER.md > /tmp/primer-ex.md
bash hooks/lib/primer-validate.sh /tmp/primer-ex.md
```

Expected: exit 0

- [ ] **Step 3: Edit PROJECT_CONTEXT template Maintenance** — remove “regenerate git log --oneline -5 block”; replace with “on substantive commits, refresh Mid-flight + Confirm in SESSION_PRIMER.md and stage it with the commit”

- [ ] **Step 4: Edit CLAUDE_MD_SNIPPET** — boot order lists engrim + graphify as required; point backlog to `/session-continuity:backlog`; note `graphify-out/graph.json` is committed

- [ ] **Step 5: Commit** (if asked)

---

### Task 5: Wire SessionStart

**Files:**
- Modify: `hooks/session-start.sh`
- Create: `meta/superpowers/validation/2026-09-09-session-start-peers-smoke.zsh`
- Modify: `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh` (**required** — not optional; missing-primer case must expect the nudge, not silence)

**Behavior:**
1. Primer missing → print `<system-reminder>` one-liner (exact sentence below). Exit 0. (Replace today's silent exit.)
2. Primer exists → run `peer-probes.sh "$cwd"`. If either ≠ ok → hard-stop reminder (exact sentence below), then optional backlog shortlist.
3. Both ok → existing reminder, plus “read Mid-flight + Confirm”, plus if freshness `STALE=1` append ⚠️ stale line.
4. **Inject-only:** SessionStart never opens SESSION_PRIMER for write; Peers status appears only in the injected reminder text.
5. Never exit non-zero.

Exact hard-stop sentence (stable for smoke):

```
PEER SETUP INCOMPLETE: engrim and graphify-out/graph.json are required. Do not start feature work until /session-continuity:doctor is green.
```

Missing-primer sentence:

```
No .session-continuity/SESSION_PRIMER.md. Run /session-continuity:primer to init. Required peers: engrim + graphify-out/graph.json.
```

- [ ] **Step 1: Write peers smoke** (temp dir as cwd JSON payload). All greps use `grep -qi` / bash `[[ $out == *…* ]]` on lowercased copy where needed:
  1. Empty dir → stdout contains `/session-continuity:primer`
  2. Primer + missing peers → stdout contains exact substring `PEER SETUP INCOMPLETE` **and** `graphify-out/graph.json` **and** `engrim`
  3. Primer + fixture graph + mock `ENGRIM_BIN` ok → stdout contains `SESSION_PRIMER` or `Mid-flight`, and does **not** contain `PEER SETUP INCOMPLETE`

- [ ] **Step 2: Run; expect fail**

- [ ] **Step 3: Patch `session-start.sh`**

Resolve helpers next to script (`$(dirname "$0")/lib/...`). Export/pass `ENGRIM_BIN` through. Keep version-check tail. No writes to `.session-continuity/`.

- [ ] **Step 4: Update `2026-08-12-session-start-smoke.zsh` missing-primer case** to assert the nudge string (not empty stdout). Re-run new smoke + old smoke; both pass.

- [ ] **Step 5: Commit** (if asked)

---

### Task 6: Doctor command wiring

**Files:**
- Modify: `commands/doctor.md`

- [ ] **Step 1: In Step 1 gather Bash block, add** (via `require_script` gate text in the command prose, same pattern as other helpers):

```bash
echo "--- primer validate ---"
if [ -f .session-continuity/SESSION_PRIMER.md ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" .session-continuity/SESSION_PRIMER.md \
    && echo "PRIMER_VALIDATE=ok" || echo "PRIMER_VALIDATE=fail"
fi
echo "--- peer probes ---"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/peer-probes.sh" .
fi
echo "--- primer freshness ---"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-freshness.sh" .
fi
```

Command prose must `require_script` each of `primer-validate.sh`, `peer-probes.sh`, `primer-freshness.sh` at `CONTRACT_VERSION=1` before relying on their output (mirror existing `primer-status.sh` usage in `commands/primer.md`).

- [ ] **Step 2: Replace git-log block staleness interpretation** with:
  - `PRIMER_VALIDATE=fail` → row ✗ hard fail (shape)
  - `ENGRIM`/`GRAPHIFY` ≠ ok → row ✗ hard fail (peers); Notes: commit/rebuild `graphify-out/graph.json`, ensure `engrim` on PATH
  - `STALE=1` → ⚠️ only
  - Remove “compare embedded git log --oneline -5” instructions

- [ ] **Step 3: Document install order** in doctor Notes when peers fail: primer → graphify (commit `graph.json`) → engrim → re-doctor

- [ ] **Step 4: Manual dry-read of doctor.md for contradiction with banlist** (no remaining “git log block” staleness)

- [ ] **Step 5: Commit** (if asked)

---

### Task 7: Primer + end-session + pre-commit prose

**Files:**
- Modify: `commands/primer.md`
- Modify: `commands/end-session.md`
- Modify: `hooks/pre-commit-check.sh` (reminder string only)

**Primer.md changes:**
1. Init copies thin template; print install-order blurb (include: commit `graphify-out/graph.json`); after stage remind doctor stays red until peers exist.
2. Refresh: rewrite only Mid-flight + Confirm (+ Peers status lines in the file are agent-maintained on refresh/slim-migrate only — **not** by SessionStart). **Delete** “Regenerate git log --oneline -5” step. After write, `require_script` + run `primer-validate.sh`; on failure, stop and show stderr.
3. New slim-migrate mode: if validate fails with fat signals OR leftover Outstanding/BACKLOG fossils → rewrite to thin template; agent picks ≤5 Mid-flight bullets; validate before stage.
4. Check mode: status + validate + peer-probes summary (all via `require_script`).
5. Detection table: add `slim_migrate` trigger.

**end-session.md:** Step 1 = thin Mid-flight/Confirm refresh + re-run Confirm commands + `require_script` validate. Remove git-log regen.

**pre-commit-check.sh:** reminder text → refresh Mid-flight and Confirm only; do not grow the file.

- [ ] **Step 1: Patch primer.md** (remove git-log refresh; add `require_script` + validate; add slim-migrate; install order; graph.json commit note)

- [ ] **Step 2: Patch end-session.md**

- [ ] **Step 3: Patch pre-commit reminder string**

- [ ] **Step 4: Grep banlist instructions**

```bash
rg -n 'git log --oneline -5|Regenerate this block|Outstanding items' commands/primer.md commands/end-session.md hooks/pre-commit-check.sh skills/session-continuity/templates/
```

Expected: no maintenance instructions that regenerate git-log blocks (migration detection mentions of Outstanding OK).

- [ ] **Step 5: Commit** (if asked)

---

### Task 8: Dogfood + privacy copy + version bump

**Files:**
- Replace: `.session-continuity/SESSION_PRIMER.md` (slim-migrate)
- Modify: `.session-continuity/PROJECT_CONTEXT.md` Maintenance
- Create/update + **git-add**: `graphify-out/graph.json` (prefer real graphify update; minimal `{"nodes":[],"edges":[]}` only if graphify unavailable — still commit it)
- Ensure: `graphify-out/` is **not** listed in `.gitignore`
- Modify: `PRIVACY.md` — one sentence: session boot expects local engrim memory and a committed `graphify-out/graph.json`
- Modify: `README.md` — one sentence in install/doctor section: engrim + committed graphify graph are required peers
- Modify: `.claude-plugin/plugin.json` → `0.36.0`
- Modify: other version pins if present
- Modify: `CHANGELOG.md` entry for 0.36.0

- [ ] **Step 1: Slim-migrate dogfood primer** to hard template; ≤5 Mid-flight bullets reflecting real open work (Issues); Confirm commands that match (e.g. `bash hooks/lib/backlog-issues.sh --count .`, `zsh meta/superpowers/validation/2026-09-09-primer-validate-smoke.zsh`)

- [ ] **Step 2: Validate dogfood primer**

```bash
bash hooks/lib/primer-validate.sh .session-continuity/SESSION_PRIMER.md
```

- [ ] **Step 3: Produce + stage `graphify-out/graph.json`; confirm not gitignored**

```bash
# prefer: graphify update (or /graphify) from repo root
test -s graphify-out/graph.json
git check-ignore -v graphify-out/graph.json && exit 1 || true
bash hooks/lib/peer-probes.sh .
# expect ENGRIM=ok GRAPHIFY=ok
```

- [ ] **Step 4: PRIVACY.md + README peer sentences**

- [ ] **Step 5: Bump version + CHANGELOG**

- [ ] **Step 6: Run all new smokes + updated session-start smoke**

```bash
zsh meta/superpowers/validation/2026-09-09-peer-probes-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-validate-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-freshness-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-session-start-peers-smoke.zsh
zsh meta/superpowers/validation/2026-08-12-session-start-smoke.zsh
```

- [ ] **Step 7: Commit** (if asked) — include `graphify-out/graph.json` in the release commit set

---

## Spec coverage checklist

| Spec requirement | Task |
|---|---|
| `peer-probes.sh` graph.json + engrim | 1 |
| Engrim probe before hard-fail wiring | 1 before 5–6 |
| `primer-validate.sh` caps/banlist | 2 |
| Freshness without git-log block (basename ignores) | 3, 6 |
| Thin template | 4 |
| Copy churn templates | 4 |
| SessionStart missing nudge + peer hard-stop (inject-only) | 5 |
| Old session-start smoke updated | 5 |
| Doctor hard-fail shape/peers, ⚠️ stale | 6 |
| `require_script` for new helpers | 6–7 |
| Primer refresh/slim-migrate/check | 7 |
| end-session + pre-commit text | 7 |
| Committed `graphify-out/graph.json` policy | Global + 8 |
| PRIVACY + README peer disclosure | 8 |
| Dogfood + version | 8 |
| Install order documented | 6–7 |
| Confirm counting rule | 2 |
| ≤80 lines excl Confirm fence | 2, 4 |

## Self-review notes (post caveman-review)

- Smoke asserts exact `PEER SETUP INCOMPLETE` (not literal `hard-stop`).
- `graph.json` is committed, not gitignored — fresh clone can doctor-green.
- SessionStart never mutates the primer file.
- Freshness ignore is basename-only (`docs/README.md` ignored).
- Banlist avoids bare `git log -` substring false positives.
- Fixtures stay in smoke `mktemp` trees.
- Optional Commit steps honor user git rules.

---

Plan revised after caveman-review. Path: `meta/superpowers/plans/2026-09-09-primer-thin-hard-template.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with checkpoints  

Which approach?
