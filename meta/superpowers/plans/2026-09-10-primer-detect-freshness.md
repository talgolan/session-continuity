# Align primer-detect with primer-freshness (#64) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/session-continuity:primer` check mode no-op when `primer-freshness.sh` reports `STALE=0` (thin primers no longer force `LOG_DRIFT=1` / `STEPS=refresh`).

**Architecture:** `primer-detect.sh` probes sibling `primer-freshness.sh` with `$DIR`, maps `STALE=` → `--argjson log_drift 0|1`, and stops gathering `git log --oneline -5`. `primer-detect.jq` drops `log_drift()` content parse and uses the injected bit. `CODE_STAGED` and migration chain unchanged. stdout still emits `LOG_DRIFT=0|1` only (never `STALE=`).

**Tech Stack:** bash, jq, zsh hermetic smokes under `meta/superpowers/validation/`, existing `CONTRACT_VERSION=1` helpers.

**Spec:** `meta/superpowers/specs/2026-09-10-primer-detect-freshness-design.md`

## Global Constraints

- Spec decisions locked: `STALE=?` → `LOG_DRIFT=1`; keep `LOG_DRIFT` key; no dual-path embedded-log compare; soft-fail degraded freshness probe → `log_drift=1` (never `die` for freshness).
- Invoke freshness as: `bash "$SCRIPT_DIR/primer-freshness.sh" "$DIR"` (always pass `$DIR`).
- Before probe: `[[ -r ... ]]` and `grep -q '^# CONTRACT_VERSION=1$'` on `primer-freshness.sh`; either fail → `log_drift=1`, skip probe.
- Never forward raw freshness stdout / `STALE=` to detect callers.
- Document semantic flip in `primer-detect.sh` header comment.
- Amend parent design `meta/superpowers/specs/2026-09-08-primer-detect-design.md` (architecture + `LOG_DRIFT` prose).
- Plugin version: `0.36.0` → `0.36.1` (patch: detect drift source bugfix).
- Spec/plan under `meta/superpowers/`, not `docs/`.
- Do not commit unless the user asked; Commit steps are optional gates.
- Smoke fixtures stay inside each smoke’s `mktemp` tree.

## File map

| File | Role |
|---|---|
| `hooks/lib/primer-detect.sh` | Call freshness; map → `--argjson log_drift`; drop `GIT_LOG` |
| `hooks/lib/primer-detect.jq` | Drop `log_drift()`; use `$log_drift` |
| `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh` | Thin `mk_repo`; freshness-driven cases |
| `meta/superpowers/specs/2026-09-08-primer-detect-design.md` | Amend drift source prose |
| `CHANGELOG.md` / `.claude-plugin/plugin.json` | 0.36.1 notes + version |
| `meta/superpowers/specs/2026-09-10-primer-detect-freshness-design.md` | Ship with release (already written) |

---

### Task 1: Failing smokes — thin `mk_repo` + freshness cases

**Files:**
- Modify: `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`
- Test: same file

**Interfaces:**
- Consumes: current `hooks/lib/primer-detect.sh` (still log-block based — tests must fail)
- Produces: smoke cases that define the new contract for Task 2

- [ ] **Step 1: Rewrite `mk_repo` to commit a thin primer (no log block)**

Replace the `mk_repo` function body so it commits the thin primer once and does not overwrite with an embedded log. Keep the same flag signature:

```zsh
# mk_repo <dir> <split:0|1> <oi_file:0|1> <bl_file:0|1> <inline:0|1> <origin:gh|other> <staged:none|code|docs>
mk_repo() {
  local dir="$1" split=$2 oi=$3 bl=$4 inline=$5 origin=$6 staged=$7
  rm -rf "$dir"
  mkdir -p "$dir/.session-continuity"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Test
  if [[ "$origin" == "gh" ]]; then
    git -C "$dir" remote add origin https://github.com/example/repo.git
  else
    git -C "$dir" remote add origin https://example.com/example/repo.git
  fi
  : > "$dir/.session-continuity/LEARNINGS.md"
  (( split ))  && : > "$dir/.session-continuity/PROJECT_CONTEXT.md"
  : > "$dir/.session-continuity/ROADMAP.md"
  (( oi ))     && : > "$dir/.session-continuity/OUTSTANDING_ITEMS.md"
  (( bl ))     && : > "$dir/.session-continuity/BACKLOG.md"
  local heading=""
  (( inline )) && heading=$'## Outstanding items\n1. something\n\n'
  print -r -- "${heading}# Primer

## Mid-flight
- none

## Confirm
\`\`\`bash
true
\`\`\`
" > "$dir/.session-continuity/SESSION_PRIMER.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
  case "$staged" in
    code) print -r -- x > "$dir/src.js"; git -C "$dir" add src.js ;;
    docs) print -r -- x >> "$dir/.session-continuity/LEARNINGS.md"; git -C "$dir" add .session-continuity/LEARNINGS.md ;;
  esac
}
```

Update the comment above `mk_repo` to drop the log-block / self-referential-hash notes; say drift comes from `primer-freshness.sh` after the primer tip commit.

- [ ] **Step 2: Replace case 4 + add dogfood / `STALE=?` cases**

Replace the old case 4 block (stale embedded log overwrite) with:

```zsh
# --- 3b: dogfood thin primer, migration facts off, STALE=0 -> empty --------
d="$work/case3b"; mk_repo "$d" 1 0 0 0 other none
drift="$(bash "$tool" "$d" | awk -F= '/^LOG_DRIFT=/{print $2}')"
[[ "$(steps_of "$d")" == "" && "$drift" == "0" ]] \
  && ok "3b: thin+STALE=0+no migrations -> empty, LOG_DRIFT=0" \
  || bad "3b: steps='$(steps_of "$d")' drift='$drift'"

# --- 4: substantive commit after primer tip -> refresh --------------------
d="$work/case4"; mk_repo "$d" 1 0 0 0 other none
mkdir -p "$d/src"
print -r -- x > "$d/src/foo.sh"
git -C "$d" add src/foo.sh
git -C "$d" commit -qm "src after primer"
[[ "$(steps_of "$d")" == "refresh" ]] \
  && ok "4: STALE=1 after src commit -> refresh" \
  || bad "4: got '$(steps_of "$d")'"

# --- 4b: primer on disk but never committed -> STALE=? -> refresh ---------
d="$work/case4b"
rm -rf "$d"
mkdir -p "$d/.session-continuity"
git -C "$d" init -q
git -C "$d" config user.email test@example.com
git -C "$d" config user.name Test
git -C "$d" remote add origin https://example.com/example/repo.git
: > "$d/README.md"
git -C "$d" add README.md
git -C "$d" commit -qm init
# Continuity files on disk only — do NOT git add SESSION_PRIMER.md
: > "$d/.session-continuity/LEARNINGS.md"
: > "$d/.session-continuity/PROJECT_CONTEXT.md"
: > "$d/.session-continuity/ROADMAP.md"
print -r -- "# Primer

## Mid-flight
- none

## Confirm
\`\`\`bash
true
\`\`\`
" > "$d/.session-continuity/SESSION_PRIMER.md"
[[ "$(steps_of "$d")" == "refresh" ]] \
  && ok "4b: uncommitted primer -> STALE=? -> refresh" \
  || bad "4b: got '$(steps_of "$d")'"
```

After case 15 (jq absent), append case 16 (soft-fail freshness — runs against post-Task-2 detect; red/irrelevant until then is fine if Task 1 lands before Task 2):

```zsh
# --- 16: missing primer-freshness.sh -> soft-fail LOG_DRIFT=1, still STEPS= --
softlib="$work/softlib"; mkdir -p "$softlib"
cp "$lib/primer-detect.sh" "$lib/primer-detect.jq" "$softlib/"
# deliberately omit primer-freshness.sh
d="$work/case16"; mk_repo "$d" 1 0 0 0 other none
out="$(bash "$softlib/primer-detect.sh" "$d" 2>&1)"; rc=$?
drift="$(printf '%s\n' "$out" | awk -F= '/^LOG_DRIFT=/{print $2}')"
steps="$(printf '%s\n' "$out" | awk -F= '/^STEPS=/{print $2}')"
[[ "$rc" -eq 0 && "$drift" == "1" && "$steps" == "refresh" ]] \
  && ok "16: missing freshness -> soft LOG_DRIFT=1, STEPS=refresh, exit 0" \
  || bad "16: rc=$rc drift='$drift' steps='$steps' out='$out'"
```

Keep cases 1–3, 5–15 as-is (they call the new `mk_repo`). Case 3 still uses `bl=1` + `other` (fossil empty). Case 3b is the dogfood invariant (`bl=0`).

- [ ] **Step 3: Run smoke — expect failures on clean/empty / migration-only paths**

Run: `zsh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`

Expected: FAIL until Task 2. Specifically red (do **not** “fix” by reverting `mk_repo`):

- Empty/`LOG_DRIFT=0` expected: `3`, `3b`, `5b`, `10` → get `refresh` (or trailing `,refresh`) because thin primer still looks like log-drift
- Migration-only expected: `2`, `6`, `8`, `9`, `11` → get trailing `,refresh`
- Load-bearing red: `3b` (`STEPS=` + `LOG_DRIFT=0`)
- May pass for the wrong reason pre-Task-2: `4`, `4b` (missing log block ⇒ old `LOG_DRIFT=1`)
- Case `16` may pass pre-Task-2 for the wrong reason (old log-block drift) once softlib still forces `LOG_DRIFT=1`; it becomes a real soft-fail check only after Task 2

- [ ] **Step 4: Commit (optional — only if user asked)**

```bash
git add meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
git commit -m "$(cat <<'EOF'
test: primer-detect smokes expect freshness-mapped drift (#64)

EOF
)"
```

---

### Task 2: Wire detect.sh + detect.jq to freshness

**Files:**
- Modify: `hooks/lib/primer-detect.sh`
- Modify: `hooks/lib/primer-detect.jq`
- Test: `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`

**Interfaces:**
- Consumes: `hooks/lib/primer-freshness.sh` (`STALE=0|1|?`, always exit 0 when healthy)
- Produces: same detect KEY= contract; `LOG_DRIFT` = freshness map; `STEPS` refresh only when mapped drift or `CODE_STAGED`

- [ ] **Step 1: Update `primer-detect.jq` — drop `log_drift()`, take `$log_drift`**

Replace the log-related defs and binding. Full filter after edit:

```jq
# CONTRACT_VERSION=1
# hooks/lib/primer-detect.jq — /session-continuity:primer dispatch decision.
# Invoked via primer-detect.sh; see that file for the CLI contract and
# meta/superpowers/specs/2026-09-08-primer-detect-design.md (amended by
# 2026-09-10-primer-detect-freshness-design.md) for the state machine.
#
# All decision logic lives here, not in the .sh wrapper — no I/O, so this
# is directly fixture-testable with synthetic strings (see the smoke test).
# LOG_DRIFT is injected by the .sh wrapper from primer-freshness.sh
# (not computed from an embedded git-log block).
# The trigger chain is evaluated by threading each trigger's effect
# forward into the fact the next trigger reads (PROJ_OI, PROJ_BL below),
# not by writing out "OR about to become true" disjunctions per trigger —
# see the spec's "Why threading, not disjunctions" note for why the naive
# approach doesn't compose past one chained link.

def has_inline_outstanding:
  test("(?m)^## Outstanding items");

def is_allowlisted:
  (startswith("docs/") or startswith(".session-continuity/")) as $dir_ok
  | (split("/") | .[-1]) as $base
  | ($base | test("^(README|CHANGELOG|LICENSE)")) as $name_ok
  | ($dir_ok or $name_ok);

def code_staged($files):
  ($files | split("\n") | map(select(length > 0))) as $paths
  | ($paths | any(is_allowlisted | not));

def github_origin($origin):
  $origin | test("github\\.com");

($primer_content | has_inline_outstanding) as $INLINE
| ($log_drift) as $DRIFT
| (code_staged($staged_files)) as $STAGED
| (github_origin($origin_url)) as $GH

| ($project_context_exists == 0) as $DO_SPLIT
| ($INLINE and ($outstanding_items_exists == 0)) as $DO_OSPLIT
| (if $DO_OSPLIT then 1 else $outstanding_items_exists end) as $PROJ_OI
| ($PROJ_OI == 1 and $backlog_exists == 0) as $DO_BRENAME
| (if $DO_BRENAME then 1 else $backlog_exists end) as $PROJ_BL
| ($PROJ_BL == 1 and $GH) as $DO_B2I
| ($DRIFT == 1 or $STAGED) as $DO_REFRESH

| ([]
   | if $DO_SPLIT then . + ["split"] else . end
   | if $DO_OSPLIT then . + ["outstanding_split"] else . end
   | if $DO_BRENAME then . + ["backlog_rename"] else . end
   | if $DO_B2I then . + ["backlog_to_issues"] else . end
   | if $DO_REFRESH then . + ["refresh"] else . end
  ) as $triggered_steps
| (if $primer_exists == 0 then ["init"] else $triggered_steps end) as $steps

| ("PRIMER_EXISTS=" + ($primer_exists|tostring)),
  ("LEARNINGS_EXISTS=" + ($learnings_exists|tostring)),
  ("PROJECT_CONTEXT_EXISTS=" + ($project_context_exists|tostring)),
  ("OUTSTANDING_ITEMS_EXISTS=" + ($outstanding_items_exists|tostring)),
  ("PRIMER_HAS_INLINE_OUTSTANDING=" + (if $INLINE then "1" else "0" end)),
  ("BACKLOG_EXISTS=" + ($backlog_exists|tostring)),
  ("ROADMAP_EXISTS=" + ($roadmap_exists|tostring)),
  ("GITHUB_ORIGIN=" + (if $GH then "1" else "0" end)),
  ("LOG_DRIFT=" + ($DRIFT|tostring)),
  ("CODE_STAGED=" + (if $STAGED then "1" else "0" end)),
  ("STEPS=" + ($steps | join(",")))
```

- [ ] **Step 2: Update `primer-detect.sh` — freshness probe + header**

In the header block (after the KEY= list), add that `LOG_DRIFT` is mapped from `primer-freshness.sh` (`STALE=0`→0; `STALE=1|?` / degraded probe→1), not from an embedded git-log compare. Point at both design specs.

Replace the gather + jq invocation section (from `ORIGIN_URL=` through the jq call) with:

```bash
ORIGIN_URL="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
STAGED_FILES="$(git -C "$DIR" diff --cached --name-only 2>/dev/null || true)"

# LOG_DRIFT from primer-freshness.sh (never forward STALE= to callers).
LOG_DRIFT=1
FRESHNESS_SH="$SCRIPT_DIR/primer-freshness.sh"
if [[ -r "$FRESHNESS_SH" ]] && grep -q '^# CONTRACT_VERSION=1$' "$FRESHNESS_SH"; then
  FRESH_OUT="$(bash "$FRESHNESS_SH" "$DIR" 2>/dev/null)"
  FRESH_RC=$?
  if [[ "$FRESH_RC" -eq 0 ]]; then
    FRESH_STALE="$(printf '%s\n' "$FRESH_OUT" | awk -F= '/^STALE=/{print $2; exit}')"
    case "$FRESH_STALE" in
      0) LOG_DRIFT=0 ;;
      1|\?) LOG_DRIFT=1 ;;
      *) LOG_DRIFT=1 ;;
    esac
  fi
  # nonzero exit or missing STALE= → leave LOG_DRIFT=1
fi

ERRFILE="$(mktemp)"
RESULT="$(
  jq -r -n \
    --argjson primer_exists "$PRIMER_EXISTS" \
    --argjson learnings_exists "$LEARNINGS_EXISTS" \
    --argjson project_context_exists "$PROJECT_CONTEXT_EXISTS" \
    --argjson outstanding_items_exists "$OUTSTANDING_ITEMS_EXISTS" \
    --argjson backlog_exists "$BACKLOG_EXISTS" \
    --argjson roadmap_exists "$ROADMAP_EXISTS" \
    --argjson log_drift "$LOG_DRIFT" \
    --arg origin_url "$ORIGIN_URL" \
    --arg staged_files "$STAGED_FILES" \
    --arg primer_content "$PRIMER_CONTENT" \
    -f "$JQ_FILTER" 2>"$ERRFILE"
)"
```

Remove `GIT_LOG=...` and `--arg git_log` entirely.

- [ ] **Step 3: Run smoke — all pass**

Run: `zsh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`

Expected: `Result: 19 passed, 0 failed` (old 16 − replaced case 4 + `3b` + `4b` + `16`).

- [ ] **Step 4: Dogfood on this repo**

```bash
git diff --cached --name-only   # note: allowlisted .session-continuity staging is OK
bash hooks/lib/primer-freshness.sh .
bash hooks/lib/primer-detect.sh .
```

Expected when freshness is `STALE=0` and no non-allowlisted paths are staged: `LOG_DRIFT=0` and `STEPS=` does not contain `refresh` (migrations may still appear if fossils present — this repo should be migration-clean).

- [ ] **Step 5: Commit (optional — only if user asked)**

```bash
git add hooks/lib/primer-detect.sh hooks/lib/primer-detect.jq
git commit -m "$(cat <<'EOF'
fix: map primer-detect LOG_DRIFT from primer-freshness (#64)

EOF
)"
```

---

### Task 3: Amend parent design + changelog + version

**Files:**
- Modify: `meta/superpowers/specs/2026-09-08-primer-detect-design.md` (Architecture + `DO_REFRESH` / `LOG_DRIFT` prose)
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json` only (`0.36.0` → `0.36.1`) — no root `plugin.json`
- Add (already written, stage if untracked): `meta/superpowers/specs/2026-09-10-primer-detect-freshness-design.md`
- Optional stage: `meta/superpowers/plans/2026-09-10-primer-detect-freshness.md`
- Test: re-run detect smoke; skim changelog against shipped files

**Interfaces:**
- Consumes: Task 2 behavior (freshness-mapped `LOG_DRIFT`)
- Produces: docs/version aligned with code

- [ ] **Step 1: Amend Architecture diagram in the 2026-09-08 detect design**

Replace the Architecture code block so I/O lists `primer-freshness.sh "$DIR"` (not `git log --oneline -5`), and jq lists “use injected `log_drift` from freshness map” (not extract/diff embedded git-log).

Update the sentence under `DO_REFRESH` that says splitting doesn’t touch the git-log block — say it doesn’t touch freshness tip / staged set instead.

Add a one-line pointer at the top Context (or after Architecture): drift source amended by `meta/superpowers/specs/2026-09-10-primer-detect-freshness-design.md` (#64).

- [ ] **Step 2: Bump version + CHANGELOG**

In `.claude-plugin/plugin.json` only, set `"version": "0.36.0"` → `"0.36.1"`. Do not create a root `plugin.json`. No README version string to bump.

`CHANGELOG.md` entry under `## [0.36.1]`:

```markdown
## [0.36.1] — 2026-09-10

### Fixed
- **`primer-detect` refresh trigger now follows `primer-freshness.sh`.** Thin
  hard-template primers (no embedded `git log` block) no longer always look
  like `LOG_DRIFT=1`. `LOG_DRIFT` maps from `STALE=` (`0`→0; `1`/`?`/degraded
  probe→1). Check mode can no-op when freshness is clean. (#64)
```

- [ ] **Step 3: Re-run smokes**

```bash
zsh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
zsh meta/superpowers/validation/2026-09-09-primer-freshness-smoke.zsh
```

Expected: detect smoke `19 passed, 0 failed`; freshness smoke `0 failed`.

- [ ] **Step 4: Commit (optional — only if user asked)**

```bash
git add meta/superpowers/specs/2026-09-08-primer-detect-design.md \
  meta/superpowers/specs/2026-09-10-primer-detect-freshness-design.md \
  meta/superpowers/plans/2026-09-10-primer-detect-freshness.md \
  CHANGELOG.md .claude-plugin/plugin.json
git commit -m "$(cat <<'EOF'
docs: amend detect design + 0.36.1 for freshness-mapped drift (#64)

EOF
)"
```

---

### Task 4: Close-out checklist

**Files:**
- Modify: `.session-continuity/SESSION_PRIMER.md` Mid-flight (drop #64 when closing)
- Test: Confirm block commands from the primer

- [ ] **Step 1: Verify success criteria from the #64 spec**

| # | Check | Command / observation |
|---|---|---|
| 1 | Thin dogfood, `STALE=0`, clean non-allowlisted index → no `refresh` | `bash hooks/lib/primer-freshness.sh .` + `bash hooks/lib/primer-detect.sh .` |
| 2 | `STALE=1` / `?` → `LOG_DRIFT=1` → `refresh` | covered by smoke 4 / 4b |
| 3 | Non-allowlisted staged still refreshes at `STALE=0` | smoke case 5 |
| 4 | Migration-order smokes pass | smoke 7 / 11 |
| 5 | freshness helper untouched | `zsh meta/superpowers/validation/2026-09-09-primer-freshness-smoke.zsh` |

- [ ] **Step 2: Refresh Mid-flight** — remove #64; leave other Mid-flight items. Stage primer with the shipping commit when the user asks to commit (do not commit primer alone).

- [ ] **Step 3: Close GitHub issue** (after code is on the branch the user will ship)

```bash
gh issue close 64 --reason completed
```

Only after the implementation is committed/merged per user instruction — do not close on uncommitted work.

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|---|---|
| Bash calls freshness with `$DIR` | Task 2 |
| Map `STALE=0/1/?` + degraded → `LOG_DRIFT` | Task 2 |
| No `STALE=` on detect stdout | Task 2 |
| Drop embedded-log compare / `git log -5` gather | Task 2 |
| Soft-fail missing/wrong-version freshness | Task 2 |
| Header documents semantic flip | Task 2 |
| Smoke: retire log overwrite; thin mk_repo; 3 freshness cases + soft-fail | Task 1 |
| Soft-fail missing freshness (exit 0, `LOG_DRIFT=1`) | Task 1 case 16 + Task 2 rc check |
| Nonzero freshness exit → `LOG_DRIFT=1` | Task 2 |
| Amend 2026-09-08 detect design | Task 3 |
| Ship #64 design (+ plan) with version bump | Task 3 |
| Success criteria / dogfood | Task 2 Step 4 + Task 4 |
| `CODE_STAGED` unchanged | Task 2 (jq keeps `code_staged`) |
| Out of scope: freshness policy / rename key / Step 4 prose | not tasked |

No TBD/placeholder steps. Commit steps optional per repo convention.
