# Determinism Phase 6, sub-project A — `primer-detect.sh`/`.jq` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `commands/primer.md` Step 1's hand-evaluated 4-state-plus-3-trigger dispatch logic (~15 lines of nested-conditional prose, including a sequencing rule easy to misapply) with one script, `hooks/lib/primer-detect.sh`, that gathers the same raw facts already gathered today and prints a definitive, ordered `STEPS=` list telling the model exactly which of Steps 2/3/3b/3c/3d/4/5 to run.

**Architecture:** `primer-detect.sh` (bash, I/O only — file-existence checks, three git commands, one file read) pipes everything into `primer-detect.jq` (pure decision function, no I/O, fixture-testable with synthetic strings). The `.jq` filter evaluates each migration trigger by **threading each trigger's effect forward** into the fact the next trigger reads (a chained `outstanding_split → backlog_rename → backlog_to_issues` dependency), not by writing out "OR about to become true" disjunctions per trigger — that approach was tried, found not to compose past one link, and replaced during this plan's own verification pass (see Task 1's notes). `commands/primer.md` Step 1 shrinks to one script call plus a lookup table from `STEPS` names to step numbers.

**Tech Stack:** Bash, `jq` (already a hard dependency across this plugin), zsh (smoke tests only).

**Spec:** `meta/superpowers/specs/2026-09-08-primer-detect-design.md`. That spec was corrected twice during writing (caveman-review, then this plan's own implementation-first verification) — both fixes are already folded into the spec text; this plan implements the spec as it now reads, no further corrections needed.

## Global Constraints

- `primer-detect.sh` carries a `# CONTRACT_VERSION=1` header (both the `.sh` and the `.jq`) and is called through `require_script` from `commands/primer.md`, exactly like `primer-status.sh` already is in Step 5.
- **No conservative default dispatch on failure.** Unlike `token-overlap.sh` (empty output safely degrades to "zero matches"), `primer-detect.sh` prints no `STEPS=` line at all on any operational failure and exits nonzero — some `STEPS` values gate destructive migrations (`git mv`/`git rm`), so guessing wrong is worse than stopping. `commands/primer.md` must treat a missing `STEPS=` line as a hard stop.
- **Never invent a value.** Every fact the script cannot resolve reflects reality (a missing file is `0`, not a guess) — this plan changes *how* the dispatch decision is computed, never *what* Steps 2/3/3b/3c/3d/4/5 themselves do.
- All decision logic lives in `primer-detect.jq`, none in `primer-detect.sh` — the `.sh` wrapper's only job is gathering raw facts and invoking the filter, mirroring `token-overlap.sh`/`candidate-extract.sh`.
- Do not touch Steps 2, 3, 3b, 3c, 3d, 4, or 5's own internal logic — this plan scripts *whether* they run, not *what* they do once entered. (Their own mechanics are sub-projects B/C/D per the spec's Context section — out of scope here.)
- Do not touch `candidate-extract.jq`'s `overlap()` (issue #40, already fixed and closed in a prior session) or `hooks/lib/token-overlap.sh`/`.jq` (issue #42, already shipped) — unrelated to this plan.

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/lib/primer-detect.jq` (new) | Pure decision function: takes the raw facts as string/int arguments, runs the state machine, prints `KEY=value` lines ending in `STEPS=`. No I/O. |
| `hooks/lib/primer-detect.sh` (new) | Thin I/O wrapper: file-existence checks, `git remote get-url origin`, `git log --oneline -5`, `git diff --cached --name-only`, reads the primer file if present, invokes the filter. |
| `commands/primer.md` (modified) | Step 1 collapses to one script call plus a `STEPS`-name-to-step-number table. Steps 3b/3c/3d's opening "Runs whenever ..." sentences are simplified to "Runs when `<name>` appears in Step 1's `STEPS`" — restating the old boolean conditions in prose would now be actively misleading, since the corrected threaded logic lives only in the `.jq` filter. |
| `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh` (new) | Smoke test: 16 assertions total (real scratch git repos, no mocking) — the 11 state-machine fixtures, a `5b` docs-allowlist variant, and 4 operational-failure cases. |
| `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (modified) | Phase 6 entry notes sub-project A shipped, points to this plan; sub-projects B–E remain listed as pending. |
| `CHANGELOG.md` (modified) | New version entry. |
| `.claude-plugin/plugin.json` (modified) | Version bump. |

---

### Task 1: `hooks/lib/primer-detect.jq` + `hooks/lib/primer-detect.sh`

**Files:**
- Create: `hooks/lib/primer-detect.jq`
- Create: `hooks/lib/primer-detect.sh`
- Test: `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`

**Interfaces:**
- Produces: `bash primer-detect.sh [<project-dir>]` (default `.`). Prints `KEY=value` lines to stdout, ending in `STEPS=<comma,separated,ordered,list>` (possibly empty). Exits 0 on success. On operational failure (jq missing, filter missing/wrong version, `<project-dir>` not a git repo), prints one diagnostic line to stderr and exits 1 with **no** `STEPS=` line anywhere in stdout.
- Consumes: `jq` (hard dependency), `git`.

**A note on the log-drift fixture design (read before writing tests):** `primer-detect.sh` reads `SESSION_PRIMER.md` from the *working tree*, not from a git commit — so a fixture that wants "recorded log block matches actual `git log`" never needs the primer file's own content to be committed at all. Write the primer file to disk with whatever recorded block you want *after* whatever commits the fixture needs, and leave it uncommitted. There is no way to make a *committed* primer file accurately quote the `git log` of the very commit that adds it (the commit's own hash isn't known until after committing) — this is an inherent property of any git-log-embedding scheme, not a bug this plan introduces or needs to solve, and the real command's Step 4 (`refresh mode`) only ever *stages* the primer, never commits it itself, for exactly this reason.

**jq/Oniguruma flag note (also read before writing tests):** jq's regex flag letters don't match PCRE convention. `"s"` means *single-line anchor mode* (`^`/`$` match string start/end only); `"m"` is the flag that makes `.` match newlines. A regex built assuming PCRE's `s` (dotall) will silently fail to match multi-line content and must use `"m"` instead.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# primer-detect.sh/.jq smoke test. Hermetic: one scratch git repo per case,
# built fresh via mk_repo. No mocking needed -- every fact is a real file
# or a real git command against a real (throwaway) repository.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
tool="$lib/primer-detect.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# mk_repo <dir> <split:0|1> <oi_file:0|1> <bl_file:0|1> <inline:0|1> <origin:gh|other> <staged:none|code|docs>
# Builds a fresh scratch repo with .session-continuity/ populated per the
# flags, commits everything, then writes SESSION_PRIMER.md's log block to
# exactly match the post-commit `git log --oneline -5` (never re-committed
# afterward -- see this plan's Task 1 notes on why that avoids a
# self-referential-hash problem). Callers that want DRIFT instead
# overwrite the block themselves after calling mk_repo.
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

placeholder body, overwritten below with the real log block
" > "$dir/.session-continuity/SESSION_PRIMER.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
  local log
  log="$(git -C "$dir" log --oneline -5)"
  print -r -- "${heading}# Primer

**Current \`git log --oneline -5\` (primary branch):**

\`\`\`
$log
\`\`\`
" > "$dir/.session-continuity/SESSION_PRIMER.md"
  case "$staged" in
    code) print -r -- x > "$dir/src.js"; git -C "$dir" add src.js ;;
    docs) print -r -- x >> "$dir/.session-continuity/LEARNINGS.md"; git -C "$dir" add .session-continuity/LEARNINGS.md ;;
  esac
}

steps_of() { bash "$tool" "$1" | awk -F= '/^STEPS=/{print $2}'; }

# --- 1: fresh install (no .session-continuity/ at all) -> init -------------
d="$work/case1"; mkdir -p "$d"
git -C "$d" init -q; git -C "$d" config user.email t@t.com; git -C "$d" config user.name T
: > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm init
git -C "$d" remote add origin https://github.com/example/repo.git
[[ "$(steps_of "$d")" == "init" ]] && ok "1: fresh install -> init" || bad "1: got '$(steps_of "$d")'"

# --- 2: existing unsplit primer, otherwise current -> split -----------------
d="$work/case2"; mk_repo "$d" 0 0 1 0 other none
[[ "$(steps_of "$d")" == "split" ]] && ok "2: unsplit only -> split" || bad "2: got '$(steps_of "$d")'"

# --- 3: split + current + clean -> empty ------------------------------------
d="$work/case3"; mk_repo "$d" 1 0 1 0 other none
[[ "$(steps_of "$d")" == "" ]] && ok "3: split+current+clean -> empty" || bad "3: got '$(steps_of "$d")'"

# --- 4: recorded log block differs from actual -> refresh -------------------
d="$work/case4"; mk_repo "$d" 1 0 1 0 other none
print -r -- "# Primer

**Current \`git log --oneline -5\` (primary branch):**

\`\`\`
0000000 stale placeholder
\`\`\`
" > "$d/.session-continuity/SESSION_PRIMER.md"
[[ "$(steps_of "$d")" == "refresh" ]] && ok "4: log drift -> refresh" || bad "4: got '$(steps_of "$d")'"

# --- 5: non-allowlisted file staged -> refresh -------------------------------
d="$work/case5"; mk_repo "$d" 1 0 1 0 other code
[[ "$(steps_of "$d")" == "refresh" ]] && ok "5: non-allowlisted staged -> refresh" || bad "5: got '$(steps_of "$d")'"

# --- docs-only staged -> NOT refresh (allowlisted) --------------------------
d="$work/case5b"; mk_repo "$d" 1 0 1 0 other docs
[[ "$(steps_of "$d")" == "" ]] && ok "5b: docs-only staged -> no refresh (allowlisted)" || bad "5b: got '$(steps_of "$d")'"

# --- 6: inline heading, no OUTSTANDING_ITEMS.md -> outstanding_split -------
d="$work/case6"; mk_repo "$d" 1 0 1 1 other none
[[ "$(steps_of "$d")" == "outstanding_split" ]] && ok "6: inline+no file -> outstanding_split" || bad "6: got '$(steps_of "$d")'"

# --- 7: both unsplit AND inline -> split,outstanding_split (order) ---------
d="$work/case7"; mk_repo "$d" 0 0 1 1 other none
[[ "$(steps_of "$d")" == "split,outstanding_split" ]] && ok "7: unsplit+inline -> split,outstanding_split in order" || bad "7: got '$(steps_of "$d")'"

# --- 8: OUTSTANDING_ITEMS.md exists, no BACKLOG.md -> backlog_rename -------
d="$work/case8"; mk_repo "$d" 1 1 0 0 other none
[[ "$(steps_of "$d")" == "backlog_rename" ]] && ok "8: outstanding file, no backlog -> backlog_rename" || bad "8: got '$(steps_of "$d")'"

# --- 9: BACKLOG.md exists, github origin -> backlog_to_issues --------------
d="$work/case9"; mk_repo "$d" 1 0 1 0 gh none
[[ "$(steps_of "$d")" == "backlog_to_issues" ]] && ok "9: backlog exists, github -> backlog_to_issues" || bad "9: got '$(steps_of "$d")'"

# --- 10: BACKLOG.md exists, non-github origin -> empty (fossil, no GH call) -
d="$work/case10"; mk_repo "$d" 1 0 1 0 other none
[[ "$(steps_of "$d")" == "" ]] && ok "10: backlog exists, non-github -> empty (fossil)" || bad "10: got '$(steps_of "$d")'"

# --- 11: full worst-case stack, exact order ---------------------------------
d="$work/case11"; mk_repo "$d" 0 0 0 1 gh none
[[ "$(steps_of "$d")" == "split,outstanding_split,backlog_rename,backlog_to_issues" ]] \
  && ok "11: full stack fires in dependency order" || bad "11: got '$(steps_of "$d")'"

# --- 12: operational failure -- missing filter, no STEPS line at all -------
badlib="$work/badlib"; mkdir -p "$badlib"
cp "$lib/primer-detect.sh" "$badlib/"
out="$(bash "$badlib/primer-detect.sh" "$work/case3" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "12: missing filter -> nonzero exit, no STEPS= line" || bad "12: rc=$rc out='$out'"

# --- 13: operational failure -- not a git repo ------------------------------
notgit="$work/notgit"; mkdir -p "$notgit"
out="$(bash "$tool" "$notgit" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "13: not a git repo -> nonzero exit, no STEPS= line" || bad "13: rc=$rc out='$out'"

# --- 14: operational failure -- wrong CONTRACT_VERSION -----------------------
wronglib="$work/wronglib"; mkdir -p "$wronglib"
cp "$lib/primer-detect.sh" "$wronglib/"
sed 's/CONTRACT_VERSION=1/CONTRACT_VERSION=99/' "$lib/primer-detect.jq" > "$wronglib/primer-detect.jq"
out="$(bash "$wronglib/primer-detect.sh" "$work/case3" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "14: wrong CONTRACT_VERSION -> nonzero exit, no STEPS= line" || bad "14: rc=$rc out='$out'"

# --- 15: operational failure -- jq absent from PATH -------------------------
nojq="$work/nojq"; mkdir -p "$nojq/bin"
for b in bash git awk grep sed head cat mktemp dirname; do
  p="$(command -v "$b")"; [[ -n "$p" ]] && ln -sf "$p" "$nojq/bin/$b"
done
out="$(PATH="$nojq/bin" bash "$tool" "$work/case3" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out" != *"STEPS="* ]] \
  && ok "15: jq absent from PATH -> nonzero exit, no STEPS= line" || bad "15: rc=$rc out='$out'"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
zsh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
```

Expected: FAIL on every assertion — `hooks/lib/primer-detect.sh` does not exist yet.

- [ ] **Step 3: Write `hooks/lib/primer-detect.jq`**

```jq
# CONTRACT_VERSION=1
# hooks/lib/primer-detect.jq — /session-continuity:primer dispatch decision.
# Invoked via primer-detect.sh; see that file for the CLI contract and
# meta/superpowers/specs/2026-09-08-primer-detect-design.md for the state
# machine this ports.
#
# All decision logic lives here, not in the .sh wrapper — no I/O, so this
# is directly fixture-testable with synthetic strings (see the smoke test).
# The trigger chain is evaluated by threading each trigger's effect
# forward into the fact the next trigger reads (PROJ_OI, PROJ_BL below),
# not by writing out "OR about to become true" disjunctions per trigger —
# see the spec's "Why threading, not disjunctions" note for why the naive
# approach doesn't compose past one chained link.

def has_inline_outstanding:
  test("(?m)^## Outstanding items");

# jq/Oniguruma's "m" flag makes "." match newlines (the "s" flag means
# something else here -- single-line anchor mode -- unlike PCRE, where
# the letters are swapped). Without "m", .*? can never cross the log
# block's internal newlines and this always fails to match.
def log_drift($primer_exists; $actual_log; $primer_content):
  if $primer_exists == 0 then 0
  else
    (($primer_content | capture("Current `git log --oneline -5`[^`]*```\\n(?<block>.*?)```"; "m")) // null | .block) as $recorded
    | if $recorded == null then 1
      elif ($recorded | gsub("^\\s+|\\s+$";"")) == ($actual_log | gsub("^\\s+|\\s+$";"")) then 0
      else 1
      end
  end;

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
| (log_drift($primer_exists; $git_log; $primer_content)) as $DRIFT
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

- [ ] **Step 4: Write `hooks/lib/primer-detect.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/primer-detect.sh — dispatch decision for /session-continuity:primer.
# See meta/superpowers/specs/2026-09-08-primer-detect-design.md for the full
# state machine this ports (unchanged behavior, just executable instead of
# hand-evaluated per invocation) and
# meta/superpowers/plans/2026-09-08-primer-detect.md for the implementation
# plan.
#
# Usage: primer-detect.sh [<project-dir>]   (default: .)
# Prints KEY=value lines to stdout on success, ending in
# STEPS=<comma,separated,ordered,list> (possibly empty — empty means check
# mode, primer is current and no migration triggers fired):
#   PRIMER_EXISTS=0|1              LEARNINGS_EXISTS=0|1
#   PROJECT_CONTEXT_EXISTS=0|1     OUTSTANDING_ITEMS_EXISTS=0|1
#   PRIMER_HAS_INLINE_OUTSTANDING=0|1   BACKLOG_EXISTS=0|1
#   ROADMAP_EXISTS=0|1             GITHUB_ORIGIN=0|1
#   LOG_DRIFT=0|1                  CODE_STAGED=0|1
#   STEPS=<split,outstanding_split,backlog_rename,backlog_to_issues,refresh,init>
#
# Operational failure (jq missing, primer-detect.jq missing or from a
# different CONTRACT_VERSION, <project-dir> not inside a git repository)
# prints one diagnostic line to stderr and exits 1 with NO STEPS= line on
# stdout at all — no conservative default dispatch. Some STEPS values gate
# destructive migrations (git mv/git rm in Steps 3c/3d), so guessing wrong
# on failure is worse than stopping; the caller must treat a missing
# STEPS= line as a hard stop, not degrade to any default step list.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="$SCRIPT_DIR/primer-detect.jq"
DIR="${1:-.}"

die() {  # <message>
  printf 'primer-detect.sh: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 \
  || die "jq is not installed, so the primer dispatch cannot be computed."
[[ -r "$JQ_FILTER" ]] \
  || die "primer-detect.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=1$' "$JQ_FILTER" \
  || die "primer-detect.jq is from a different plugin version — run \`/session-continuity:update\`."
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$DIR is not inside a git repository."

file_flag() {  # <path relative to $DIR> -> 1|0
  [[ -f "$DIR/$1" ]] && echo 1 || echo 0
}

PRIMER_EXISTS="$(file_flag .session-continuity/SESSION_PRIMER.md)"
LEARNINGS_EXISTS="$(file_flag .session-continuity/LEARNINGS.md)"
PROJECT_CONTEXT_EXISTS="$(file_flag .session-continuity/PROJECT_CONTEXT.md)"
OUTSTANDING_ITEMS_EXISTS="$(file_flag .session-continuity/OUTSTANDING_ITEMS.md)"
BACKLOG_EXISTS="$(file_flag .session-continuity/BACKLOG.md)"
ROADMAP_EXISTS="$(file_flag .session-continuity/ROADMAP.md)"

PRIMER_CONTENT=""
[[ "$PRIMER_EXISTS" == "1" ]] && PRIMER_CONTENT="$(cat "$DIR/.session-continuity/SESSION_PRIMER.md")"

ORIGIN_URL="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
GIT_LOG="$(git -C "$DIR" log --oneline -5 2>/dev/null || true)"
STAGED_FILES="$(git -C "$DIR" diff --cached --name-only 2>/dev/null || true)"

ERRFILE="$(mktemp)"
RESULT="$(
  jq -r -n \
    --argjson primer_exists "$PRIMER_EXISTS" \
    --argjson learnings_exists "$LEARNINGS_EXISTS" \
    --argjson project_context_exists "$PROJECT_CONTEXT_EXISTS" \
    --argjson outstanding_items_exists "$OUTSTANDING_ITEMS_EXISTS" \
    --argjson backlog_exists "$BACKLOG_EXISTS" \
    --argjson roadmap_exists "$ROADMAP_EXISTS" \
    --arg origin_url "$ORIGIN_URL" \
    --arg git_log "$GIT_LOG" \
    --arg staged_files "$STAGED_FILES" \
    --arg primer_content "$PRIMER_CONTENT" \
    -f "$JQ_FILTER" 2>"$ERRFILE"
)"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  die "the detect filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
```

```bash
chmod +x hooks/lib/primer-detect.sh
```

- [ ] **Step 5: Run the smoke test to verify all assertions pass**

```bash
zsh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
```

Expected: `Result: 16 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/primer-detect.jq hooks/lib/primer-detect.sh meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh
git commit -m "feat: add primer-detect.sh/.jq, scripting /session-continuity:primer's dispatch decision"
```

---

### Task 2: `commands/primer.md` — call the script

**Files:**
- Modify: `commands/primer.md` (Step 1, currently lines 11-64; Steps 3b/3c/3d's opening sentences)

**Interfaces:**
- Consumes: `hooks/lib/primer-detect.sh` (Task 1), resolved via `CLAUDE_PLUGIN_ROOT` and `require_script`, exactly like `primer-status.sh` already is in Step 5.

- [ ] **Step 1: Replace Step 1 in full**

Using the Edit tool, replace this exact block (currently `commands/primer.md` lines 11-64, from `## Step 1 — Detect state` through the line ending `...run Step 3d (markdown backlog → GitHub Issues) after 3c.`):

````markdown
## Step 1 — Detect state

Gather the raw data for every check below in **one Bash call**, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
[ -f .session-continuity/SESSION_PRIMER.md ] && echo "PRIMER_EXISTS=1" || echo "PRIMER_EXISTS=0"
[ -f .session-continuity/LEARNINGS.md ] && echo "LEARNINGS_EXISTS=1" || echo "LEARNINGS_EXISTS=0"
[ -f .session-continuity/PROJECT_CONTEXT.md ] && echo "PROJECT_CONTEXT_EXISTS=1" || echo "PROJECT_CONTEXT_EXISTS=0"
[ -f .session-continuity/OUTSTANDING_ITEMS.md ] && echo "OUTSTANDING_ITEMS_EXISTS=1" || echo "OUTSTANDING_ITEMS_EXISTS=0"
grep -q '^## Outstanding items' .session-continuity/SESSION_PRIMER.md 2>/dev/null && echo "PRIMER_HAS_INLINE_OUTSTANDING=1" || echo "PRIMER_HAS_INLINE_OUTSTANDING=0"
[ -f .session-continuity/BACKLOG.md ] && echo "BACKLOG_EXISTS=1" || echo "BACKLOG_EXISTS=0"
[ -f .session-continuity/ROADMAP.md ] && echo "ROADMAP_EXISTS=1" || echo "ROADMAP_EXISTS=0"
git remote get-url origin 2>/dev/null || echo "NO_ORIGIN"
git log --oneline -5
git diff --cached --name-only
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-1-detect-state --duration="$_PERF_DURATION"
```

Interpret the output:

1. Do `.session-continuity/SESSION_PRIMER.md` and `.session-continuity/LEARNINGS.md` exist? (`PRIMER_EXISTS` / `LEARNINGS_EXISTS` above.)
2. If a primer exists, does the `git log --oneline -5` block inside it match the `git log --oneline -5` output above? (mtime is intentionally not checked — formatters, save-on-blur, and `cat | tee` all bump mtime without changing content. The log-block diff is the authoritative drift signal.)
3. Does the `git diff --cached --name-only` output above contain any file outside `docs/`, `.session-continuity/`, `README*`, `CHANGELOG*`, `LICENSE*`? (Code is staged and a commit is imminent — the primer will be stale the moment that commit lands.)
4. If a primer exists, does `.session-continuity/PROJECT_CONTEXT.md` also exist? (`PROJECT_CONTEXT_EXISTS` above.)

Four states result:

- **No primer** → init mode (Step 2)
- **Primer exists but unsplit** (no `PROJECT_CONTEXT.md` yet) → split mode (Step 3)
- **Primer exists but stale** (log block drifted or code staged for commit) → refresh mode (Step 4)
- **Primer exists and current** (nothing staged) → check mode (Step 5)

If `PRIMER_HAS_INLINE_OUTSTANDING=1` AND `OUTSTANDING_ITEMS_EXISTS=0`,
outstanding-items migration is needed — run it (Step 3b below) in addition
to whichever of the four states above applies. **Sequencing:** if the
primer is also unsplit (no `PROJECT_CONTEXT.md`), run the existing Split
mode (Step 3) to completion first, then run Step 3b against the resulting
primer, as two sequential edits — not simultaneous partitioning. The two
splits touch disjoint sections of the primer (stable-context headings vs.
the Outstanding items heading), so sequencing avoids any edit conflict.

If `OUTSTANDING_ITEMS_EXISTS=1` AND `BACKLOG_EXISTS=0`, a file-rename
migration is needed — run it (Step 3c below) in addition to whichever of
the four states above applies. **Sequencing:** if Step 3b also fired this
run (inline heading present, no file yet), run Step 3b to completion
first — it still writes `OUTSTANDING_ITEMS.md` under the old name — then
run Step 3c against that result. Step 3c is strictly the one-level-up
file rename; it never inspects primer content.

If `BACKLOG_EXISTS=1` (including after Step 3c) AND origin contains
`github.com`, run Step 3d (markdown backlog → GitHub Issues) after 3c.
````

with:

````markdown
## Step 1 — Detect state

Run the shared dispatch script once, timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-detect.sh" 1; then
  DETECT_OUTPUT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-detect.sh" . 2>&1)"
  DETECT_STATUS=$?
else
  DETECT_OUTPUT="$SC_REQUIRE_SCRIPT_MSG"
  DETECT_STATUS=1
fi
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=primer --step=step-1-detect-state --duration="$_PERF_DURATION"
echo "$DETECT_OUTPUT"
echo "DETECT_STATUS=$DETECT_STATUS"
```

**If `DETECT_STATUS` is nonzero, or `$DETECT_OUTPUT` has no `STEPS=` line:
stop.** Report `$DETECT_OUTPUT` to the user (it carries the diagnostic
either way — `require_script`'s message, or `primer-detect.sh`'s own
stderr, merged into stdout above) and do not execute any step below —
there is no safe default dispatch, since some steps run destructive
migrations (`git mv` in Step 3c, `git rm` in Step 3d).

**Otherwise**, read `STEPS=` from `$DETECT_OUTPUT` and **execute every
name it lists, in the order given, then stop.** Do not re-derive which
steps should run from the individual `KEY=value` facts printed above
`STEPS=` — those are for transparency/debugging only, not a second
source of dispatch truth. An empty `STEPS=` means check mode: run Step 5.

| Name in `STEPS` | Run |
|---|---|
| `init` | Step 2 (the only value `STEPS` can ever carry alone) |
| `split` | Step 3 |
| `outstanding_split` | Step 3b |
| `backlog_rename` | Step 3c |
| `backlog_to_issues` | Step 3d |
| `refresh` | Step 4 |
````

- [ ] **Step 2: Simplify Step 3b's opening sentence**

Using the Edit tool, replace this exact block (currently `commands/primer.md`, the two sentences immediately under `## Step 3b — Outstanding-items split`):

```markdown
Runs whenever `PRIMER_HAS_INLINE_OUTSTANDING=1` and
`OUTSTANDING_ITEMS_EXISTS=0` (see Step 1). Extract the primer's inline
`## Outstanding items` section into the new file; this is a one-time
content move, no numbering changes — the items keep whatever numbers
they currently have, and those become the first permanent IDs.
```

with:

```markdown
Runs when `outstanding_split` appears in Step 1's `STEPS`. Extract the
primer's inline `## Outstanding items` section into the new file; this
is a one-time content move, no numbering changes — the items keep
whatever numbers they currently have, and those become the first
permanent IDs.
```

- [ ] **Step 3: Simplify Step 3c's opening sentence**

Using the Edit tool, replace this exact block (currently `commands/primer.md`, the paragraph immediately under `## Step 3c — Backlog rename migration`):

```markdown
Runs whenever `BACKLOG_EXISTS=0` AND `OUTSTANDING_ITEMS_EXISTS=1` (see
Step 1). This is strictly the `OUTSTANDING_ITEMS.md` → `BACKLOG.md`
rename, one level up from Step 3b (which may have just created
`OUTSTANDING_ITEMS.md` under its old name this same run — Step 3c runs
after it, per the sequencing note in Step 1).
```

with:

```markdown
Runs when `backlog_rename` appears in Step 1's `STEPS`. This is strictly
the `OUTSTANDING_ITEMS.md` → `BACKLOG.md` rename, one level up from Step
3b (which may have just created `OUTSTANDING_ITEMS.md` under its old
name this same run — `STEPS` already places `backlog_rename` after
`outstanding_split` when both fire).
```

- [ ] **Step 4: Simplify Step 3d's opening sentence**

Using the Edit tool, replace this exact block (currently `commands/primer.md`, the paragraph immediately under `## Step 3d — BACKLOG.md → GitHub Issues`):

```markdown
Runs whenever `BACKLOG_EXISTS=1` (including after Step 3c just created
it) AND Step 1's origin URL contains `github.com`. If origin is missing
or not github.com, leave the file in place as a fossil and tell the
user `/session-continuity:doctor` will warn that the queue is inactive.
Do not keep writing to the fossil.
```

with:

```markdown
Runs when `backlog_to_issues` appears in Step 1's `STEPS`. If it doesn't
(non-github origin, or no backlog to migrate), leave any existing
`BACKLOG.md` in place as a fossil and tell the user
`/session-continuity:doctor` will warn that the queue is inactive. Do
not keep writing to the fossil.
```

- [ ] **Step 5: Verify the old per-step condition restatements are gone**

```bash
grep -c 'PRIMER_HAS_INLINE_OUTSTANDING=1.*and\|BACKLOG_EXISTS=0.*AND OUTSTANDING\|BACKLOG_EXISTS=1.*(including after Step 3c' commands/primer.md
```

Expected: `0` — the boolean conditions now live only in `primer-detect.jq`, referenced by `STEPS` membership everywhere else.

- [ ] **Step 6: Commit**

```bash
git add commands/primer.md
git commit -m "refactor: primer.md Step 1 dispatches via primer-detect.sh"
```

---

### Task 3: Doc pointers, regression pass, changelog

**Files:**
- Modify: `meta/superpowers/specs/2026-09-02-determinism-program-design.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Update the design doc's Phase 6 entry**

Using the Edit tool, replace this exact block in `meta/superpowers/specs/2026-09-02-determinism-program-design.md`:

```markdown
**Phase 6 `#43` — `primer` detect, migrate, init, drift.** Mode detection plus
migration triggers (11-60, pure boolean logic over file existence); the
backlog rename migration (209-248, forty lines of prompt with no judgment in
any of its seven items, performing a destructive `git mv`); init-mode template
copy and mechanical placeholder substitution, collapsing the ten
`{{LATEST_COMMIT_*}}` slots into one `{{GIT_LOG_BLOCK}}`; and the drift check
plus test-count rerun with modal pinning (172-210, 249-250, 264-278). Largest
phase, lowest per-invocation frequency, highest blast radius — it runs a
`git mv` and rewrites five files.
```

with:

```markdown
**Phase 6 `#43` — `primer` detect, migrate, init, drift.** Decomposed into
five sub-projects (see `meta/superpowers/specs/2026-09-08-primer-detect-design.md`'s
Context section for the full breakdown and why): **sub-project A shipped**
— Step 1's mode detection plus all three migration triggers, previously
hand-evaluated nested conditionals with an easy-to-miss sequencing rule,
now `hooks/lib/primer-detect.sh`/`.jq`. Plan:
`meta/superpowers/plans/2026-09-08-primer-detect.md`. Still pending:
sub-project B (Step 4's test-count majority-vote rerun — the same
compare-a-claimed-value-against-an-actual-one class Phase 7 is being
built to gate against), C (Step 3c/3d's `git mv`/`git rm` migration
mechanics themselves — sub-project A only scripted *whether* they run,
not *what* they do), D (Step 2's placeholder-derivation gather-and-regex),
E (Step 3/3b's section-bucketing judgment, lowest priority — near-zero
remaining audience, most judgment-heavy of the five).
```

- [ ] **Step 2: Full regression pass**

```bash
for f in \
  meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh \
  meta/superpowers/validation/2026-09-08-token-overlap.md \
  meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh \
  meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh \
  meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh \
  meta/superpowers/validation/2026-08-12-session-start-smoke.zsh \
  meta/superpowers/validation/2026-09-01-require-script-smoke.zsh \
  meta/superpowers/validation/2026-09-07-backlog-issues-smoke.zsh \
  meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh \
  meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh \
  meta/superpowers/validation/2026-09-02-count-entries-smoke.zsh \
  meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh \
  meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
do
  [[ "$f" == *.zsh ]] || continue
  echo "--- $f ---"
  zsh "$f" || echo "FAILED: $f"
done
```

Expected: every runner ends `0 failed`. (`2026-09-08-token-overlap.md` in
the list above is a validation *log*, not a runner — included for
completeness of the "everything touched this program" review, nothing to
execute.)

- [ ] **Step 3: Add a CHANGELOG entry**

Add a new section at the top of `CHANGELOG.md`, directly under the `# Changelog` header and its description line, above the current top entry:

```markdown
## [0.32.0] — 2026-09-08

### Changed
- **`/session-continuity:primer`'s Step 1 dispatch is now scripted.** New `hooks/lib/primer-detect.sh`/`.jq` replace ~15 lines of hand-evaluated nested-conditional prose (a 4-state classification plus 3 migration triggers with an easy-to-miss sequencing rule) with one script call that prints a definitive, ordered `STEPS=` list. The trigger chain is evaluated by threading each trigger's effect forward into the fact the next depends on (`outstanding_split → backlog_rename → backlog_to_issues`), not by re-deriving disjunctions per trigger — an approach tried and found not to compose past one chained link during this work. Determinism Phase 6 (#43) sub-project A; sub-projects B–E remain pending.
```

- [ ] **Step 4: Bump the plugin version**

Using the Edit tool, update `.claude-plugin/plugin.json`'s `"version"` field from `"0.31.0"` to `"0.32.0"`.

- [ ] **Step 5: Commit**

```bash
git add meta/superpowers/specs/2026-09-02-determinism-program-design.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "docs: Phase 6 sub-project A doc pointers, changelog, and version bump"
```
