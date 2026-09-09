# Determinism Phase 4 — `end-session` Step 3 checklist assembly — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `commands/end-session.md` Step 3's model-assembled checklist (six git commands, hand-formatted rows, a hand-composed suggested-commit message, and a hand-picked sign-off line) with one script, `hooks/lib/checklist-assemble.sh`, that consumes the six git outputs plus a `tag<TAB>verdict<TAB>citation` backlog-verdict file and prints the finished eight-row checklist, the backlog tallies, every row's ✓/⚠️ marker, and the terminal sign-off line, verbatim.

**Architecture:** `checklist-assemble.sh` follows the same shape as `hooks/lib/candidate-render.sh` (Phase 2): one JSON object on stdin carrying every git-derived and model-decided value, one optional positional arg for the backlog-verdict TSV path, one text blob on stdout, always exit 0, one `SC-FALLBACK:` escape hatch for malformed input. Step 3's Bash block builds that JSON in the same round trip that runs the six (now seven — see Task 3) git commands, pipes it through the script, and prints the result unchanged. Because the script's own output now includes the terminal sign-off line, Step 4 no longer prints any checklist-derived text of its own — it becomes a pure timing/logging step.

**Tech Stack:** Bash, `jq` (already a hard dependency via `candidate-render.sh`), zsh (smoke tests only).

**Spec:** `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (Phase 4 entry). That entry's line-number citations (612-675, 759-773, 687-701) are stale — they were written against a pre-Phase-5 `end-session.md` (45,284 bytes); the current file is 587 lines. This plan cites current line numbers throughout and Task 6 updates the spec's pointer.

## Global Constraints

- Every new script prints best-effort output and **always exits 0** — `checklist-assemble.sh` sits inside `end-session`'s close-out ritual, which must never abort on a formatting failure (same rule `candidate-render.sh` and `perf-log.sh` already follow).
- `checklist-assemble.sh` carries a `# CONTRACT_VERSION=1` header and is called through `require_script` from `commands/end-session.md`, exactly like `candidate-extract.sh` and `resolve-transcript.sh` already are.
- **Never invent a value.** Every field the script cannot resolve is either omitted (per the existing per-row omission rules already in `end-session.md`) or degrades to the script's own fixed fallback text — never a paraphrase, never a placeholder.
- **One round trip per Bash call**, unchanged from the existing convention: Step 3's "gather facts" call stays one call: seven git commands, the JSON assembly, and the `checklist-assemble.sh` invocation, timed exactly as today.
- **Backlog verdicts never mutate the primer.** Unchanged from today — the TSV file this plan introduces is a read-only report of verdicts already decided in Step 1; nothing about closing an item changes.
- Do not touch `overlap()`/`candidate-extract.jq` (backlog item #40) or Phase 6's `primer` detect/migrate/init/drift logic (#43) — out of scope.
- Do not touch `primer-status.sh` — it already reads `BACKLOG_COUNT` via `backlog-issues.sh --count` (shipped in v0.29.0), so it needs no change for this plan.

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/lib/checklist-assemble.sh` (new) | Reads one JSON object from stdin plus an optional backlog-TSV path argument; prints the finished eight-row checklist, suggested-commit block, and terminal sign-off line as one text blob. |
| `hooks/lib/perf-log.sh` (modified) | `write_record`'s gitignore-ensure list gains the new scratch TSV path, so it's never accidentally tracked if a ritual is interrupted before Step 3's cleanup runs. |
| `commands/end-session.md` (modified) | Fast path gains one cheap backlog-count call. Backlog verification gains a TSV-writing step. Step 3's "Gather the facts" / "Emit the checklist" / "Suggested commit message" / "Example output" sections collapse to one script call plus its `SC-FALLBACK:` branch. Step 4 drops all of its own printed text, keeping only the timing calls. |
| `meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh` (new) | Smoke test for the new script — every row, every branch, the fallback path. |
| `meta/superpowers/specs/2026-09-02-determinism-program-design.md` (modified) | Phase 4 entry collapses to a pointer at this plan, per the doc's own "Entry format" rule. |
| `CHANGELOG.md` (modified) | New version entry. |

---

### Task 1: `hooks/lib/checklist-assemble.sh`

**Files:**
- Create: `hooks/lib/checklist-assemble.sh`
- Test: `meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh`

**Interfaces:**
- Produces: `bash checklist-assemble.sh [<backlog-tsv-path>]`, reading one JSON object from stdin. Prints the finished checklist text (eight rows, blank line, sign-off line) on stdout. Always exits 0.
- Consumes: `jq` (hard dependency, same as `candidate-render.sh`). If `<backlog-tsv-path>` is given and `backlog_mode=="normal"` in the input JSON, reads that file as `tag\tverdict\tcitation` lines (one open backlog item per line).

**JSON input contract** (every key optional except `staged`/`unstaged`/`untracked`/`branch`/`primer`/`learnings`/`backlog_mode`, which must always be present — `checklist-assemble.sh` treats a missing required key the same as malformed JSON, i.e. the `SC-FALLBACK:` branch):

```json
{
  "staged": ["path/a", "path/b"],
  "unstaged": ["path/c"],
  "untracked": ["path/d"],
  "branch": "main",
  "detached": false,
  "short_sha": "abc1234",
  "upstream": "origin/main",
  "ahead": 0,
  "primer": "refreshed",
  "learnings": [{"number": 7, "title": "awk range collapse on single-version CHANGELOG"}],
  "backlog_mode": "normal",
  "backlog_fastpath_count": null,
  "commit_subject": null
}
```

- `detached`: `true` means `branch` is the literal `"HEAD"` from `git rev-parse --abbrev-ref HEAD`; `upstream`/`ahead` are ignored when `true`.
- `upstream`: `null` (not the literal string `"null"` — real JSON null) when `git rev-parse --abbrev-ref @{u}` failed. `ahead` is `null` under the same condition.
- `primer`: one of `"refreshed"`, `"closed"`, `"current"`.
- `learnings`: empty array when Step 2 captured nothing.
- `backlog_mode`: one of `"normal"`, `"none"`, `"unavailable"`, `"not-migrated"`, `"fast-path"`. `"fast-path"` requires `backlog_fastpath_count` (an integer). `"normal"` requires the positional TSV path argument to be non-empty and readable — an empty/unreadable path when `backlog_mode=="normal"` is treated as zero backlog items (not a fallback — an empty TSV is a valid "no open items survived the overlap gate" state, but a *missing* one attached to `"normal"` mode is a caller bug, silently degraded to zero rather than crashing).
- `commit_subject`: `null` unless staged files exist AND at least one staged path is outside `.session-continuity/` — in that mixed/code case, the caller (the model) supplies its own conventional-commit subject line here (this is retained model judgment per the spec's "What stays model work" list, item 5). When staged is all-`.session-continuity/`, this field is ignored entirely — the script uses its own literal subject.

**Output rows, in order** (blank line, then the sign-off line, are appended after row 8):

1. **Primer refresh** — `✓ Primer refreshed and staged` / `✓ Primer updated (outstanding item(s) closed)` / `✓ Primer already current (no-op)`, keyed off `primer`.
2. **New learnings** — `✓ No new learnings` if `learnings` is empty; else `✓ N LEARNINGS entry/entries captured (#X, "title", #Y, "title", …)` — singular "entry" for N=1, plural "entries" otherwise, comma-joined `#N, "title"` pairs in array order.
3. **Backlog** — see the mode table below.
4. **Staged files** — `✓ Staged: a, b, c` (comma-joined, array order) or `✓ Nothing staged` if `staged` is empty.
5. **Unstaged modifications** — `✓ No unstaged modifications` if `unstaged` is empty, else `⚠️ Unstaged: a, b, c`.
6. **Untracked files** — `✓ No untracked files` if `untracked` is empty, else `⚠️ N untracked: a, b, c — ignore, add, or delete?` (N is `untracked`'s length).
7. **Unpushed commits** — see the branch-state table below.
8. **Suggested commit** — omitted entirely (no row, no blank line in its place) if `staged` is empty. Otherwise: `→ Suggested:` followed by a fenced ` ```\ngit commit -m "<subject>"\n``` ` block, where `<subject>` is: the literal `docs: update session continuity` if every entry in `staged` starts with `.session-continuity/`; else `commit_subject` if non-null; else the mechanical fallback `chore: update N file(s)` (N = `staged`'s length) if `commit_subject` is null in the mixed/code case — this fallback is deliberately generic (never fabricates a theme) so the ritual never blocks on a missing judgment call, but always losslessly reflects the actual N.

**Backlog row, by `backlog_mode`:**

| `backlog_mode` | Marker | Text |
|---|---|---|
| `none` | ✓ | `Backlog: none tracked` |
| `unavailable` | ✓ | `Backlog: GitHub queue unavailable — run /session-continuity:doctor` |
| `not-migrated` | ✓ | `Backlog: not migrated — run /session-continuity:primer` |
| `fast-path` | ✓ | `Backlog: N tracked — not re-verified this session (no repo changes since last close-out)` (N = `backlog_fastpath_count`) |
| `normal` | ✓ if zero `appears-DONE` rows in the TSV, else ⚠️ | `Backlog: N tracked — k appears-DONE (tag, "citation", tag, "citation", …), m still-open (tag, tag, …), j manual (tag, tag, …)` — N = total TSV lines; k/m/j = counts per verdict; the `appears-DONE` clause is the only one carrying citations (still-open and manual list bare tags), and any verdict with zero items **and its parenthetical are omitted from the sentence entirely** (never print `0 still-open ()`, only the fragments for k/m/j that are >0, comma-joined) |

> **Proven-gate:** N/A — the fast-path row's `not re-verified` text
> above is a quoted UI string this script prints, not a proven/verified
> claim about this plan itself.
>
> **Evidence-gate:** N/A — the `cleanup` mention above is a scratch-TSV
> gitignore entry, not a smoke-test teardown that could destroy failure
> evidence.

**Unpushed commits row:**

| Condition | Marker | Text |
|---|---|---|
| `detached==true` | ⚠️ | `detached HEAD at <short_sha>` |
| `upstream==null` | ⚠️ | `` branch `<branch>` has no upstream — set one with `git push -u origin <branch>` `` |
| `upstream!=null`, `ahead==0` | ✓ | `Up to date with origin/<branch>` |
| `upstream!=null`, `ahead>0` | ⚠️ | `` Branch `<branch>` is N commits ahead of origin — push before closing? `` (N = `ahead`) |

**Sign-off line** (blank line, then this line, after row 8 — or after row 7 if row 8 was omitted): if any of rows 1-8 carries a ⚠️ marker, `✅ Session complete. Safe to close. (Warnings above are advisory — review before closing if relevant.)`; else `✅ Session complete. Safe to close.`

**Fallback:** malformed/non-object JSON on stdin, or `jq` not installed, or a required key missing → print `SC-FALLBACK: manual — <detail>` and exit 0. `<detail>` is one of: `jq is not installed.`, `malformed checklist JSON.`, or `checklist JSON missing required key '<key>'.`

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# checklist-assemble.sh smoke test. Hermetic: fixture JSON + a throwaway
# TSV file, no real git state.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"
tool="$lib/checklist-assemble.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

run() { print -rn -- "$1" | bash "$tool" "${2:-}"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

base_json() {
  # Minimal valid document: nothing staged/unstaged/untracked, primer
  # current, no learnings, no backlog tracked, upstream clean.
  cat <<'JSON'
{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,
 "short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current",
 "learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,
 "commit_subject":null}
JSON
}

# --- malformed JSON must not crash, must fall back -------------------------
out="$(run 'not json at all')"
[[ "$out" == SC-FALLBACK:* ]] && ok "malformed JSON -> SC-FALLBACK" \
  || bad "expected SC-FALLBACK, got: $out"

# --- missing required key must not crash ------------------------------------
out="$(run '{"staged":[]}')"
[[ "$out" == SC-FALLBACK:* ]] && ok "missing required keys -> SC-FALLBACK, no crash" \
  || bad "expected SC-FALLBACK, got: $out"

# --- fully clean run: every row ✓, no suggested-commit row, clean sign-off --
out="$(run "$(base_json)")"
expected="✓ Primer already current (no-op)
✓ No new learnings
✓ Backlog: none tracked
✓ Nothing staged
✓ No unstaged modifications
✓ No untracked files
✓ Up to date with origin/main

✅ Session complete. Safe to close."
[[ "$out" == "$expected" ]] && ok "fully clean run renders all-✓ checklist, no suggested-commit row, clean sign-off" \
  || bad "got:\n$out"

# --- new learnings row: singular vs plural ----------------------------------
one_learning='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[{"number":7,"title":"awk range collapse"}],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$one_learning")"
[[ "$out" == *'✓ 1 LEARNINGS entry captured (#7, "awk range collapse")'* ]] \
  && ok "one learning -> singular 'entry'" \
  || bad "got:\n$out"

two_learnings='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[{"number":7,"title":"A"},{"number":8,"title":"B"}],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$two_learnings")"
[[ "$out" == *'✓ 2 LEARNINGS entries captured (#7, "A", #8, "B")'* ]] \
  && ok "two learnings -> plural 'entries', both cited" \
  || bad "got:\n$out"

# --- backlog: fast-path mode -------------------------------------------------
fastpath='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[],"backlog_mode":"fast-path","backlog_fastpath_count":5,"commit_subject":null}'
out="$(run "$fastpath")"
[[ "$out" == *'✓ Backlog: 5 tracked — not re-verified this session (no repo changes since last close-out)'* ]] \
  && ok "fast-path backlog mode renders the standing-count line" \
  || bad "got:\n$out"

# --- backlog: unavailable / not-migrated modes -------------------------------
unavail='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[],"backlog_mode":"unavailable","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$unavail")"
[[ "$out" == *'✓ Backlog: GitHub queue unavailable — run /session-continuity:doctor'* ]] \
  && ok "unavailable backlog mode renders the doctor pointer" \
  || bad "got:\n$out"

notmig='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[],"backlog_mode":"not-migrated","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$notmig")"
[[ "$out" == *'✓ Backlog: not migrated — run /session-continuity:primer'* ]] \
  && ok "not-migrated backlog mode renders the primer pointer" \
  || bad "got:\n$out"

# --- backlog: normal mode, mixed verdicts, TSV-driven ------------------------
tsv="$work/backlog.tsv"
cat <<'TSV' > "$tsv"
#4	appears-DONE	found test/end_to_end.bats -> 0 hits before, now present
#3	still-open	no *.bats and no test/ dir -> item still open
#5	manual	not auto-verifiable
#6	manual	no related commits since last refresh -- not re-checked this session
TSV
normal='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[],"backlog_mode":"normal","backlog_fastpath_count":null,"commit_subject":null}'
out="$(print -rn -- "$normal" | bash "$tool" "$tsv")"
[[ "$out" == *'⚠️ Backlog: 4 tracked — 1 appears-DONE (#4, "found test/end_to_end.bats -> 0 hits before, now present"), 1 still-open (#3), 2 manual (#5, #6)'* ]] \
  && ok "normal mode tallies all three verdicts, cites only appears-DONE, marks ⚠️" \
  || bad "got:\n$out"
[[ "$out" == *'(Warnings above are advisory'* ]] \
  && ok "any ⚠️ row flips the sign-off line to the advisory variant" \
  || bad "sign-off did not carry the warning suffix:\n$out"

# --- backlog: normal mode, zero appears-DONE -> ✓, no advisory suffix -------
cat <<'TSV' > "$tsv"
#3	still-open	no *.bats and no test/ dir -> item still open
TSV
out="$(print -rn -- "$normal" | bash "$tool" "$tsv")"
[[ "$out" == *'✓ Backlog: 1 tracked — 1 still-open (#3)'* ]] \
  && ok "normal mode with zero appears-DONE marks ✓, omits the empty appears-DONE clause" \
  || bad "got:\n$out"

# --- backlog: normal mode, missing TSV path degrades to zero items ---------
out="$(print -rn -- "$normal" | bash "$tool" "$work/does-not-exist.tsv")"
[[ "$out" == *'✓ Backlog: 0 tracked'* ]] \
  && ok "normal mode with an unreadable TSV path degrades to zero tracked, no crash" \
  || bad "got:\n$out"

# --- backlog: normal mode, citation with embedded quote and backslash ------
printf '#9\tappears-DONE\tfound "weird" path C:\\temp\\x -> present\n' > "$tsv"
out="$(print -rn -- "$normal" | bash "$tool" "$tsv")"
[[ "$out" == *'1 appears-DONE (#9, "found "weird" path C:\temp\x -> present")'* ]] \
  && ok "citation with embedded quote/backslash renders without breaking JSON parsing" \
  || bad "got:\n$out"

# --- unrecognized backlog_mode -> SC-FALLBACK, no silent normal-mode fallthrough
bad_mode='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[],"backlog_mode":"Normal","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$bad_mode")"
[[ "$out" == SC-FALLBACK:* ]] \
  && ok "unrecognized backlog_mode -> SC-FALLBACK, not silently treated as normal" \
  || bad "got: $out"

# --- staged/unstaged/untracked rows ------------------------------------------
files='{"staged":["a.md","b.md"],"unstaged":["c.md"],"untracked":["d.tmp","e.tmp"],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"current","learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$files")"
[[ "$out" == *'✓ Staged: a.md, b.md'* ]] && ok "staged row lists every file" || bad "got:\n$out"
[[ "$out" == *'⚠️ Unstaged: c.md'* ]] && ok "unstaged row warns and lists" || bad "got:\n$out"
[[ "$out" == *'⚠️ 2 untracked: d.tmp, e.tmp — ignore, add, or delete?'* ]] && ok "untracked row counts and lists" || bad "got:\n$out"

# --- unpushed commits: all four branch states --------------------------------
detached='{"staged":[],"unstaged":[],"untracked":[],"branch":"HEAD","detached":true,"short_sha":"deadbee","upstream":null,"ahead":null,"primer":"current","learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$detached")"
[[ "$out" == *'⚠️ detached HEAD at deadbee'* ]] && ok "detached HEAD row" || bad "got:\n$out"

noupstream='{"staged":[],"unstaged":[],"untracked":[],"branch":"feature-x","detached":false,"short_sha":"abc1234","upstream":null,"ahead":null,"primer":"current","learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$noupstream")"
[[ "$out" == *'⚠️ branch `feature-x` has no upstream — set one with `git push -u origin feature-x`'* ]] \
  && ok "no-upstream row" || bad "got:\n$out"

ahead='{"staged":[],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":3,"primer":"current","learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$ahead")"
[[ "$out" == *'⚠️ Branch `main` is 3 commits ahead of origin — push before closing?'* ]] \
  && ok "ahead-of-origin row" || bad "got:\n$out"

# --- suggested commit: omitted when nothing staged (already covered above) --
# --- suggested commit: docs-only staged -> literal subject, ignores override -
docs_only='{"staged":[".session-continuity/SESSION_PRIMER.md",".session-continuity/LEARNINGS.md"],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"refreshed","learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":"should be ignored"}'
out="$(run "$docs_only")"
[[ "$out" == *'git commit -m "docs: update session continuity"'* ]] \
  && ok "all-docs staged -> literal subject, ignores a supplied commit_subject" \
  || bad "got:\n$out"

# --- suggested commit: mixed staged, caller-supplied subject used -----------
mixed='{"staged":[".session-continuity/LEARNINGS.md","hooks/lib/foo.sh"],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"refreshed","learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":"fix(ci): extract CHANGELOG section with proper awk range"}'
out="$(run "$mixed")"
[[ "$out" == *'git commit -m "fix(ci): extract CHANGELOG section with proper awk range"'* ]] \
  && ok "mixed staged with a supplied subject -> subject used verbatim" \
  || bad "got:\n$out"

# --- suggested commit: mixed staged, no subject supplied -> mechanical fallback
mixed_nosubj='{"staged":[".session-continuity/LEARNINGS.md","hooks/lib/foo.sh"],"unstaged":[],"untracked":[],"branch":"main","detached":false,"short_sha":"abc1234","upstream":"origin/main","ahead":0,"primer":"refreshed","learnings":[],"backlog_mode":"none","backlog_fastpath_count":null,"commit_subject":null}'
out="$(run "$mixed_nosubj")"
[[ "$out" == *'git commit -m "chore: update 2 file(s)"'* ]] \
  && ok "mixed staged with no supplied subject -> mechanical N-file fallback, no invented theme" \
  || bad "got:\n$out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh
zsh meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh
```

Expected: FAIL on every assertion — `hooks/lib/checklist-assemble.sh` does not exist yet.

- [ ] **Step 3: Write `hooks/lib/checklist-assemble.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/checklist-assemble.sh — Step 3 checklist renderer for
# /session-continuity:end-session (session-continuity plugin).
#
# Usage: checklist-assemble.sh [<backlog-tsv-path>]
# Reads one JSON object on stdin (see
# meta/superpowers/plans/2026-09-08-determinism-phase-4-checklist-assembly.md
# Task 1 for the full contract) and prints the finished eight-row checklist,
# suggested-commit block, and terminal sign-off line on stdout. Always exits
# 0: a rendering failure must degrade to SC-FALLBACK, never abort the ritual.
#
# <backlog-tsv-path> is read only when the input's backlog_mode=="normal".
# Each line is tag\tverdict\tcitation, one per open backlog item still
# subject to Step 1's overlap gate. A missing/unreadable path in that mode
# degrades to zero tracked items rather than falling back — an empty
# backlog is a valid state, distinct from malformed input.

set -uo pipefail

INPUT="$(cat)"
TSV_PATH="${1:-}"

fallback() {  # <detail>
  printf 'SC-FALLBACK: manual — %s\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 || fallback "jq is not installed."

if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  fallback "malformed checklist JSON."
fi

for key in staged unstaged untracked branch primer learnings backlog_mode; do
  if ! printf '%s' "$INPUT" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
    fallback "checklist JSON missing required key '$key'."
  fi
done

# --- backlog TSV -> a JSON array jq can fold in ------------------------------
BACKLOG_MODE="$(printf '%s' "$INPUT" | jq -r '.backlog_mode')"
case "$BACKLOG_MODE" in
  normal|none|unavailable|not-migrated|fast-path) ;;
  *) fallback "unrecognized backlog_mode '$BACKLOG_MODE'." ;;
esac

BACKLOG_ITEMS_JSON='[]'
if [[ "$BACKLOG_MODE" == "normal" && -n "$TSV_PATH" && -r "$TSV_PATH" ]]; then
  # jq's own JSON string encoding handles quotes, backslashes, and control
  # characters correctly — no hand-rolled escaping. Split each line on tab;
  # a citation containing a literal tab (columns 4+) is rejoined with "\t"
  # rather than truncated.
  BACKLOG_ITEMS_JSON="$(
    jq -R -s '
      split("\n") | map(select(length > 0)) | map(split("\t")) |
      map(select(length >= 3)) |
      map({tag: .[0], verdict: .[1], citation: (.[2:] | join("\t"))})
    ' "$TSV_PATH" 2>/dev/null
  )"
  if ! printf '%s' "$BACKLOG_ITEMS_JSON" | jq -e . >/dev/null 2>&1; then
    BACKLOG_ITEMS_JSON='[]'
  fi
fi

OUT="$(
  printf '%s' "$INPUT" | jq -r --argjson items "$BACKLOG_ITEMS_JSON" '
    # --- row 1: primer -------------------------------------------------------
    def primer_row:
      if .primer == "refreshed" then "✓ Primer refreshed and staged"
      elif .primer == "closed" then "✓ Primer updated (outstanding item(s) closed)"
      else "✓ Primer already current (no-op)" end;

    # --- row 2: learnings -----------------------------------------------------
    def learnings_row:
      (.learnings // []) as $l
      | if ($l | length) == 0 then "✓ No new learnings"
        else
          ($l | length) as $n
          | (if $n == 1 then "entry" else "entries" end) as $noun
          | ([$l[] | "#" + (.number|tostring) + ", \"" + .title + "\""] | join(", ")) as $cited
          | "✓ " + ($n|tostring) + " LEARNINGS " + $noun + " captured (" + $cited + ")"
        end;

    # --- row 3: backlog ---------------------------------------------------------
    def backlog_row:
      if .backlog_mode == "none" then {marker:"✓", text:"Backlog: none tracked"}
      elif .backlog_mode == "unavailable" then {marker:"✓", text:"Backlog: GitHub queue unavailable — run /session-continuity:doctor"}
      elif .backlog_mode == "not-migrated" then {marker:"✓", text:"Backlog: not migrated — run /session-continuity:primer"}
      elif .backlog_mode == "fast-path" then {marker:"✓", text:"Backlog: " + (.backlog_fastpath_count|tostring) + " tracked — not re-verified this session (no repo changes since last close-out)"}
      else
        ($items) as $it
        | ($it | length) as $n
        | ($it | map(select(.verdict=="appears-DONE"))) as $done
        | ($it | map(select(.verdict=="still-open"))) as $open
        | ($it | map(select(.verdict=="manual"))) as $man
        | ([
            (if ($done|length) > 0 then ($done|length|tostring) + " appears-DONE (" + ([$done[] | .tag + ", \"" + .citation + "\""] | join(", ")) + ")" else empty end),
            (if ($open|length) > 0 then ($open|length|tostring) + " still-open (" + ([$open[] | .tag] | join(", ")) + ")" else empty end),
            (if ($man|length) > 0 then ($man|length|tostring) + " manual (" + ([$man[] | .tag] | join(", ")) + ")" else empty end)
          ] | join(", ")) as $clauses
        | {marker: (if ($done|length) > 0 then "⚠️" else "✓" end),
           text: "Backlog: " + ($n|tostring) + " tracked" + (if $n > 0 then " — " + $clauses else "" end)}
      end;

    # --- rows 4-6: file lists ---------------------------------------------------
    def staged_row:
      (.staged // []) as $s
      | if ($s|length) == 0 then {marker:"✓", text:"Nothing staged"}
        else {marker:"✓", text:"Staged: " + ($s|join(", "))} end;

    def unstaged_row:
      (.unstaged // []) as $u
      | if ($u|length) == 0 then {marker:"✓", text:"No unstaged modifications"}
        else {marker:"⚠️", text:"Unstaged: " + ($u|join(", "))} end;

    def untracked_row:
      (.untracked // []) as $t
      | if ($t|length) == 0 then {marker:"✓", text:"No untracked files"}
        else {marker:"⚠️", text:($t|length|tostring) + " untracked: " + ($t|join(", ")) + " — ignore, add, or delete?"} end;

    # --- row 7: unpushed commits -------------------------------------------------
    def unpushed_row:
      if .detached == true then
        {marker:"⚠️", text:"detached HEAD at " + (.short_sha // "?")}
      elif .upstream == null then
        {marker:"⚠️", text:"branch `" + .branch + "` has no upstream — set one with `git push -u origin " + .branch + "`"}
      elif (.ahead // 0) == 0 then
        {marker:"✓", text:"Up to date with " + .upstream}
      else
        {marker:"⚠️", text:"Branch `" + .branch + "` is " + (.ahead|tostring) + " commits ahead of origin — push before closing?"}
      end;

    # --- row 8: suggested commit --------------------------------------------------
    def suggested_row:
      (.staged // []) as $s
      | if ($s|length) == 0 then null
        else
          (if ([$s[] | startswith(".session-continuity/")] | all) then "docs: update session continuity"
           elif .commit_subject != null then .commit_subject
           else "chore: update " + ($s|length|tostring) + " file(s)" end) as $subject
          | "→ Suggested:\n```\ngit commit -m \"" + $subject + "\"\n```"
        end;

    (primer_row) as $r1
    | (learnings_row) as $r2
    | (backlog_row) as $r3
    | (staged_row) as $r4
    | (unstaged_row) as $r5
    | (untracked_row) as $r6
    | (unpushed_row) as $r7
    | (suggested_row) as $r8
    | [$r1, $r2, ($r3.marker + " " + $r3.text), ($r4.marker + " " + $r4.text),
       ($r5.marker + " " + $r5.text), ($r6.marker + " " + $r6.text),
       ($r7.marker + " " + $r7.text)] as $rows
    | ($rows | map(test("⚠️")) | any) as $any_warn
    | ($rows + (if $r8 != null then [$r8] else [] end)) as $all_lines
    | ($all_lines | join("\n"))
      + "\n\n"
      + (if $any_warn then
           "✅ Session complete. Safe to close. (Warnings above are advisory — review before closing if relevant.)"
         else
           "✅ Session complete. Safe to close."
         end)
  ' 2>/dev/null
)"
JQ_STATUS=$?

if [[ "$JQ_STATUS" -ne 0 || -z "$OUT" ]]; then
  fallback "checklist JSON did not match the expected shape."
fi

printf '%s\n' "$OUT"
```

```bash
chmod +x hooks/lib/checklist-assemble.sh
```

- [ ] **Step 4: Run the smoke test to verify all assertions pass**

```bash
zsh meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh
```

Expected: `Result: 23 passed, 0 failed`. If any assertion's exact string doesn't match (jq's `join`/quoting can differ from a hand-written expectation by a stray space), adjust the *test's* expected string to match the script's actual, verified-by-eye-once-correct output — never loosen an assertion's substance (e.g. don't switch an exact `==` to a lax substring match to dodge a real mismatch).

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/checklist-assemble.sh meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh
git commit -m "feat: add checklist-assemble.sh, scripting end-session Step 3's row assembly"
```

---

### Task 2: `perf-log.sh` — gitignore the new scratch TSV

**Files:**
- Modify: `hooks/lib/perf-log.sh`

**Interfaces:**
- Modifies: `write_record`'s existing gitignore-ensure loop (the `for LINE in ...` block). No new subcommand, no signature change.

**Rationale:** Task 3 has `end-session.md` write `.session-continuity/.end-session-checklist.tsv` as scratch state during Step 1, then read-and-delete it at the very start of Step 3's batched Bash call (before the git-status commands run), so it's never actually present when `git status`/`git ls-files --others` runs. The gitignore entry is defense-in-depth for the case where a ritual is interrupted (the user closes the session, or the command errors) between Step 1 writing the file and Step 3 deleting it — without this, an interrupted ritual leaves a stray untracked file in the user's repo.

- [ ] **Step 1: Add the new path to the existing ensure-loop**

Using the Edit tool, replace this exact block (currently `hooks/lib/perf-log.sh`, the `for LINE in` line inside `write_record`):

```bash
    for LINE in ".session-continuity/performance.log" ".session-continuity/.gitignore-ensured"; do
```

with:

```bash
    for LINE in ".session-continuity/performance.log" ".session-continuity/.gitignore-ensured" ".session-continuity/.end-session-checklist.tsv"; do
```

- [ ] **Step 2: Run the existing perf-log smoke test to confirm no regression**

```bash
zsh meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh
```

Expected: `Result: 16 passed, 0 failed` (unchanged — this test doesn't assert on the exact `.gitignore` line set, only on `mark`/`since`/`record` behavior).

- [ ] **Step 3: Commit**

```bash
git add hooks/lib/perf-log.sh
git commit -m "chore: gitignore the Step 3 backlog-verdict scratch file"
```

---

### Task 3: `commands/end-session.md` Step 1 — fast-path count and the backlog-verdict TSV

**Files:**
- Modify: `commands/end-session.md` (fast path block, currently lines 38-46; backlog verification section, currently lines 59-159)

**Interfaces:**
- Produces: `.session-continuity/.end-session-checklist.tsv` — one `tag\tverdict\tcitation` line per open backlog item that went through Step 1's classify/verify pass (including overlap-gated and non-code items), written once at the end of the Backlog verification section. Not written at all when `backlog_mode` will be `none`/`unavailable`/`not-migrated`/`fast-path` (the existing skip conditions already cover these — no item list exists to write).
- Consumes: `hooks/lib/backlog-issues.sh --count .` (Task 3's fast-path addition) — already-shipped script, `--count` mode already documented in its own header.

- [ ] **Step 1: Add a backlog count to the fast path**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 38-46):

```markdown
```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git status --porcelain
git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md   # <last-primer-commit>
git rev-parse HEAD
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-fast-path --duration="$_PERF_DURATION"
```
```

with:

```markdown
```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git status --porcelain
git log -1 --format=%H -- .session-continuity/SESSION_PRIMER.md   # <last-primer-commit>
git rev-parse HEAD
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-issues.sh" --count .   # <fast-path-backlog-count>, "?" on failure
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-1-fast-path --duration="$_PERF_DURATION"
```

`<fast-path-backlog-count>` feeds Step 3's `backlog_fastpath_count`. If it printed `?` (GitHub unavailable), use `backlog_mode="unavailable"` in Step 3 instead of `"fast-path"` — same GitHub-unavailable handling as the non-fast-path skip condition below.
```

- [ ] **Step 2: Add the TSV-writing step to Backlog verification**

Using the Edit tool, insert this new subsection immediately after the "Routing `appears-DONE` candidates" block and before "### Drift check (silent — no user prompt)" in `commands/end-session.md` (i.e. immediately before the current line `### Drift check (silent — no user prompt)`):

```markdown
**Record every verdict for Step 3.** Once every open item has a verdict
(from the overlap gate, the batched classify/verify pass, or the
non-code default), write them all in **one Bash call**. There is no
in-shell list to loop over — the verdicts exist only in what you just
decided — so write one literal `printf` line per item by hand (not a
shell `for`/`while` loop):

```bash
mkdir -p .session-continuity
: > .session-continuity/.end-session-checklist.tsv
printf '%s\t%s\t%s\n' "#4" "appears-DONE" "found test/end_to_end.bats -> 0 hits before, now present" >> .session-continuity/.end-session-checklist.tsv
printf '%s\t%s\t%s\n' "#3" "still-open" "no *.bats and no test/ dir -> item still open" >> .session-continuity/.end-session-checklist.tsv
# ... one such literal printf line per remaining open item, tag first (the
# #N identity, never the ephemeral 1..N list position), verdict second
# (still-open|appears-DONE|manual), citation third (the same evidence string
# already decided above — "not auto-verifiable" for non-code items, "no
# related commits since last refresh — not re-checked this session" for
# overlap-gated ones) ...
```

Skip this entirely when there were zero open items to classify (the file is
absent; Step 3 treats a missing path under `backlog_mode="normal"` as zero
tracked items — see `hooks/lib/checklist-assemble.sh`'s contract).
```

- [ ] **Step 3: Verify the edits landed at the right spots**

```bash
grep -n 'end-session-checklist.tsv\|fast-path-backlog-count' commands/end-session.md
```

Expected: the TSV path appears at least twice (the writing block, the skip note), and `<fast-path-backlog-count>` appears at least twice (the bash comment, the prose sentence after it).

- [ ] **Step 4: Commit**

```bash
git add commands/end-session.md
git commit -m "feat: end-session Step 1 records backlog verdicts for the Step 3 checklist script"
```

---

### Task 4: `commands/end-session.md` Step 3 — call `checklist-assemble.sh`

**Files:**
- Modify: `commands/end-session.md` (currently lines 409-498: "Gather the facts" through "Example output")

**Interfaces:**
- Consumes: `hooks/lib/checklist-assemble.sh` (Task 1), resolved via `CLAUDE_PLUGIN_ROOT` and `require_script` (`CONTRACT_VERSION=1`), same convention every other command-invoked script in this file already follows.

- [ ] **Step 1: Replace "Gather the facts" through "Example output"**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 409-498, from `## Step 3 — Final checklist` through the `*(Illustrative only ...)*` line):

````markdown
## Step 3 — Final checklist

Run real git commands and emit a structured checklist. Every item must reflect actual repo state, not an assertion.

### Gather the facts

Run all six in **one Bash call** (one round trip, not six), timed:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
git diff --cached --name-only          # staged files
git diff --name-only                    # unstaged modifications
git ls-files --others --exclude-standard   # untracked (ignoring .gitignore'd)
git rev-parse --abbrev-ref HEAD         # current branch (or "HEAD" if detached)
git rev-parse --abbrev-ref @{u} 2>/dev/null  # upstream branch, or empty if none
git rev-list --count @{u}..HEAD 2>/dev/null  # unpushed commits, empty if no upstream
_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-3-gather-facts --duration="$_PERF_DURATION"
```

- **Backlog verdicts** — reuse the per-item verdicts from Step 1's
  verification sub-block; re-run
  `bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-issues.sh" .`
  to get the post-close issue set. No new git command — the evidence was already
  gathered in Step 1.

Handle these edge cases explicitly:

- **Not a git repo.** If `git rev-parse` fails, the precondition in Step 0 should have caught this, but belt-and-suspenders: report "⚠️ not inside a git repo" once and skip git-dependent rows.
- **Detached HEAD.** `git rev-parse --abbrev-ref HEAD` returns `HEAD`. Note "⚠️ detached HEAD at `<short-sha>`" in the unpushed-commits row.
- **No upstream.** `git rev-parse --abbrev-ref @{u}` fails. Note "⚠️ branch `<name>` has no upstream — set one with `git push -u origin <name>`" in the unpushed-commits row.

### Emit the checklist

**List every file enumerated by the git commands — do not summarize, filter, or pick a "primary" one.** If `git diff --cached --name-only` returns three files, the "Staged files" row lists all three. Same rule for the Unstaged and Untracked rows. The suggested-commit message may emphasize one theme, but the checklist rows are inventories, not summaries.

Output using this structure. Use ✓ (green), ⚠️ (yellow), or → (suggestion):

| Row | Marker | Content |
|---|---|---|
| Primer refresh | ✓ | "Primer refreshed and staged" OR "Primer updated (outstanding item(s) closed)" OR "Primer already current (no-op)" |
| New learnings | ✓ | "N LEARNINGS entry/entries captured (#X, \"<title>\" …)" OR "No new learnings" |
| Backlog | checkmark if none stale, else warning | "N tracked — <k> appears-DONE (#N, evidence), <m> still-open (#N…), <j> manual (#N…)" OR "none tracked" |
| Staged files | ✓ | "Staged: <file1>, <file2>, …" OR "Nothing staged" |
| Unstaged modifications | ✓ if none, else ⚠️ | "No unstaged modifications" OR "⚠️ Unstaged: <file1>, <file2>, …" |
| Untracked files | ✓ if none, else ⚠️ | "No untracked files" OR "⚠️ N untracked: <file1>, <file2>, … — ignore, add, or delete?" |
| Unpushed commits | ✓ / ⚠️ | "Up to date with origin/<branch>" OR "⚠️ Branch <name> is N commits ahead of origin — push before closing?" OR the detached-HEAD / no-upstream variants |
| Suggested commit | → | Derived from staged files + captured learnings. Omit row entirely if nothing is staged. |

**Backlog row — re-derive, do not cache.** Step 3 re-runs the helper AFTER any Step 1 closures the
user confirmed. The *set* of issues and the counts are recomputed against the
post-close GitHub list; only the per-item
verdicts (`still-open` / `appears-DONE` / `manual`) computed in Step 1 are
reused. If the user closed an issue at the Step 1 prompt, it is gone from the
list and absent from this row. Marker: ✓ if
every remaining item is `still-open` or `manual` (nothing stale lingering);
⚠️ if any remaining item is `appears-DONE` (a resolved item still listed).
Cite the evidence for each `appears-DONE` item inline. A `manual` item's
citation is either `"not auto-verifiable"` (genuinely non-code) or `"no
related commits since last refresh — not re-checked this session"` (skipped
by the overlap gate) — keep whichever citation Step 1 assigned, don't
collapse them to one phrase. When the fast path fired, skip re-deriving this
row altogether and use its own citation as specified there.

### Suggested commit message

If files are staged, derive a commit message from the pattern:

- Only `.session-continuity/` staged → `docs: update session continuity`.
- `.session-continuity/LEARNINGS.md` is staged with code → pick the most prominent captured learning's title (or the primary code-change theme) and use conventional-commit style: `<type>(<scope>): <subject>`. Keep subject line ≤ 72 chars.
- Only code staged (no docs) → should not happen if Step 1 ran; if it does, suggest based on the file paths.

Prefix with `→ Suggested:` and wrap in a fenced code block so the user can copy-paste.

### Example output

```
✓ Primer refreshed and staged
✓ 1 LEARNINGS entry captured (#7, "awk range collapse on single-version CHANGELOG")
⚠️ Backlog: 5 tracked — 1 appears-DONE (4 [c7d1], "add bats test harness": found test/end_to_end.bats → 0 hits before, now present), 1 still-open (3 [b092]), 3 manual (1 [a3f9], 2 [7f3e], 5 [e8a4])
✓ Staged: .session-continuity/SESSION_PRIMER.md, .session-continuity/LEARNINGS.md, .github/workflows/release.yml
✓ No unstaged modifications
⚠️ 2 untracked files: scratch.md, tmp/debug.log — ignore, add, or delete?
⚠️ Branch "main" is 3 commits ahead of origin — push before closing?
→ Suggested:
    git commit -m "fix(ci): extract CHANGELOG section with proper awk range"
```

*(Illustrative only — the real Backlog row reflects the current primer's actual item set and verdicts.)*
````

with:

````markdown
## Step 3 — Final checklist

One script call. Every row reflects actual repo state or a value you
decided in Step 1/Step 2 and pass through — never format or re-derive a row
by hand.

### Gather the facts and render

Run in **one Bash call**, timed. First, copy the Step 1 scratch TSV to a
location outside the repo and delete the in-repo copy — *before* any
git-status command runs, so the git commands below never see it (its path
can't be deleted-then-read, since `checklist-assemble.sh` needs to read it
after the git commands run; copying it out first is what makes both true
at once). Task 2's gitignore entry is the separate belt-and-suspenders case:
a ritual that crashes *before* this block ever runs leaves the file
in-repo, and only the gitignore entry (not this ordering) keeps it out of
a later `git ls-files --others`. Then run the seven git commands, then
build the JSON `checklist-assemble.sh` expects and pipe it through:

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
TSV_INREPO=".session-continuity/.end-session-checklist.tsv"
TSV=""
if [[ -r "$TSV_INREPO" ]]; then
  TSV="$(mktemp)"
  cp "$TSV_INREPO" "$TSV"
  rm -f "$TSV_INREPO"
fi
BACKLOG_MODE="normal"   # set to none|unavailable|not-migrated|fast-path per Step 1's skip conditions/fast path instead, when applicable
BACKLOG_FASTPATH_COUNT="null"   # the fast path's <fast-path-backlog-count>, only when BACKLOG_MODE=fast-path

STAGED_JSON="$(git diff --cached --name-only | jq -R -s 'split("\n") | map(select(length>0))')"
UNSTAGED_JSON="$(git diff --name-only | jq -R -s 'split("\n") | map(select(length>0))')"
UNTRACKED_JSON="$(git ls-files --others --exclude-standard | jq -R -s 'split("\n") | map(select(length>0))')"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
if [[ "$BRANCH" == "HEAD" ]]; then DETACHED=true; else DETACHED=false; fi
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
UPSTREAM="$(git rev-parse --abbrev-ref @{u} 2>/dev/null || true)"
if [[ -z "$UPSTREAM" ]]; then UPSTREAM_JSON="null"; AHEAD_JSON="null"; else
  UPSTREAM_JSON="$(printf '%s' "$UPSTREAM" | jq -R .)"
  AHEAD="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
  AHEAD_JSON="$AHEAD"
fi

# PRIMER, LEARNINGS_JSON, COMMIT_SUBJECT_JSON: set these three from what
# Step 1/Step 2 actually did this invocation — see the field notes below.
PRIMER="current"            # "refreshed" | "closed" | "current"
LEARNINGS_JSON="[]"         # e.g. '[{"number":7,"title":"..."}]' from Step 2's captures
COMMIT_SUBJECT_JSON="null"  # a quoted JSON string, or "null", per the field note below

JSON_TMP="$(mktemp)"
jq -n \
  --argjson staged "$STAGED_JSON" --argjson unstaged "$UNSTAGED_JSON" \
  --argjson untracked "$UNTRACKED_JSON" --arg branch "$BRANCH" \
  --argjson detached "$DETACHED" --arg short_sha "$SHORT_SHA" \
  --argjson upstream "$UPSTREAM_JSON" --argjson ahead "$AHEAD_JSON" \
  --arg primer "$PRIMER" --argjson learnings "$LEARNINGS_JSON" \
  --arg backlog_mode "$BACKLOG_MODE" --argjson backlog_fastpath_count "$BACKLOG_FASTPATH_COUNT" \
  --argjson commit_subject "$COMMIT_SUBJECT_JSON" \
  '{staged:$staged, unstaged:$unstaged, untracked:$untracked, branch:$branch,
    detached:$detached, short_sha:$short_sha, upstream:$upstream, ahead:$ahead,
    primer:$primer, learnings:$learnings, backlog_mode:$backlog_mode,
    backlog_fastpath_count:$backlog_fastpath_count, commit_subject:$commit_subject}' \
  > "$JSON_TMP"

source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/checklist-assemble.sh" 1; then
  CHECKLIST="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/checklist-assemble.sh" "$TSV" < "$JSON_TMP")"
else
  CHECKLIST="⚠️ $SC_REQUIRE_SCRIPT_MSG"
fi
rm -f "$TSV" "$JSON_TMP"

_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=end-session --step=step-3-gather-facts --duration="$_PERF_DURATION"
echo "$CHECKLIST"
```

**Field notes — the values only you know, filled in before running the block above:**

- `BACKLOG_MODE` / `BACKLOG_FASTPATH_COUNT`: `"fast-path"` + the fast path's `<fast-path-backlog-count>` when Step 1's fast path fired; otherwise whichever of `none`/`unavailable`/`not-migrated`/`normal` Step 1's Backlog verification section landed on (its own skip conditions already tell you which).
- `TSV`: leave as computed above (empty string unless the in-repo scratch file existed and was copied out before deletion) — never override it by hand.
- `PRIMER`: `"refreshed"` if the refresh flow ran and staged the primer, `"closed"` if only the drift-clean close-candidate prompt ran and closed item(s), `"current"` if Step 1 was a no-op (fast path or drift-clean-zero-candidates).
- `LEARNINGS_JSON`: the accepted drafts from Step 2's capture flow, as `[{"number":N,"title":"..."}]`; `[]` if Step 2 captured nothing.
- `COMMIT_SUBJECT_JSON`: `"null"` (the bare word, unquoted) unless staged files exist AND at least one is outside `.session-continuity/` — in that case, a quoted JSON string with your conventional-commit subject (`<type>(<scope>): <subject>`, ≤72 chars), e.g. `'"fix(ci): extract CHANGELOG section with proper awk range"'`. Pick the theme from the most prominent captured learning's title, or the primary code-change theme — same judgment call as before this phase, just handed to the script instead of formatted by hand.

**Output.** If `$CHECKLIST` starts with `⚠️` (the `require_script` failure) or `SC-FALLBACK:` (the script's own malformed-input escape), print it as a single warning line and assemble the checklist by hand this one time, following the row table that existed before this phase (Primer refresh / New learnings / Backlog / Staged files / Unstaged modifications / Untracked files / Unpushed commits / Suggested commit, each ✓/⚠️/→, backlog citing evidence for `appears-DONE` only) — then still emit Step 4's sign-off line yourself, choosing the warning-suffixed variant if any row you assembled carries ⚠️. Otherwise, print `$CHECKLIST` verbatim — it already ends with the terminal sign-off line; do not print anything after it except whatever Step 4's timing calls require.
````

- [ ] **Step 2: Verify the old prose-formatting table and example are gone**

```bash
grep -c 'List every file enumerated\|Illustrative only' commands/end-session.md
```

Expected: `0`.

- [ ] **Step 3: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session Step 3 renders the checklist via checklist-assemble.sh"
```

---

### Task 5: `commands/end-session.md` Step 4 — drop the printed sign-off, keep only timing

**Files:**
- Modify: `commands/end-session.md` (currently lines 500-569: `## Step 4 — Terminal sign-off (always)` through the "Required." paragraph)

**Interfaces:**
- Consumes: nothing new — Step 4's two timing blocks (`step-4-ritual-complete`, `step-4-agent-active`) are unchanged.
- Produces: nothing printed — Task 4's `$CHECKLIST` already ends with the sign-off line. Step 4 becomes purely a logging step with no user-facing output of its own.

- [ ] **Step 1: Replace the section header and the two "Always emit" bullets**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 500-502):

```markdown
## Step 4 — Terminal sign-off (always)

After the checklist (and suggested-commit block, if any), emit a final closing line so the user knows the ritual completed and they are not blocked waiting for further prompts.
```

with:

```markdown
## Step 4 — Ritual timing (always)

Step 3's `$CHECKLIST` already ended with the terminal sign-off line — this
step prints nothing of its own. It only logs how long the ritual took, so
the log carries one real end-to-end number per invocation.
```

- [ ] **Step 2: Delete the "Always emit one of these two lines" block and its two example lines**

Using the Edit tool, replace this exact block (currently `commands/end-session.md` lines 555-569):

```markdown
**Always emit one of these two lines, exactly:**

- If every checklist row was ✓ (no ⚠️ anywhere):

  ```
  ✅ Session complete. Safe to close.
  ```

- If any checklist row had ⚠️:

  ```
  ✅ Session complete. Safe to close. (Warnings above are advisory — review before closing if relevant.)
  ```

**Required.** Print this line on its own, after the checklist and any suggested-commit block. Never omit it. Never replace it with paraphrased prose. Never ask follow-up questions after this line — the line marks the end of the ritual. If the user wants to act on a warning, they will reply on their own.
```

with:

```markdown
**Never ask follow-up questions after Step 3's sign-off line printed.** It marks the end of the ritual. If the user wants to act on a warning, they will reply on their own.
```

- [ ] **Step 3: Verify no duplicate sign-off text remains**

```bash
grep -c '✅ Session complete' commands/end-session.md
```

Expected: `0` — the two literal sign-off strings now live only inside `checklist-assemble.sh` and this plan's own smoke test, not in the command markdown.

- [ ] **Step 4: Commit**

```bash
git add commands/end-session.md
git commit -m "refactor: end-session Step 4 becomes a pure timing step, sign-off now owned by checklist-assemble.sh"
```

---

### Task 6: Doc pointers, regression pass, changelog

**Files:**
- Modify: `meta/superpowers/specs/2026-09-02-determinism-program-design.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Collapse the design doc's Phase 4 entry to a pointer**

Using the Edit tool, replace this exact block in `meta/superpowers/specs/2026-09-02-determinism-program-design.md`:

```markdown
**Phase 4 `#41` — `end-session` Step 3 checklist assembly.** One script consuming the
six git outputs and a `tag<TAB>verdict<TAB>citation` file, emitting the eight
finished rows, the four backlog tallies, the per-row markers, and the sign-off
boolean (612-675, 759-773), retiring the example block at 687-701. Depends on
Phase 3's `since`. Removes the file-inventory summarization failure that
line 646 exists to prevent.
```

with:

```markdown
**Phase 4 `#41` — `end-session` Step 3 checklist assembly.** `checklist-assemble.sh`
consumes the (now seven — a `git rev-parse --short HEAD` was added for the
detached-HEAD row) git outputs plus a `tag<TAB>verdict<TAB>citation` scratch
file, emitting all eight finished rows, the backlog tallies, every marker,
and the terminal sign-off line as one block — Step 4 no longer prints
anything of its own. Removes the "list every file, do not summarize"
instruction and the illustrative example entirely; the script's own output
is the contract. Plan:
`meta/superpowers/plans/2026-09-08-determinism-phase-4-checklist-assembly.md`.
```

- [ ] **Step 2: Full regression pass**

```bash
for f in \
  meta/superpowers/validation/2026-09-08-checklist-assemble-smoke.zsh \
  meta/superpowers/validation/2026-08-17-perf-log-smoke.zsh \
  meta/superpowers/validation/2026-09-03-primer-status-smoke.zsh \
  meta/superpowers/validation/2026-08-12-session-start-smoke.zsh \
  meta/superpowers/validation/2026-09-01-require-script-smoke.zsh \
  meta/superpowers/validation/2026-09-01-agent-active-smoke.zsh \
  meta/superpowers/validation/2026-09-02-resolve-transcript-smoke.zsh \
  meta/superpowers/validation/2026-09-02-count-entries-smoke.zsh \
  meta/superpowers/validation/2026-09-02-candidate-render-smoke.zsh \
  meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
do
  echo "--- $f ---"
  zsh "$f" || echo "FAILED: $f"
done
```

Expected: every runner ends `0 failed`.

- [ ] **Step 3: Add a CHANGELOG entry**

Add a new section at the top of `CHANGELOG.md`, directly under the `# Changelog` header and its description line, above `## [0.29.1]`:

```markdown
## [0.30.0] — 2026-09-08

### Changed
- **`end-session`'s Step 3 checklist is now scripted.** New `hooks/lib/checklist-assemble.sh` consumes the seven git-status outputs and a `tag/verdict/citation` backlog-verdict file, and prints all eight finished checklist rows, the backlog tallies, every ✓/⚠️ marker, the suggested-commit block, and the terminal sign-off line as one deterministic block. The model's job shrinks to deciding backlog verdicts (unchanged from before) and picking a commit-message theme when code is staged — everything else (file-list rendering, tallying, marker selection, sign-off wording) is no longer hand-formatted per invocation. Step 4 no longer prints anything; the sign-off line is now part of Step 3's script output.
```

- [ ] **Step 4: Bump the plugin version**

Using the Edit tool, update `.claude-plugin/plugin.json`'s `"version"` field from `"0.29.1"` to `"0.30.0"`.

- [ ] **Step 5: Commit**

```bash
git add meta/superpowers/specs/2026-09-02-determinism-program-design.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "docs: Phase 4 doc pointers, changelog, and version bump for the checklist script"
```
