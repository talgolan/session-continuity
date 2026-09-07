# Determinism Phase 5 — backlog mechanics and the commit-overlap gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close backlog items `#42` and `#40` together. Fix `candidate-extract.jq`'s `overlap()` — an asymmetric, multiplicity-mismatched Jaccard that over-merges distinct LEARNINGS candidates (`#40`) — and lift two new shared scripts, `hooks/lib/backlog-item.sh` (tag mint / tag-in-use / renumber) and `hooks/lib/commit-overlap.sh` (tokenize + stopword-drop + threshold intersection), so the backlog-bookkeeping and commit-overlap logic that `primer.md` and `end-session.md` currently perform as hand-executed prose becomes one deterministic call each (`#42`).

**Architecture:** Three independent scripts, one bugfix and two new shared libraries — `candidate-extract.jq`'s `overlap()` gets a symmetric, deduped rewrite plus a title-suffix exclusion; `backlog-item.sh` centralizes the three backlog-editing primitives `primer.md` currently re-derives by hand in two places (init-mode Step 2, refresh-mode Step 4); `commit-overlap.sh` centralizes the tokenize/stopword/intersection-cardinality primitive that today exists as two separate hand-executed prose blocks inside `end-session.md` (the backlog-verification overlap gate and the refresh-flow's backlog overlay) — these two blocks use the identical primitive in opposite directions (item-vs-commit-subject and subject-vs-item), which is the same primitive because set intersection is symmetric, so one script serves both call sites. `commit-overlap.sh`'s Jaccard-free intersection-cardinality metric and threshold (3) are a **different** algorithm from `candidate-extract.jq`'s normalized Jaccard (threshold 0.7) — the two are not unified into one script; conflating them was explicitly ruled out during scoping (see Global Constraints).

**Tech Stack:** Bash, jq, awk (smoke tests in zsh, matching every other script in `hooks/lib/`).

**Spec:** `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (Phase 5 entry, lines 191-199).

**Evidence-gate:** N/A — no poll/wait loop appears anywhere in this plan's scripts or smoke tests; every check is a one-shot assertion against a fixed fixture, not a retry/timeout loop.

## Global Constraints

- Every new or modified script prints best-effort output. `backlog-item.sh mint` and `tag-in-use` always exit true-to-purpose (`tag-in-use`'s exit code IS its answer — 0 found, 1 clean, matching `grep`'s own convention) but `renumber` and any file-mutating path **exit non-zero on write failure** — unlike `perf-log.sh`'s "never block the ritual" logging convention, a failed rewrite of `BACKLOG.md` must be visible, not silently swallowed. `commit-overlap.sh` is a read-only text comparison and always exits 0.
- Every new script invoked from a *command* markdown file (`primer.md`, `end-session.md`) carries a `# CONTRACT_VERSION=1` header and is called through `require_script` (from `hooks/lib/require-script.sh`), exactly like `primer-status.sh`, `resolve-transcript.sh`, and `agent-active.sh` already are.
- `candidate-extract.jq` keeps `CONTRACT_VERSION=2` — this plan changes `overlap()`'s internal scoring only, not the JSON output shape `candidate-extract.sh` depends on, so the hardcoded skew check at `hooks/lib/candidate-extract.sh:76` (`grep -q '^# CONTRACT_VERSION=2$'`) does not need updating. Do not bump it — bumping without updating that grep would make the wrapper treat its own sibling as skewed.
- `commit-overlap.sh`'s intersection-cardinality metric (drop tokens <3 chars, drop the stopword list, threshold ≥3) is a **different algorithm from `candidate-extract.jq`'s `overlap()`** (normalized Jaccard, threshold 0.7, no stopword list). Do not merge them into one script or one threshold — Task 1 and Task 3 are scoped and tested independently.
- `renumber` must skip lines inside fenced code blocks and HTML comments, using the identical state machine `hooks/lib/render-backlog.awk` already implements — `.session-continuity/BACKLOG.md`'s own shipped template (`skills/session-continuity/templates/BACKLOG.md`) has an example `### 1. [a3f9] ...` heading wrapped in an `<!-- Example: ... -->` comment, and renumbering it would corrupt the template.
- Never invent a tag: `backlog-item.sh mint` retries against real collisions (the target file's existing tags, plus any tags already minted earlier in the same batch, tracked by the caller) rather than assuming a fixed retry count always succeeds.
- Do not touch Phase 4 (`#41`, Step 3 checklist assembly) or Phase 6/7 (`#43`/`#44`) — out of scope.
- An unrelated stale-doc defect was found while reading `hooks/lib/render.sh` for this plan (`render.sh:119-121`'s `/help` text says BACKLOG.md is "Permanently numbered... never renumbered," which is backwards — that describes LEARNINGS.md's convention, not BACKLOG.md's ephemeral 1..N renumbering). **Out of scope for this plan** — flagged to the user separately, not bundled in here.

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/lib/candidate-extract.jq` (modified) | `overlap()` becomes a true symmetric, deduped-set Jaccard; new `dedup_key` strips the retry-burst title's shared template suffix before scoring so two distinct retry-bursts sharing that suffix no longer over-merge. |
| `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh` (modified) | New assertions: `overlap()` symmetry, the two-distinct-retry-bursts-sharing-a-suffix case no longer merges, and a regression that genuinely similar titles still dedupe. |
| `hooks/lib/backlog-item.sh` (new) | `mint` / `tag-in-use` / `renumber` subcommands, replacing prose `primer.md` currently executes by hand in Step 2 (init) and Step 4 item 6 (refresh). |
| `meta/superpowers/validation/2026-09-07-backlog-item-smoke.zsh` (new) | Smoke test for the new script. |
| `hooks/lib/commit-overlap.sh` (new) | Tokenize + stopword-drop + threshold-N intersection-cardinality check, replacing the two prose copies inside `end-session.md`. |
| `meta/superpowers/validation/2026-09-07-commit-overlap-smoke.zsh` (new) | Smoke test for the new script. |
| `commands/primer.md` (modified) | Step 2's backlog-conversion mint logic and Step 4 item 6's mint/tag-in-use/renumber prose switch to `backlog-item.sh` calls. |
| `commands/end-session.md` (modified) | The backlog-verification overlap gate and the refresh-flow's backlog overlay switch to `commit-overlap.sh` calls; the stale "Step 5 of `commands/primer.md`" cross-reference at line 236 is corrected. |
| `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (modified) | Phase 5 entry collapses to a pointer at this plan, per the doc's own "Entry format" rule (matching how Phase 3's entry was collapsed). |
| `.session-continuity/BACKLOG.md` (modified) | Items `#42` and `#40` marked closed, pointing at the commits that fix them. |
| `CHANGELOG.md` (modified) | New version entry. |
| `.claude-plugin/plugin.json` (modified) | Version bump. |

---

### Task 1: Fix `candidate-extract.jq`'s `overlap()` (closes `#40`)

**Files:**
- Modify: `hooks/lib/candidate-extract.jq:95-107`
- Modify: `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`

**Interfaces:**
- Produces: `overlap($ta; $tb)` — same signature, same 0..1 output range, same call site (`candidate-extract.jq:242`, the dedup `reduce`). Only the scoring is corrected; `candidate-extract.sh`'s consumers (the JSON shape) are unaffected.

- [ ] **Step 1: Write the failing smoke test additions**

Read `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh` in full (already open in this plan's context — 373 lines, `pass`/`fail`/`ok`/`bad` already defined, `mk_bash_call`/`mk_edit`/`mk_result` fixture builders already defined). Using the Edit tool, insert the following block immediately before the final `rm -rf "$work_ce"` line (currently line 368):

```zsh
# --- c9a4 regression: overlap() symmetry and suffix over-merge ---------------

# Two genuinely distinct retry-bursts whose titles differ only in the
# command-specific portion, sharing the boilerplate
# " — re-run N times with M file edits in between." suffix. Before the
# fix, this suffix's shared tokens pushed the pair's score to 0.722 --
# over the 0.7 threshold -- so the second command was silently dropped.
overlap_a_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T10:00:00.000Z" "oa1" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T10:01:00.000Z" "oa2" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T10:02:00.000Z" "oa3" "bun test src/foo.test.ts"
  mk_edit      "2026-09-01T10:00:30.000Z" "oae1"
} > "$overlap_a_f"
overlap_b_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T11:00:00.000Z" "ob1" "bun test src/bar.test.ts"
  mk_bash_call "2026-09-01T11:01:00.000Z" "ob2" "bun test src/bar.test.ts"
  mk_bash_call "2026-09-01T11:02:00.000Z" "ob3" "bun test src/bar.test.ts"
  mk_edit      "2026-09-01T11:00:30.000Z" "obe1"
} > "$overlap_b_f"
combined_f="$(mktemp)"
cat "$overlap_a_f" "$overlap_b_f" > "$combined_f"
out="$(bash "$lib/candidate-extract.sh" "$combined_f")"
n="$(print -r -- "$out" | jq '[.candidates[] | select(.heuristic=="retry-burst")] | length')"
[[ "$n" -eq 2 ]] && ok "c9a4: two retry-bursts sharing the title-template suffix stay distinct" \
  || bad "c9a4: expected 2 distinct retry-bursts, got $n (suffix over-merge regressed): $out"
rm -f "$overlap_a_f" "$overlap_b_f" "$combined_f"

# overlap() itself must be symmetric: swapping which title is "a" and
# which is "b" must not change the score. Before the fix, the numerator
# counted $wa's words with multiplicity while the denominator was the
# deduped union, so overlap(A;B) != overlap(B;A). candidate-extract.jq is
# a filter, not an includable module (its top-level pipeline reads
# $tracked_files/inputs, undefined outside a real run) -- build a driver
# program instead: everything up to the top-level pipeline's start, plus
# a call comparing both directions. Anchored on the `[inputs] as $lines`
# marker, not a line number, so this survives Task 1 Step 3 inserting
# `dedup_key` before `overlap` and shifting every line below it.
driver_f="$(mktemp)"
{ sed -n '1,/^\[inputs\] as \$lines/{/^\[inputs\] as \$lines/!p}' "$lib/candidate-extract.jq"; \
  print -r -- '[overlap("Reverted approach: vitest run."; "Reverted approach: jest run."), overlap("Reverted approach: jest run."; "Reverted approach: vitest run.")]'; \
} > "$driver_f"
scores="$(jq -n -f "$driver_f" 2>/dev/null)"
rm -f "$driver_f"
a_score="$(print -r -- "$scores" | jq '.[0]')"
b_score="$(print -r -- "$scores" | jq '.[1]')"
[[ -n "$a_score" && "$a_score" == "$b_score" ]] && ok "c9a4: overlap() is symmetric (both directions score $a_score)" \
  || bad "c9a4: overlap() is asymmetric or errored: A;B=$a_score B;A=$b_score"

# Regression: genuinely similar titles (one word swapped out of few) must
# still dedupe -- the fix must not turn dedup off entirely.
sim_a_f="$(mktemp)"
mk_bash_call "2026-09-01T12:00:00.000Z" "sa1" "rm -rf src/broken.ts" > "$sim_a_f"
sim_repo="$(gt_make_repo)"
gt_stage "$sim_repo" "src/broken.ts" "old content"
git -C "$sim_repo" commit -q -m "add broken.ts"
out="$(cd "$sim_repo" && bash "$lib/candidate-extract.sh" "$sim_a_f")"
print -r -- "$out" | jq -e '.candidates | length == 1' >/dev/null 2>&1 \
  && ok "c9a4: a single genuine candidate still survives dedup unchanged" \
  || bad "c9a4: single-candidate baseline broke: $out"
rm -f "$sim_a_f"
gt_cleanup "$sim_repo"
```

- [ ] **Step 2: Run it to verify the new assertions fail**

Run: `zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: the two `c9a4:` assertions FAIL (the suffix-over-merge test sees `n=1` not `2`; the symmetry test sees `a_score != b_score`). The single-candidate regression assertion PASSes already (unrelated to the bug) — that's fine, it's there to catch a future overcorrection, not to fail now.

- [ ] **Step 3: Rewrite `overlap()` in `hooks/lib/candidate-extract.jq`**

Replace lines 95-107 (the `title_words` def through the end of `overlap`):

```jq
def title_words:
  ascii_downcase
  | gsub("[^a-z0-9 ]+"; " ")
  | [splits(" +")]
  | map(select(length > 0));

# Strips the retry-burst heuristic's shared title-template suffix before
# scoring for dedup. Without this, two distinct retry-bursts on
# genuinely different commands score high purely on the ~10 boilerplate
# words ("re run N times with M file edits in between") they share
# regardless of which command actually ran.
def dedup_key:
  sub(" — re-run [0-9]+ times with [0-9]+ file edits? in between\\.$"; "");

# Symmetric, multiplicity-free Jaccard: both sides are deduped to sets
# before computing intersection/union, so overlap(A;B) == overlap(B;A).
# The prior version's numerator counted $wa's words with multiplicity
# while the denominator was the deduped union -- an asymmetric mismatch
# that scored short/similar titles (e.g. "vitest"/"jest") above the 0.7
# threshold when they shouldn't have merged.
def overlap($ta; $tb):
  ($ta | dedup_key | title_words | unique) as $wa
  | ($tb | dedup_key | title_words | unique) as $wb
  | ($wa + $wb | unique) as $u
  | if ($u | length) == 0 then 0
    else (($wa - ($wa - $wb)) | length) / ($u | length)
    end;
```

- [ ] **Step 4: Run the smoke test to verify all assertions pass**

Run: `zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: all assertions PASS, including the pre-existing 40+ and the new `c9a4:` ones. Also re-run the full suite once more to confirm the pre-existing "per-heuristic cap" test block's comment (lines 251-257 in the original file, about an earlier draft's foo/beta/gamma titles Jaccard-collapsing at 1.0) is still consistent — it should be, since that comment already describes the fixed formula's expected behavior for near-identical titles.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/candidate-extract.jq meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
git commit -m "fix: candidate-extract.jq's overlap() is now a symmetric, multiplicity-free Jaccard (#40)"
```

---

### Task 2: `backlog-item.sh` — `mint` / `tag-in-use` / `renumber`

**Files:**
- Create: `hooks/lib/backlog-item.sh`
- Create: `meta/superpowers/validation/2026-09-07-backlog-item-smoke.zsh`

**Interfaces:**
- Produces: `backlog-item.sh mint <backlog-file>` → prints `TAG=<4-hex>` and `DATE=<YYYY-MM-DD>` on stdout, exit 0 (exit 0 with nothing printed and a stderr message if the file arg is missing/unreadable, or if 50 mint attempts all collide). `backlog-item.sh tag-in-use <tag> [<search-root default .>]` → prints matching `file:line` citations to stdout, exit 0 if found, exit 1 if clean (matches `grep`'s own convention). `backlog-item.sh renumber <backlog-file>` → rewrites the file in place, no stdout, exit 0 on success, **exit 1** on any write failure.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-07-backlog-item-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# backlog-item.sh smoke test. Hermetic: temp files and a throwaway git repo,
# never touches this repo's own BACKLOG.md.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
source "$here/lib/gate-test-common.zsh"
item="$lib/backlog-item.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# --- mint ---------------------------------------------------------------

empty_backlog="$(mktemp)"
print -r -- "# Backlog — test" > "$empty_backlog"
out="$(bash "$item" mint "$empty_backlog")"
tag="$(print -r -- "$out" | sed -n 's/^TAG=//p')"
date_out="$(print -r -- "$out" | sed -n 's/^DATE=//p')"
[[ "$tag" =~ ^[0-9a-f]{4}$ ]] && ok "mint: prints a 4-hex tag" || bad "mint: bad TAG output: $out"
[[ "$date_out" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && ok "mint: prints a YYYY-MM-DD date" || bad "mint: bad DATE output: $out"

collide_backlog="$(mktemp)"
{
  print -r -- "# Backlog — test"
  print -r -- "### 1. [$tag] [2026-09-07] Existing item"
} > "$collide_backlog"
out2="$(bash "$item" mint "$collide_backlog")"
tag2="$(print -r -- "$out2" | sed -n 's/^TAG=//p')"
[[ "$tag2" != "$tag" ]] && ok "mint: never re-mints a tag already present in the file" \
  || bad "mint: re-minted a colliding tag: $tag2"
rm -f "$empty_backlog" "$collide_backlog"

out3="$(bash "$item" mint /no/such/file 2>/dev/null)"
[[ -z "$out3" ]] && ok "mint: missing file prints nothing on stdout" || bad "mint: missing file printed: $out3"

# --- tag-in-use -----------------------------------------------------------

tag_repo="$(gt_make_repo)"
mkdir -p "$tag_repo/.session-continuity"
print -r -- "See item [a3f9] for context." > "$tag_repo/.session-continuity/BACKLOG.md"
git -C "$tag_repo" add -A
git -C "$tag_repo" commit -q -m "seed"
( cd "$tag_repo" && bash "$item" tag-in-use a3f9 ) >/dev/null 2>&1
rc=$?
[[ "$rc" -eq 0 ]] && ok "tag-in-use: exit 0 when the tag is referenced" || bad "tag-in-use: expected exit 0, got $rc"
( cd "$tag_repo" && bash "$item" tag-in-use dead ) >/dev/null 2>&1
rc=$?
[[ "$rc" -eq 1 ]] && ok "tag-in-use: exit 1 when the tag is clean" || bad "tag-in-use: expected exit 1, got $rc"
gt_cleanup "$tag_repo"

# --- renumber ---------------------------------------------------------------

renumber_f="$(mktemp)"
cat > "$renumber_f" <<'EOF'
# Backlog — test

Intro text.

<!-- Example:
### 1. [a3f9] [2026-09-01] Example item, must not renumber
-->

### 5. [aaaa] [2026-08-01] First real item

### 9. [bbbb] — closed. Fixed in `deadbeef`.

### 12. [cccc] [2026-08-02] Third real item
EOF
bash "$item" renumber "$renumber_f"
rc=$?
[[ "$rc" -eq 0 ]] && ok "renumber: exits 0 on success" || bad "renumber: exited $rc"
grep -q '^### 1\. \[aaaa\]' "$renumber_f" && ok "renumber: first real item becomes position 1" \
  || bad "renumber: first item not renumbered: $(grep '\[aaaa\]' "$renumber_f")"
grep -q '^### 2\. \[bbbb\]' "$renumber_f" && ok "renumber: closed stub becomes position 2 (still renumbered, not skipped)" \
  || bad "renumber: closed stub not renumbered: $(grep '\[bbbb\]' "$renumber_f")"
grep -q '^### 3\. \[cccc\]' "$renumber_f" && ok "renumber: third real item becomes position 3" \
  || bad "renumber: third item not renumbered: $(grep '\[cccc\]' "$renumber_f")"
grep -q '^### 1\. \[a3f9\] \[2026-09-01\] Example item' "$renumber_f" \
  && ok "renumber: the HTML-comment-wrapped template example is untouched" \
  || bad "renumber: corrupted the commented-out example: $(grep 'a3f9' "$renumber_f")"
rm -f "$renumber_f"

bash "$item" renumber /no/such/file >/dev/null 2>&1
rc=$?
[[ "$rc" -ne 0 ]] && ok "renumber: missing file exits non-zero" || bad "renumber: missing file exited 0"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh meta/superpowers/validation/2026-09-07-backlog-item-smoke.zsh`
Expected: FAIL — `hooks/lib/backlog-item.sh: No such file or directory` (or similar) on the first `bash "$item" mint ...` call, since the script doesn't exist yet.

- [ ] **Step 3: Write `hooks/lib/backlog-item.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/backlog-item.sh — backlog item bookkeeping (session-continuity plugin).
#
# Three subcommands, replacing prose commands/primer.md previously executed
# by hand in its init (Step 2) and refresh (Step 4) flows:
#   mint       — generate an unused 4-hex tag + today's UTC date.
#   tag-in-use — grep a tree for a tag before deleting a closed item.
#   renumber   — rewrite a BACKLOG.md's own <position> numbers to 1..N in
#                file order, skipping fenced code blocks and HTML comments
#                (the shipped template's own example heading lives inside
#                one) — the identical guard hooks/lib/render-backlog.awk
#                uses for the read path.
#
# Usage:
#   backlog-item.sh mint <backlog-file>
#   backlog-item.sh tag-in-use <tag> [<search-root, default .>]
#   backlog-item.sh renumber <backlog-file>
#
# mint prints nothing and exits 0 on bad input (missing/unreadable file, or
# 50 mint attempts all colliding) — it has no ritual to protect, but there
# is also nothing useful to do with a hard failure here; the caller MUST
# check for empty TAG=/DATE= output rather than assume success. tag-in-use's
# exit code IS its answer, and callers must branch on all three outcomes,
# not just "0 vs. nonzero": 0 = found a reference (grep's own convention,
# do not delete), 1 = clean (safe to delete), 2 = the check itself failed
# (bad root, grep error — do not delete; the safety check didn't run).
# renumber mutates a file in place and exits 1 on any write failure --
# unlike perf-log.sh's "never block the ritual" logging convention, a
# failed rewrite of BACKLOG.md must be visible, not silently swallowed.

set -uo pipefail

cmd_mint() {
  local file="${1:-}"
  if [[ -z "$file" || ! -r "$file" ]]; then
    echo "backlog-item.sh: mint requires a readable backlog file" >&2
    return 0
  fi
  local tag tries=0
  while :; do
    tag="$(printf '%04x' "$(( (RANDOM * 32768 + RANDOM) % 65536 ))")"
    grep -q "\[$tag\]" "$file" 2>/dev/null || break
    tries=$(( tries + 1 ))
    if [[ "$tries" -ge 50 ]]; then
      echo "backlog-item.sh: could not find an unused tag after 50 tries" >&2
      return 0
    fi
  done
  printf 'TAG=%s\n' "$tag"
  printf 'DATE=%s\n' "$(date -u +%Y-%m-%d)"
  return 0
}

cmd_tag_in_use() {
  local tag="${1:-}" root="${2:-.}"
  if [[ -z "$tag" ]]; then
    echo "backlog-item.sh: tag-in-use requires a tag" >&2
    return 1
  fi
  grep -rn --exclude-dir=.git -E "\[$tag\]|\b$tag\b" "$root"
}

cmd_renumber() {
  local file="${1:-}"
  if [[ -z "$file" || ! -f "$file" ]]; then
    echo "backlog-item.sh: renumber requires an existing backlog file" >&2
    return 1
  fi
  local tmp
  tmp="$(mktemp)" || { echo "backlog-item.sh: mktemp failed" >&2; return 1; }
  awk '
    BEGIN { fence = 0; in_comment = 0; n = 0 }
    {
      line = $0
      if (line ~ /^```/) { fence = !fence; print line; next }
      if (fence) { print line; next }
      if (in_comment) {
        if (index(line, "-->") > 0) in_comment = 0
        print line; next
      }
      if (index(line, "<!--") > 0) {
        rest = substr(line, index(line, "<!--") + 4)
        if (index(rest, "-->") == 0) { in_comment = 1; print line; next }
        print line; next
      }
      if (line ~ /^### [0-9]+\./) {
        n++
        sub(/^### [0-9]+\./, "### " n ".", line)
      }
      print line
    }
  ' "$file" > "$tmp"
  if [[ $? -ne 0 ]]; then
    rm -f "$tmp"
    echo "backlog-item.sh: awk pass failed" >&2
    return 1
  fi
  if ! mv "$tmp" "$file"; then
    rm -f "$tmp"
    echo "backlog-item.sh: could not write $file" >&2
    return 1
  fi
  return 0
}

subcommand="${1:-}"
shift || true

case "$subcommand" in
  mint)       cmd_mint "$@" ;;
  tag-in-use) cmd_tag_in_use "$@" ;;
  renumber)   cmd_renumber "$@" ;;
  *)
    echo "backlog-item.sh: unknown subcommand '$subcommand' (expected 'mint', 'tag-in-use', or 'renumber')" >&2
    exit 1
    ;;
esac
```

Make it executable: `chmod +x hooks/lib/backlog-item.sh`.

- [ ] **Step 4: Run the smoke test to verify it passes**

Run: `zsh meta/superpowers/validation/2026-09-07-backlog-item-smoke.zsh`
Expected: all assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/backlog-item.sh meta/superpowers/validation/2026-09-07-backlog-item-smoke.zsh
git commit -m "feat: add backlog-item.sh (mint/tag-in-use/renumber), shared backlog bookkeeping"
```

---

### Task 3: `commit-overlap.sh` — tokenize + stopword-drop + threshold intersection

**Files:**
- Create: `hooks/lib/commit-overlap.sh`
- Create: `meta/superpowers/validation/2026-09-07-commit-overlap-smoke.zsh`

**Interfaces:**
- Produces: `commit-overlap.sh --a="<text>" --b="<text>" [--threshold=N, default 3]` → prints `OVERLAP=<intersection cardinality>` then `MATCH=1` or `MATCH=0` on stdout, always exit 0.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-07-commit-overlap-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# commit-overlap.sh smoke test. Hermetic: no filesystem or git state, pure
# text-in/text-out.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
overlap="$lib/commit-overlap.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

get() { print -r -- "$1" | sed -n "s/^${2}=//p"; }  # <output> <KEY>

# Real case from end-session.md's own worked example: a backlog item about
# `end-session.md` Step 4's `$start_epoch` bug, versus the commit subject
# that actually fixed it.
out="$(bash "$overlap" --a="end-session Step 4 does not survive its own cross-Bash-call boundary so step-4-agent-active never logs" --b="refactor: end-session.md collapses its four epoch-subtraction blocks to mark/since, fixing step-4-agent-active's start_epoch scope bug (52dc)")"
match="$(get "$out" MATCH)"
[[ "$match" == "1" ]] && ok "matching item/subject pair crosses the threshold" \
  || bad "expected MATCH=1, got: $out"

# Unrelated text stays below threshold.
out="$(bash "$overlap" --a="Submit to the Anthropic marketplace" --b="fix: count-entries.sh now skips headings with self-closing inline comments")"
match="$(get "$out" MATCH)"
[[ "$match" == "0" ]] && ok "unrelated item/subject pair stays below threshold" \
  || bad "expected MATCH=0, got: $out"

# Stopwords and short tokens don't count toward the cardinality even when
# they're the only words two unrelated strings share.
out="$(bash "$overlap" --a="the fix for add and update primer session" --b="the fix for add and update learnings tag")"
overlap_n="$(get "$out" OVERLAP)"
[[ "$overlap_n" -eq 0 ]] && ok "shared stopwords/short tokens do not count toward OVERLAP" \
  || bad "expected OVERLAP=0 (all shared tokens are stopwords), got: $out"

# Symmetric: swapping --a/--b gives the same OVERLAP.
out_ab="$(bash "$overlap" --a="hooks lib backlog item renumber tag mint" --b="backlog item mint tag renumber logic")"
out_ba="$(bash "$overlap" --a="backlog item mint tag renumber logic" --b="hooks lib backlog item renumber tag mint")"
n_ab="$(get "$out_ab" OVERLAP)"
n_ba="$(get "$out_ba" OVERLAP)"
[[ "$n_ab" -eq "$n_ba" ]] && ok "OVERLAP is symmetric ($n_ab both directions)" \
  || bad "OVERLAP asymmetric: a;b=$n_ab b;a=$n_ba"

# Custom threshold is honored.
out="$(bash "$overlap" --a="alpha beta gamma delta" --b="alpha beta epsilon zeta" --threshold=2)"
match="$(get "$out" MATCH)"
[[ "$match" == "1" ]] && ok "custom --threshold=2 is honored (2 shared tokens meets it)" \
  || bad "expected MATCH=1 at threshold=2, got: $out"

# Empty input never crashes and never false-matches.
out="$(bash "$overlap" --a="" --b="anything at all here")"
[[ "$?" -eq 0 ]] && ok "empty --a exits 0" || bad "empty --a crashed"
match="$(get "$out" MATCH)"
[[ "$match" == "0" ]] && ok "empty --a never matches" || bad "empty --a matched: $out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh meta/superpowers/validation/2026-09-07-commit-overlap-smoke.zsh`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Write `hooks/lib/commit-overlap.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/commit-overlap.sh — token-overlap check (session-continuity plugin).
#
# Shared by both prose copies inside commands/end-session.md: the
# backlog-verification overlap gate (item text vs. each commit subject,
# skip classify/verify below threshold) and the refresh-flow's backlog
# overlay (commit subject vs. each item, present as a close-candidate at
# or above threshold). Both are the identical tokenize + stopword-drop +
# intersection-cardinality primitive in opposite directions -- one script
# serves both, since set intersection is symmetric.
#
# This is a DIFFERENT algorithm from hooks/lib/candidate-extract.jq's
# overlap() (normalized Jaccard, threshold 0.7, no stopword list, used
# only for LEARNINGS-candidate self-dedup) -- do not conflate the two.
#
# Usage:
#   commit-overlap.sh --a="<text>" --b="<text>" [--threshold=N, default 3]
#
# Tokenizes both strings: lowercase, split on runs of non-alphanumeric
# characters, drop tokens shorter than 3 characters, drop the stopword
# list below. Prints:
#   OVERLAP=<intersection cardinality>
#   MATCH=1   if OVERLAP >= threshold
#   MATCH=0   otherwise
# Always exits 0 -- a read-only text comparison, never a reason to block
# the command that calls it.

set -uo pipefail

STOPWORDS=" the and for fix add update from with into feat chore docs primer learnings session continuity tag version release "

tokenize() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c '[:alnum:]' ' ' \
    | tr -s ' ' '\n' \
    | awk 'length($0) >= 3'
}

filter_stopwords() {
  local w
  while IFS= read -r w; do
    [[ "$STOPWORDS" == *" $w "* ]] || printf '%s\n' "$w"
  done
}

A=""; B=""; THRESHOLD=3
for arg in "$@"; do
  case "$arg" in
    --a=*)         A="${arg#*=}" ;;
    --b=*)         B="${arg#*=}" ;;
    --threshold=*) THRESHOLD="${arg#*=}" ;;
    *) : ;;
  esac
done
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || THRESHOLD=3

TOK_A="$(tokenize "$A" | filter_stopwords | sort -u)"
TOK_B="$(tokenize "$B" | filter_stopwords | sort -u)"

OVERLAP="$(comm -12 <(printf '%s\n' "$TOK_A") <(printf '%s\n' "$TOK_B") 2>/dev/null | grep -c .)"
[[ "$OVERLAP" =~ ^[0-9]+$ ]] || OVERLAP=0

printf 'OVERLAP=%d\n' "$OVERLAP"
if [[ "$OVERLAP" -ge "$THRESHOLD" ]]; then
  printf 'MATCH=1\n'
else
  printf 'MATCH=0\n'
fi
exit 0
```

Make it executable: `chmod +x hooks/lib/commit-overlap.sh`.

- [ ] **Step 4: Run the smoke test to verify it passes**

Run: `zsh meta/superpowers/validation/2026-09-07-commit-overlap-smoke.zsh`
Expected: all assertions PASS. Note the "empty `--a`" case: `grep -c .` on empty input exits 1 with count 0 — the `2>/dev/null` plus the `[[ "$OVERLAP" =~ ^[0-9]+$ ]] || OVERLAP=0` guard covers it either way, but confirm the printed `OVERLAP=0` (not a `comm`/`grep` error leaking to stdout) if this assertion fails.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/commit-overlap.sh meta/superpowers/validation/2026-09-07-commit-overlap-smoke.zsh
git commit -m "feat: add commit-overlap.sh, shared tokenize+intersection primitive"
```

---

### Task 4: Wire `commands/primer.md` to `backlog-item.sh`

**Files:**
- Modify: `commands/primer.md:113-129` (Step 2, backlog-conversion rule)
- Modify: `commands/primer.md:301-315` (Step 4 item 6, refresh-mode backlog edit)

**Interfaces:**
- Consumes: `backlog-item.sh mint <file>` → `TAG=`/`DATE=` stdout lines (Task 2). `backlog-item.sh tag-in-use <tag>` → exit code (Task 2). `backlog-item.sh renumber <file>` → exit code (Task 2). `require_script` from `hooks/lib/require-script.sh` (existing, already sourced elsewhere in this file's Step 5).

- [ ] **Step 1: Replace Step 2's backlog-conversion rule**

Find this text at `commands/primer.md:115-126` (the "**Backlog conversion rule.**" paragraph inside Step 2, item 8):

```
   **Backlog conversion rule.** The user's answer for
   `{{BACKLOG}}` is free-form prose — a list, a paragraph, however
   they typed it. Convert it into one
   `### <position>. [<tag>] [<date>]` entry per distinct item in
   `.session-continuity/BACKLOG.md`, positions numbered sequentially
   starting at 1, each minted a fresh unused 4-hex-character `<tag>`
   and stamped with today's date, trimming each to a title plus 1-3
   sentences (the same length cap every item in that file follows).
   Never paste the raw answer in as a single unstructured blob. If the
   user said "none" or skipped the question, leave the file's
   `{{BACKLOG}}` placeholder area empty (substituted per the existing
   placeholder-cleanup step below, same as any other skipped field).
```

Replace with:

```
   **Backlog conversion rule.** The user's answer for
   `{{BACKLOG}}` is free-form prose — a list, a paragraph, however
   they typed it. Convert it into one
   `### <position>. [<tag>] [<date>]` entry per distinct item in
   `.session-continuity/BACKLOG.md`, positions numbered sequentially
   starting at 1. For the tag+date on each item, use
   `hooks/lib/backlog-item.sh mint` rather than inventing one — batch
   every item's mint call into one Bash call, tracking already-minted
   tags locally so two items in the same batch can never collide before
   either is written to the file:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-item.sh" 1; then
     used=()
     for i in $(seq 1 "$N"); do   # N = number of distinct items parsed from the answer
       mint_tries=0
       while :; do
         out="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-item.sh" mint .session-continuity/BACKLOG.md)"
         tag="$(printf '%s\n' "$out" | sed -n 's/^TAG=//p')"
         if [[ -z "$tag" ]]; then
           echo "⚠️ backlog-item.sh mint produced no tag for item $i — aborting the batch."
           break 2
         fi
         [[ -n "${used[*]:-}" && " ${used[*]} " == *" $tag "* ]] || break
         mint_tries=$(( mint_tries + 1 ))
         [[ "$mint_tries" -ge 20 ]] && { echo "⚠️ mint kept colliding with this batch's own tags for item $i — aborting."; break 2; }
       done
       used+=("$tag")
       echo "ITEM_${i}_TAG=$tag"
     done
     echo "DATE=$(printf '%s\n' "$out" | sed -n 's/^DATE=//p')"
   else
     echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
   fi
   ```

   Trim each item to a title plus 1-3 sentences (the same length cap
   every item in that file follows). Never paste the raw answer in as a
   single unstructured blob. If the user said "none" or skipped the
   question, leave the file's `{{BACKLOG}}` placeholder area empty
   (substituted per the existing placeholder-cleanup step below, same as
   any other skipped field) — skip the mint loop entirely in that case.
```

- [ ] **Step 2: Replace Step 4 item 6's backlog-edit prose**

Find this text at `commands/primer.md:301-315` (Step 4, item 6):

```
6. Apply the edits to `.session-continuity/BACKLOG.md` (not the
   primer). **Before removing any item as DONE, verify it against the
   actual code** — one grep or read per load-bearing claim, even if the
   user confirms it from memory or a commit subject matched the item's
   keywords. A subject-line match does not prove the change shipped, and
   a fix landing inside an unrelated commit can leave an item reading
   OPEN when it already shipped — verify both directions, not just the
   one the candidate list surfaced. **Before deleting a closed item, grep
   the whole repo for its tag** (e.g. `\[a3f9\]`) — a hit means fix the
   referencing text first, per the identity convention in
   `.session-continuity/BACKLOG.md`'s own intro block. A new item mints
   a fresh unused hex tag and today's date; after any add/remove,
   renumber every remaining item's `<position>` to 1..N with no gaps —
   position is display order only, never a permanent reference.
```

Replace with:

```
6. Apply the edits to `.session-continuity/BACKLOG.md` (not the
   primer). **Before removing any item as DONE, verify it against the
   actual code** — one grep or read per load-bearing claim, even if the
   user confirms it from memory or a commit subject matched the item's
   keywords. A subject-line match does not prove the change shipped, and
   a fix landing inside an unrelated commit can leave an item reading
   OPEN when it already shipped — verify both directions, not just the
   one the candidate list surfaced. **Before deleting a closed item**,
   check it isn't still referenced elsewhere:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-item.sh" 1; then
     bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-item.sh" tag-in-use <tag>
     TAG_CHECK_RC=$?
   else
     echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
     TAG_CHECK_RC=2
   fi
   ```

   Branch on the exit code explicitly — do not treat "not 0" as uniformly
   safe: **0** (citations printed) means fix the referencing text first,
   per the identity convention in `.session-continuity/BACKLOG.md`'s own
   intro block, rather than deleting the item out from under a live
   cross-reference. **1** means clean — safe to delete. **2** means the
   check itself failed (bad root, `require_script` skew) — never delete
   on this outcome; tell the user the safety check couldn't run rather
   than silently proceeding as if it had passed.

   A new item mints a fresh unused hex tag and today's date:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-item.sh" 1; then
     out="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-item.sh" mint .session-continuity/BACKLOG.md)"
     NEW_TAG="$(printf '%s\n' "$out" | sed -n 's/^TAG=//p')"
     NEW_DATE="$(printf '%s\n' "$out" | sed -n 's/^DATE=//p')"
     if [[ -z "$NEW_TAG" || -z "$NEW_DATE" ]]; then
       echo "⚠️ backlog-item.sh mint produced no usable tag/date — do not write a new item this round."
     fi
   else
     echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
   fi
   ```

   Only write the new `### <position>. [<NEW_TAG>] [<NEW_DATE>] <title>`
   heading if both `NEW_TAG` and `NEW_DATE` came back non-empty. After
   any add/remove, renumber the file:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-item.sh" renumber .session-continuity/BACKLOG.md
   ```

   position is display order only, never a permanent reference.
```

- [ ] **Step 3: Run the existing session-start/primer smoke tests**

Run: `zsh meta/superpowers/validation/2026-08-12-session-start-smoke.zsh && zsh meta/superpowers/validation/2026-09-01-require-script-smoke.zsh`
Expected: both PASS unchanged — this task only edits prose in `primer.md`, no script behavior these smoke tests exercise.

- [ ] **Step 4: Commit**

```bash
git add commands/primer.md
git commit -m "refactor: primer.md's backlog mint/tag-check/renumber prose calls backlog-item.sh"
```

---

### Task 5: Wire `commands/end-session.md` to `commit-overlap.sh`

**Files:**
- Modify: `commands/end-session.md:100-112` (backlog-verification overlap gate)
- Modify: `commands/end-session.md:234-267` (refresh-flow overlay, plus the stale cross-reference at line 236)

**Interfaces:**
- Consumes: `commit-overlap.sh --a=<item text> --b=<commit subject> --threshold=3` → `OVERLAP=`/`MATCH=` stdout lines (Task 3).

- [ ] **Step 1: Replace the backlog-verification overlap gate**

Find this text at `commands/end-session.md:100-112`:

```
**Overlap gate (cost control) — run this before classifying.** Tokenize the
item (same rule as the overlay below: lowercase, split on non-alphanumeric,
drop tokens <3 chars, drop the overlay's stopword list) and compare against
each commit subject in the list computed above, tokenized the same way. If
the intersection with EVERY commit subject has cardinality <3 — nothing that
landed since the last refresh implicates this item — skip the
classify/verify steps below for this item. Assign verdict **`manual`**, cited
as `"no related commits since last refresh — not re-checked this session"`.
This is the deliberate accuracy tradeoff of the gate: an item resolved
through means that leave no matching commit subject (a manual/external fix)
won't be caught until a touching commit lands or the user mentions it
directly. Items with cardinality ≥3 against at least one commit subject
proceed to full classify/verify below.
```

Replace with:

```
**Overlap gate (cost control) — run this before classifying.** For each
item, check it against every commit subject in the list computed above
using the shared script:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/commit-overlap.sh" 1; then
  for subject in "${COMMIT_SUBJECTS[@]}"; do   # from the commit list computed above
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/commit-overlap.sh" --a="<item text>" --b="$subject"
  done
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
fi
```

Batch every item's checks into the same single Bash call this section
already uses for its classify/verify pass — do not spend one round trip
per item or per commit subject. If EVERY commit subject comes back
`MATCH=0` for an item — nothing that landed since the last refresh
implicates it — skip the classify/verify steps below for this item.
Assign verdict **`manual`**, cited as `"no related commits since last
refresh — not re-checked this session"`. This is the deliberate accuracy
tradeoff of the gate: an item resolved through means that leave no
matching commit subject (a manual/external fix) won't be caught until a
touching commit lands or the user mentions it directly. Items with at
least one `MATCH=1` proceed to full classify/verify below.
```

- [ ] **Step 2: Replace the refresh-flow overlay and fix the stale cross-reference**

Find this text at `commands/end-session.md:234-271`:

```
### Refresh flow (runs only when drift was detected)

Follow the logic in **Step 5 of `commands/primer.md`** (refresh mode):

1. Regenerate the `git log --oneline -5` block with current output.
2. If the primer has a test-counts section and the counts changed (after the 3× retry), update them to match current output.
3. **Surface commits since the last primer refresh, with backlog overlay.** Reuse the commit list already computed in the Backlog verification section above (`git log <last-primer-commit>..HEAD --oneline`) — do not recompute it. Present the subject list as candidate prompts.

   Then compute a **backlog overlay** for each subject:

   - Tokenize the subject: lowercase, split on non-alphanumeric, drop tokens of length <3, drop the stopword list below.
   - For each `### <position>. [<tag>] [<date>]` entry in `.session-continuity/BACKLOG.md`: tokenize the item text the same way, capped at the first 200 characters of the item (the heading line through everything up to the next `### ` heading or end of file; sub-bullets roll up to their parent item).
   - Match if the intersection of subject tokens and item tokens has cardinality ≥ 3.

   **Stopwords** (extend per project as needed):

   ```
   the and for fix add update from with into feat chore docs primer learnings session continuity tag version release
   ```

   **Presentation.** Render the "May close outstanding items" block when EITHER
```

Replace the `### Refresh flow` header line and its first three steps' cross-reference/overlay-computation text with:

```
### Refresh flow (runs only when drift was detected)

Steps 1-2 below mirror `commands/primer.md`'s own refresh mode (its Step
4) but run directly here — this file no longer defers the overlay
computation to `primer.md`, since it now calls the same shared script
`primer.md` calls (`hooks/lib/commit-overlap.sh`), not a copy of
`primer.md`'s prose.

1. Regenerate the `git log --oneline -5` block with current output.
2. If the primer has a test-counts section and the counts changed (after the 3× retry), update them to match current output.
3. **Surface commits since the last primer refresh, with backlog overlay.** Reuse the commit list already computed in the Backlog verification section above (`git log <last-primer-commit>..HEAD --oneline`) — do not recompute it. Present the subject list as candidate prompts.

   Then compute a **backlog overlay** for each subject, using the same
   shared script as the overlap gate above (each item's text capped at
   the first 200 characters — the heading line through everything up to
   the next `### ` heading or end of file; sub-bullets roll up to their
   parent item):

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
   if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/commit-overlap.sh" 1; then
     for subject in "${COMMIT_SUBJECTS[@]}"; do
       for item_text in "${BACKLOG_ITEM_TEXTS[@]}"; do   # first 200 chars each
         bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/commit-overlap.sh" --a="$subject" --b="$item_text"
       done
     done
   else
     echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
   fi
   ```

   Batch every subject×item check into one Bash call. A subject/item pair
   matches when `commit-overlap.sh` prints `MATCH=1` — the script owns
   the stopword list and the threshold (3) now; do not maintain a second
   copy of either here.

   **Presentation.** Render the "May close outstanding items" block when EITHER
```

Leave everything from `**Presentation.**` onward (lines 254-271 in the original) unchanged — only the header, the "Follow the logic..." sentence, and the tokenize/stopword/match-rule bullets above it are replaced.

- [ ] **Step 3: Verify the old prose tokenize rules are gone**

Run: `grep -n "drop the overlay's stopword\|Tokenize the subject: lowercase\|Step 5 of \`commands/primer.md\`" commands/end-session.md`
Expected: no output — both inline stopword-list literals and the stale cross-reference are gone, replaced by calls to `commit-overlap.sh`.

- [ ] **Step 4: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session.md's two overlap prose copies call commit-overlap.sh"
```

---

### Task 6: Docs, backlog, changelog, version bump

**Files:**
- Modify: `meta/superpowers/specs/2026-09-02-determinism-program-design.md:191-199`
- Modify: `.session-continuity/BACKLOG.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Collapse the design doc's Phase 5 entry to a pointer**

Find `meta/superpowers/specs/2026-09-02-determinism-program-design.md:191-199`:

```
**Phase 5 `#42` — backlog mechanics.** Two scripts used by both `primer.md` and
`end-session.md`: item bookkeeping (mint a 4-hex tag with a uniqueness grep,
stamp the date, renumber positions 1..N, grep the repo for a tag before
deletion) and the overlap gate (tokenize, drop short tokens and stopwords,
intersect with commit subjects, threshold at 3). The overlap algorithm
currently exists as two prose copies that can drift, and
`candidate-extract.jq:96-107` already has a working token-overlap
implementation to lift. Set-intersection cardinality is a task models get
wrong silently.
```

Replace with (matching how Phase 3's entry was collapsed after it shipped):

```
**Phase 5 `#42` — backlog mechanics.** Shipped. Plan:
`meta/superpowers/plans/2026-09-07-determinism-phase-5-backlog-mechanics.md`.
Also fixed `candidate-extract.jq`'s `overlap()` (`#40`) — a related but
distinct defect the plan scoped separately, since it's a different
algorithm (normalized Jaccard) from this phase's intersection-cardinality
overlap gate.
```

- [ ] **Step 2: Update `.session-continuity/BACKLOG.md`**

Mark both `#42` and `#40` closed, following this file's own "closed stub" convention (matching how `[a17f]` and `[52dc]` were marked in this same session):

```
### 6. #40 — closed. Fixed in `<task-1-sha>`.

### 12. #42 — closed. Fixed in `<task-2-sha>`/`<task-3-sha>`/`<task-4-sha>`/`<task-5-sha>` (v<new-version>).
```

Fill in the real short SHAs from Tasks 1-5's commits (Step 5's is the last one — retrieve all five with `git log --oneline -8` once Task 5 lands) and the real position numbers current at edit time (re-check with `grep -n '^### ' .session-continuity/BACKLOG.md` — positions shift as earlier items in this file get closed across sessions).

- [ ] **Step 3: Full regression pass**

Run every smoke test in `meta/superpowers/validation/`:

```bash
for f in meta/superpowers/validation/*.zsh; do
  echo "=== $f ==="
  zsh "$f" || echo "FAILED: $f"
done
```

Expected: every file reports `0 failed`. Pay particular attention to `2026-09-02-render-smoke.zsh` and `2026-09-02-count-entries-smoke.zsh` — both parse `.session-continuity/BACKLOG.md`'s live item count, which Task 6 Step 2 changes.

- [ ] **Step 4: Add a CHANGELOG entry**

Add to the top of `CHANGELOG.md`, above the existing `## [0.28.0]` entry:

```markdown
## [0.29.0] — 2026-09-07

### Fixed
- **`candidate-extract.jq`'s `overlap()` is now a symmetric, multiplicity-free Jaccard.** The prior formula's numerator counted one side's title words with multiplicity while the denominator was the deduped union — an asymmetric mismatch that scored short/similar titles above the 0.7 dedup threshold when they shouldn't merge (`vitest`/`jest` scored 0.909), and let two distinct retry-bursts sharing the heuristic's title-template suffix over-merge (0.722). A new `dedup_key` strips that shared suffix before scoring. Closes backlog item #40.

### Changed
- **New `hooks/lib/backlog-item.sh` (`mint`/`tag-in-use`/`renumber`) and `hooks/lib/commit-overlap.sh` replace hand-executed prose in `primer.md` and `end-session.md`.** Backlog tag minting (with a real uniqueness check), the before-delete tag-reference grep, and position renumbering were previously instructions the model followed by hand; the commit-overlap gate that decides whether an outstanding item needs re-verification, and the refresh flow's backlog overlay, existed as two separate prose copies of the same tokenize/stopword/intersection-cardinality logic inside `end-session.md`. Both are now one call each to a tested script. Closes backlog item #42 (Determinism Phase 5).
```

Bump `.claude-plugin/plugin.json`'s `"version"` field from `"0.28.0"` to `"0.29.0"`.

- [ ] **Step 5: Commit**

```bash
git add meta/superpowers/specs/2026-09-02-determinism-program-design.md .session-continuity/BACKLOG.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "chore: bump to 0.29.0 — Phase 5 backlog mechanics and the #40 overlap fix"
```
