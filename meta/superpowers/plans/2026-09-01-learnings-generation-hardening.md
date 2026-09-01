# LEARNINGS generation hardening — Implementation Plan

Proven-gate: N/A — this is an unexecuted implementation plan (every task's
checkboxes are unchecked). The "measured"/"confirmed"/"validated" findings
below describe a prior investigation's evidence for *why* each task is
needed, not a claim that this plan's changes are proven working; no code
in this plan has been written or run yet.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the v0.23.0 LEARNINGS generation scripts safe to run and useful to read — close the path where `learnings-index.sh reindex` truncates `LEARNINGS.md` to zero bytes, and retune the candidate heuristics so a real session produces two to four genuine candidates instead of five heredoc fragments plus an eight-candidate overflow warning.

**Architecture:** No new scripts and no new dependencies. `hooks/lib/learnings-index.sh` gains a write gate — it verifies its awk siblings, checks every awk exit status, and refuses to overwrite unless the regenerated file is non-empty and preserves the input's entry count. `hooks/lib/candidate-extract.jq` gets a new command-identity rule (full normalized text, not first line), a wider bookkeeping exclusion, a file-edit precondition, subject parsing for fix commits, and a per-heuristic cap. `hooks/lib/candidate-extract.sh` learns to distinguish bad *input* (`mode:"unavailable"`) from a broken *install* (`mode:"error"`), and absorbs its own perf timing as the spec originally specified. Both scripts go to `CONTRACT_VERSION=2`, and the awk/jq siblings carry their own marker so a partial cache update is caught instead of executed.

**Tech Stack:** bash, `jq` (Oniguruma regex — named captures and `try`/`catch` are used), POSIX `awk`, zsh for the smoke runners. No `python3`, no new runtime dependency.

**Spec:** `meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md` — this plan implements the parts of that spec's Testing plan that were never run (the archived-transcript replay and the end-to-end ritual check), and fixes what running them found. Findings are reproduced below so the plan is self-contained.

## Findings this plan closes

Every row was measured on this machine against real data, not inferred from reading code.

| # | Finding | Evidence |
|---|---|---|
| F1 | `reindex` truncates `LEARNINGS.md` to 0 bytes when an awk sibling is missing. awk exits 2, `$tmp` is empty, `diff -q` reports "differs", `cat "$tmp" > "$file"` clobbers the corpus. Exit code is 0 and the message reads `regenerated 0 bullet(s)`. | Copied `learnings-index.sh` to a directory without its three `.awk` files, ran `reindex` on a copy of this repo's `LEARNINGS.md`: 35,562 bytes in, 0 bytes out, exit 0. |
| F2 | `require_script` validates only the entry script's `CONTRACT_VERSION`. The `.jq` and `.awk` siblings carry no marker and are not checked for existence, so a partial cache update passes the guard and then hits F1. | `hooks/lib/require-script.sh:17-29` reads one file: the path it is given. |
| F3 | Heuristic A's identity rule (first line of the command) collapses every heredoc and quoted multi-line command into one bucket. Real candidate titles include `bun -e ' — investigated for 6 retries.` and `git status --short — investigated for 4 retries.` | Ran `candidate-extract.jq` over the four largest `architect-workbench` transcripts. |
| F4 | Heuristic D uses the raw command as the title and fires on essentially every fix commit in an active session. One real candidate title is 20 lines long and carries the full commit body and the `Co-Authored-By` trailer; one session produced 5 fix-bursts and `overflow: 8`. | Same replay; transcript `0e2be32d`. |
| F5 | Heuristic C cannot fire. It reads `toolUseResult.stderr` (empty in every record measured) or a line starting `Error:` (zero matches), and then demands 3 identical errors spanning 15 minutes. | `181c4ffb`: 558 tool results, 0 with non-empty stderr, 0 matching `^Error:`, 8 with `is_error: true` whose text begins `Exit code N`. |
| F6 | Every failure mode returns the same `mode:"unavailable"`: missing file, stale file, absent `jq`, and any jq runtime error (`2>/dev/null`). A malformed timestamp aborts the whole filter and the user sees a clean "no candidates". | `hooks/lib/candidate-extract.sh:18-42`; `to_epoch` at `candidate-extract.jq:9` throws on any timestamp lacking the `.NNNZ` shape. |
| F7 | The staleness guard is skipped on GNU coreutils. `stat -f %m` there means `--file-system`, writes filesystem info to **stdout**, and exits 1 — command substitution captures that stdout, so `MTIME_EPOCH` is garbage, the `^[0-9]+$` test fails, and the age check never runs. | `gstat -f %m /etc/hosts` on this machine: filesystem block printed to stdout, exit 1. |
| F8 | The Symptoms-index insert path anchors on the first `^---$` line, which is the YAML front-matter opener on any file that has one. | Ran `reindex` on a fixture with front matter: the index was spliced between `---` and `title:`. |
| F9 | Neither awk pass is fence-aware. A `### 9. …` line inside a fenced example counts as an entry, producing a false `DUPNUM` that trips `learning.md` Step 4's refuse-to-write guard. | Code read: `learnings-index-report.awk:1`, `learnings-index-bullets.awk:1`. |
| F10 | `commands/end-session.md:395` still reads "**Apply** each heuristic to the resolved input source" inside the section labeled "documentation, not an execution path", and the documented Heuristic B and D titles no longer match what the script emits. | File read. |
| F11 | Nothing has run post-change. The last `end-session` in `.session-continuity/performance.log` (`2026-09-01T19:36`) logged `step-4-compute-only` and no `step-4-agent-active` — it executed from the 0.22.0 plugin cache. | `grep step-4 .session-continuity/performance.log`. |

## Global Constraints

- Every script under `hooks/lib/` starts with `#!/usr/bin/env bash` (or, for the awk/jq filters, a `#` comment line) followed by a `# CONTRACT_VERSION=N` line. This plan takes `candidate-extract.sh`, `candidate-extract.jq`, `learnings-index.sh`, and all three `learnings-index-*.awk` files to `CONTRACT_VERSION=2`. `require-script.sh` keeps its `CONTRACT_VERSION=n/a` marker — it is sourced, never guarded.
- **Bad input data never fails loud; a broken install always does.** A missing, unreadable, empty, or stale transcript, and a missing `LEARNINGS.md`, produce the documented empty result and `exit 0`. A missing or version-mismatched sibling file, a non-zero awk/jq exit, or an absent `jq` binary is an installation fault: `learnings-index.sh` prints to stderr and exits 2 without touching the file; `candidate-extract.sh` prints `mode:"error"` with a `detail` string and still exits 0 (its caller is a command that must not abort the ritual, but must show the message).
- **`reindex` never writes unless the output is provably safe.** The invariant: the regenerated file is non-empty AND contains exactly as many `^### <n>.` entry headings as the input. This is checked at the single write site, so no future edit to the awk passes can bypass it.
- No new runtime dependency. `jq`, POSIX `awk`, `sed`, `grep`, `cmp`, `sort`, `bash`, and `git` only.
- Idempotency holds: `reindex` run twice over an unchanged file produces `no change` on the second run and a byte-identical file.
- Smoke tests follow the existing convention — `meta/superpowers/validation/YYYY-MM-DD-<name>-smoke.zsh`, `set -uo pipefail`, `pass`/`fail` counters with `ok`/`bad` helpers, `gt_make_repo`/`gt_stage`/`gt_cleanup` from `meta/superpowers/validation/lib/gate-test-common.zsh` where a git repo is needed, every `bad` message carrying the mismatched value, and teardown after the assertion so the diagnostic survives in the run's own output.
- Regex portability: `grep -E` (never GNU BRE `\+`), and `sort` always under `LC_ALL=C`.

---

### Task 1: Write gate for `learnings-index.sh` (F1, F2)

This is the data-loss fix. It ships first and stands alone.

**Files:**
- Modify: `hooks/lib/learnings-index.sh` (whole file)
- Modify: `hooks/lib/learnings-index-report.awk:1` (add contract marker)
- Modify: `hooks/lib/learnings-index-bullets.awk:1` (add contract marker)
- Modify: `hooks/lib/learnings-index-splice.awk:1` (add contract marker)
- Test: `meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh` (extend the existing file)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `learnings-index.sh report <file>` → stdout `MAX <n>`, `DUPNUM <n> <lines>`, `DUPSLUG <slug> <lines>`; exit 0. `learnings-index.sh reindex <file>` → stdout `no change` or `regenerated <n> bullet(s)`; exit 0. Both exit **2** with a one-line stderr message on an installation fault, having modified nothing. Task 6 (command prose) branches on exit status 2.

- [ ] **Step 1: Add the contract markers to the three awk files**

Insert this as the **first line** of each of `hooks/lib/learnings-index-report.awk`, `hooks/lib/learnings-index-bullets.awk`, and `hooks/lib/learnings-index-splice.awk`:

```awk
# CONTRACT_VERSION=2
```

- [ ] **Step 2: Write the failing tests**

Append to `meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`, immediately before the final `rm -rf "$work"`:

```zsh
# --- install-fault paths: never write, never exit 0 -------------------------

# A copy of the script in a directory with no awk siblings must refuse to run.
mkdir -p "$work/orphan"
cp "$lib/learnings-index.sh" "$work/orphan/learnings-index.sh"
cat "$repo/.session-continuity/LEARNINGS.md" > "$work/victim.md"
before_sum="$(shasum "$work/victim.md" | cut -d' ' -f1)"
out="$(bash "$work/orphan/learnings-index.sh" reindex "$work/victim.md" 2>&1)"
rc=$?
after_sum="$(shasum "$work/victim.md" | cut -d' ' -f1)"
[[ "$rc" -eq 2 ]] && ok "missing awk sibling exits 2" || bad "missing awk sibling: expected exit 2, got $rc (out: $out)"
[[ "$before_sum" == "$after_sum" ]] && ok "missing awk sibling leaves the file byte-identical" \
  || bad "missing awk sibling MODIFIED the file ($before_sum -> $after_sum)"
[[ -s "$work/victim.md" ]] && ok "missing awk sibling leaves the file non-empty" \
  || bad "missing awk sibling TRUNCATED the file to 0 bytes"

# A sibling from a different contract version must refuse too.
mkdir -p "$work/skewed"
cp "$lib/learnings-index.sh" "$work/skewed/learnings-index.sh"
for f in learnings-index-report.awk learnings-index-bullets.awk learnings-index-splice.awk; do
  sed 's/^# CONTRACT_VERSION=2$/# CONTRACT_VERSION=1/' "$lib/$f" > "$work/skewed/$f"
done
cat "$repo/.session-continuity/LEARNINGS.md" > "$work/victim2.md"
before_sum="$(shasum "$work/victim2.md" | cut -d' ' -f1)"
out="$(bash "$work/skewed/learnings-index.sh" reindex "$work/victim2.md" 2>&1)"
rc=$?
after_sum="$(shasum "$work/victim2.md" | cut -d' ' -f1)"
[[ "$rc" -eq 2 ]] && ok "contract-skewed awk sibling exits 2" || bad "contract-skewed sibling: expected exit 2, got $rc (out: $out)"
[[ "$before_sum" == "$after_sum" ]] && ok "contract-skewed sibling leaves the file byte-identical" \
  || bad "contract-skewed sibling MODIFIED the file"

# report must fail the same way rather than printing a bogus MAX 0.
out="$(bash "$work/orphan/learnings-index.sh" report "$work/victim.md" 2>&1)"
rc=$?
[[ "$rc" -eq 2 ]] && ok "report with missing sibling exits 2" || bad "report with missing sibling: expected exit 2, got $rc (out: $out)"

# --- entry-count invariant --------------------------------------------------

# A splice pass that silently drops entries must be refused. Simulate by
# handing the script a splice sibling that deletes every entry heading.
mkdir -p "$work/lossy"
cp "$lib/learnings-index.sh" "$work/lossy/learnings-index.sh"
cp "$lib/learnings-index-report.awk" "$lib/learnings-index-bullets.awk" "$work/lossy/"
cat > "$work/lossy/learnings-index-splice.awk" <<'EOF'
# CONTRACT_VERSION=2
/^### [0-9]+\./ { next }
{ print }
EOF
cat "$repo/.session-continuity/LEARNINGS.md" > "$work/victim3.md"
before_sum="$(shasum "$work/victim3.md" | cut -d' ' -f1)"
out="$(bash "$work/lossy/learnings-index.sh" reindex "$work/victim3.md" 2>&1)"
rc=$?
after_sum="$(shasum "$work/victim3.md" | cut -d' ' -f1)"
[[ "$rc" -eq 2 ]] && ok "entry-count drop exits 2" || bad "entry-count drop: expected exit 2, got $rc (out: $out)"
[[ "$before_sum" == "$after_sum" ]] && ok "entry-count drop leaves the file byte-identical" \
  || bad "entry-count drop MODIFIED the file"
```

- [ ] **Step 3: Run the tests, confirm they fail**

Run: `zsh meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`
Expected: the pre-existing 12 assertions pass; the new ones fail — `missing awk sibling: expected exit 2, got 0` and `missing awk sibling TRUNCATED the file to 0 bytes`.

- [ ] **Step 4: Rewrite `hooks/lib/learnings-index.sh`**

Replace the whole file with:

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=2
# hooks/lib/learnings-index.sh — LEARNINGS.md derivations.
# See meta/superpowers/plans/2026-09-01-learnings-generation-hardening.md
#
# Usage:
#   learnings-index.sh report <file>    Prints "MAX <n>" then one
#                                        "DUPNUM <n> <lines>" per duplicated
#                                        entry number and one "DUPSLUG
#                                        <slug> <lines>" per duplicated slug.
#   learnings-index.sh reindex <file>   Regenerates "## Symptoms index" in
#                                        place from every entry's
#                                        "**Symptom.**" line. Idempotent
#                                        from the first run. Prints
#                                        "regenerated <n> bullet(s)" or
#                                        "no change".
#
# Two failure classes, deliberately distinct:
#   Bad input (missing/unreadable file) — `report` prints "MAX 0", `reindex`
#   is a silent no-op, both exit 0.
#   Broken install (an awk sibling missing or from another plugin version, or
#   an awk pass exiting non-zero, or a regenerated file that is empty or has
#   lost entries) — a one-line message on stderr and exit 2, with the target
#   file never opened for writing. Losing LEARNINGS.md is worse than any
#   ritual that fails to finish.
#
# The regenerated index applies this script's own rule (hard 12-word cutoff
# + ellipsis, dictionary-order case-insensitive sort) consistently. It does
# not reproduce a prior hand-authored index byte-for-byte.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBCOMMAND="${1:-}"
FILE="${2:-}"
WORK=""

AWK_SIBLINGS="learnings-index-report.awk learnings-index-bullets.awk learnings-index-splice.awk"

die_install() {
  [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"
  printf 'learnings-index.sh: %s\n' "$1" >&2
  exit 2
}

check_siblings() {
  local f
  for f in $AWK_SIBLINGS; do
    [[ -r "$SCRIPT_DIR/$f" ]] || die_install \
      "$f is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`. LEARNINGS.md was not modified."
    grep -q '^# CONTRACT_VERSION=2$' "$SCRIPT_DIR/$f" || die_install \
      "$f is from a different plugin version — run \`/session-continuity:update\`. LEARNINGS.md was not modified."
  done
}

count_entries() {
  grep -cE '^### [0-9]+\.' "$1" 2>/dev/null || true
}

report() {
  check_siblings
  awk -f "$SCRIPT_DIR/learnings-index-report.awk" "$1" \
    || die_install "the report pass failed (awk exited non-zero)."
}

reindex() {
  local file="$1" has_index=0 bullets tmp n_bullets before after

  check_siblings

  WORK="$(mktemp -d)" || die_install "could not create a temp directory."
  bullets="$WORK/bullets"
  tmp="$WORK/out"

  grep -q '^## Symptoms index' "$file" && has_index=1

  awk -f "$SCRIPT_DIR/learnings-index-bullets.awk" "$file" | LC_ALL=C sort -d -f > "$bullets" \
    || die_install "the bullet pass failed (awk or sort exited non-zero). LEARNINGS.md was not modified."

  awk -v bfile="$bullets" -v has_index="$has_index" \
    -f "$SCRIPT_DIR/learnings-index-splice.awk" "$file" > "$tmp" \
    || die_install "the splice pass failed (awk exited non-zero). LEARNINGS.md was not modified."

  # Write gate. Both conditions are checked at the one place that writes, so
  # a future change to either awk pass cannot route around them.
  [[ -s "$tmp" ]] || die_install \
    "the regenerated file came out empty. LEARNINGS.md was not modified."

  before="$(count_entries "$file")"
  after="$(count_entries "$tmp")"
  [[ "$before" == "$after" ]] || die_install \
    "entry count changed during regeneration ($before -> $after). LEARNINGS.md was not modified."

  n_bullets="$(wc -l < "$bullets" | tr -d ' ')"

  if cmp -s "$file" "$tmp"; then
    rm -rf "$WORK"; WORK=""
    echo "no change"
  else
    cat "$tmp" > "$file"
    rm -rf "$WORK"; WORK=""
    echo "regenerated $n_bullets bullet(s)"
  fi
}

if [[ ! -r "$FILE" ]]; then
  [[ "$SUBCOMMAND" == "report" ]] && echo "MAX 0"
  exit 0
fi

case "$SUBCOMMAND" in
  report)  report "$FILE" ;;
  reindex) reindex "$FILE" ;;
  *) echo "learnings-index.sh: unknown subcommand '$SUBCOMMAND' (report|reindex)" >&2 ;;
esac
exit 0
```

- [ ] **Step 5: Run the tests, confirm they pass**

Run: `zsh meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`
Expected: `0 failed`, with the pass count up from 12 by the eight assertions added in Step 2.

- [ ] **Step 6: Confirm the real file is still safe to reindex**

Run:

```bash
cp .session-continuity/LEARNINGS.md /tmp/li-check.md
bash hooks/lib/learnings-index.sh reindex /tmp/li-check.md
bash hooks/lib/learnings-index.sh reindex /tmp/li-check.md
diff <(grep -cE '^### [0-9]+\.' .session-continuity/LEARNINGS.md) <(grep -cE '^### [0-9]+\.' /tmp/li-check.md)
```

Expected: first run prints `regenerated 15 bullet(s)` or `no change`, second prints `no change`, `diff` is silent.

- [ ] **Step 7: Commit**

```bash
git add hooks/lib/learnings-index.sh hooks/lib/learnings-index-*.awk meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh
git commit -m "fix: refuse to write LEARNINGS.md unless the regenerated file is provably intact

reindex copied awk's output over the source file without checking awk's exit
status. A missing .awk sibling produced an empty temp file, which was then
copied over a 161KB LEARNINGS.md — exit 0, message 'regenerated 0 bullet(s)'.
The write site now verifies sibling presence and contract version, checks
every awk exit status, and requires non-empty output with an unchanged entry
count. Install faults exit 2 without opening the target for writing."
```

---

### Task 2: Fence-aware, front-matter-safe awk passes (F8, F9)

**Files:**
- Modify: `hooks/lib/learnings-index-report.awk` (whole file)
- Modify: `hooks/lib/learnings-index-bullets.awk` (whole file)
- Modify: `hooks/lib/learnings-index-splice.awk` (whole file)
- Test: `meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh` (extend)

**Interfaces:**
- Consumes: the write gate and `check_siblings` from Task 1 — the contract marker line added there stays line 1 of each file.
- Produces: no interface change. `report`'s and `reindex`'s stdout contracts are unchanged; only which lines they consider changes.

- [ ] **Step 1: Write the failing tests**

Append to `meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`, before the final `rm -rf "$work"`:

```zsh
# --- fenced code blocks are not entries -------------------------------------

cat > "$work/fenced.md" <<'MDEOF'
# fixture

### 7. real entry
Slug: real-one

**The trap.** x

**Symptom.** the real symptom line

**Fix.** here is how the heading looks:

```markdown
### 7. an example heading inside a fence
Slug: real-one
**Symptom.** this line is an example, not an entry
```

---
MDEOF
out="$(bash "$lib/learnings-index.sh" report "$work/fenced.md")"
print -r -- "$out" | grep -q DUPNUM && bad "fenced example produced a false DUPNUM: $out" \
  || ok "report ignores entry headings inside fenced code blocks"
print -r -- "$out" | grep -q DUPSLUG && bad "fenced example produced a false DUPSLUG: $out" \
  || ok "report ignores Slug: lines inside fenced code blocks"
bash "$lib/learnings-index.sh" reindex "$work/fenced.md" > /dev/null
n_bullets="$(grep -c '^- .* — #' "$work/fenced.md")"
[[ "$n_bullets" -eq 1 ]] && ok "reindex indexes 1 symptom, not the fenced example" \
  || bad "reindex indexed $n_bullets bullets, expected 1"

# --- YAML front matter survives ---------------------------------------------

cat > "$work/frontmatter.md" <<'MDEOF'
---
title: My learnings
author: someone
---

# Learnings

Intro prose.

## Runtime

### 1. thing
Slug: thing

**The trap.** x

**Symptom.** it broke badly

**Fix.** x

---
MDEOF
bash "$lib/learnings-index.sh" reindex "$work/frontmatter.md" > /dev/null
head -1 "$work/frontmatter.md" | grep -q '^---$' && ok "front matter opener still on line 1" \
  || bad "front matter opener was displaced: $(head -1 "$work/frontmatter.md")"
sed -n '2p' "$work/frontmatter.md" | grep -q '^title: My learnings$' && ok "front matter body intact" \
  || bad "front matter body was mangled: $(sed -n '2p' "$work/frontmatter.md")"
grep -q '^## Symptoms index' "$work/frontmatter.md" && ok "index inserted into a front-matter file" \
  || bad "no index inserted into the front-matter file"
after1="$(cat "$work/frontmatter.md")"
bash "$lib/learnings-index.sh" reindex "$work/frontmatter.md" > /dev/null
[[ "$after1" == "$(cat "$work/frontmatter.md")" ]] && ok "front-matter file reindex is idempotent" \
  || bad "front-matter file changed on the second reindex"
```

- [ ] **Step 2: Run the tests, confirm they fail**

Run: `zsh meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`
Expected: `fenced example produced a false DUPNUM`, `reindex indexed 2 bullets, expected 1`, and `front matter opener was displaced: ## Symptoms index`.

- [ ] **Step 3: Rewrite `hooks/lib/learnings-index-report.awk`**

````awk
# CONTRACT_VERSION=2
# Reports the maximum entry number, duplicate entry numbers, and duplicate
# slugs in a LEARNINGS.md. Lines inside fenced code blocks are documentation
# examples, never entries.
/^```/ { fence = !fence; next }
fence { next }
/^### [0-9]+\./ {
  line = $0
  sub(/^### /, "", line)
  sub(/\..*/, "", line)
  num = line + 0
  cnt[num]++
  lines[num] = (cnt[num] == 1) ? NR : (lines[num] "," NR)
  if (num > max) max = num
}
/^Slug:[ \t]*/ {
  s = $0
  sub(/^Slug:[ \t]*/, "", s)
  gsub(/[ \t]+$/, "", s)
  scnt[s]++
  slines[s] = (scnt[s] == 1) ? NR : (slines[s] "," NR)
}
END {
  print "MAX", max + 0
  for (n in cnt) if (cnt[n] > 1) print "DUPNUM", n, lines[n]
  for (s in scnt) if (scnt[s] > 1) print "DUPSLUG", s, slines[s]
}
````

- [ ] **Step 4: Rewrite `hooks/lib/learnings-index-bullets.awk`**

````awk
# CONTRACT_VERSION=2
# Emits one "- <first 12 words of the symptom> — #<entry number>" line per
# entry. Lines inside fenced code blocks are examples, never entries.
/^```/ { fence = !fence; next }
fence { next }
/^### [0-9]+\./ {
  line = $0
  sub(/^### /, "", line)
  sub(/\..*/, "", line)
  num = line + 0
  have_num = 1
}
/^\*\*Symptom\.\*\* / && have_num {
  text = $0
  sub(/^\*\*Symptom\.\*\* /, "", text)
  n = split(text, words, /[ \t]+/)
  lim = (n < 12) ? n : 12
  out = ""
  for (i = 1; i <= lim; i++) out = out (i > 1 ? " " : "") words[i]
  if (n > 12) out = out "…"
  print "- " out " — #" num
  have_num = 0
}
````

- [ ] **Step 5: Rewrite `hooks/lib/learnings-index-splice.awk`**

The insert anchor moves from "the first `---` line" to "immediately before the first `## ` section heading". Front matter contains no `## ` heading, so it can no longer be split. A file with no `## ` heading at all gets the block appended in `END`, using the same trailer as every other path so the second run still matches.

````awk
# CONTRACT_VERSION=2
# Replaces (or inserts) the "## Symptoms index" section. Reads the sorted
# bullet lines from the file named by -v bfile; -v has_index tells it whether
# the input already contains the section. Every input line is printed exactly
# once except the old section body, which is replaced wholesale.
function emit_section(   bline) {
  print "## Symptoms index"
  print ""
  print "<!--"
  print "  Fully derived — never hand-edit. The /session-continuity:learning"
  print "  command regenerates this list from every entry's **Symptom.** line"
  print "  each time it appends a new entry."
  print "-->"
  print ""
  while ((getline bline < bfile) > 0) print bline
  close(bfile)
  print ""
  print "---"
  print ""
}
BEGIN { replaced = 0; in_old = 0; fence = 0 }
/^```/ { fence = !fence; print; next }
fence { print; next }
/^## Symptoms index/ && !replaced {
  emit_section()
  in_old = 1
  replaced = 1
  next
}
in_old && /^## / { in_old = 0 }
in_old { next }
!has_index && !replaced && /^## / {
  emit_section()
  replaced = 1
}
{ print }
END {
  if (!replaced) emit_section()
}
````

- [ ] **Step 6: Run the tests, confirm they pass**

Run: `zsh meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh`
Expected: `0 failed`, with the seven assertions added in Step 1 now passing.

- [ ] **Step 7: Confirm the real file round-trips unchanged in substance**

Run:

```bash
cp .session-continuity/LEARNINGS.md /tmp/li-fence.md
bash hooks/lib/learnings-index.sh reindex /tmp/li-fence.md
diff <(grep -vE '^- .* — #[0-9]+$' .session-continuity/LEARNINGS.md) <(grep -vE '^- .* — #[0-9]+$' /tmp/li-fence.md)
```

Expected: `diff` reports nothing outside the index bullet lines — every entry body is byte-identical.

- [ ] **Step 8: Commit**

```bash
git add hooks/lib/learnings-index-*.awk meta/superpowers/validation/2026-09-01-learnings-index-smoke.zsh
git commit -m "fix: make the LEARNINGS index passes fence-aware and front-matter-safe

Entry headings and Slug: lines inside fenced examples were counted as real
entries, which produced false DUPNUM reports that trip learning.md Step 4's
refuse-to-write guard. The insert path anchored on the first '---' line, which
is the YAML front-matter opener on any file that has one; it now anchors on
the first '## ' section heading."
```

---

### Task 3: Failure taxonomy and portability for `candidate-extract.sh` (F2, F6, F7)

**Files:**
- Modify: `hooks/lib/candidate-extract.sh` (whole file)
- Test: `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh` (extend)

**Interfaces:**
- Consumes: `hooks/lib/perf-log.sh record --source=command --name=end-session --step=step-2-transcript-extraction --duration=<seconds>` (existing, unchanged).
- Produces: stdout is one JSON object, always, exit 0, always:
  `{"mode":"transcript"|"unavailable"|"error","candidates":[...],"overflow":N,"detail":"<string>"}`.
  `detail` is `""` for `mode:"transcript"` and a one-sentence human-readable string otherwise. Task 4 produces the `mode:"transcript"` body; Task 6 renders all three modes.

- [ ] **Step 1: Write the failing tests**

Append to `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`, before the determinism block at the end:

```zsh
# --- failure taxonomy: bad input vs broken install ---------------------------

out="$(bash "$lib/candidate-extract.sh" /no/such/file.jsonl)"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "unavailable" ]] && ok "missing transcript -> mode:unavailable" || bad "missing transcript gave mode:$mode"
[[ -n "$(print -r -- "$out" | jq -r .detail)" ]] && ok "unavailable carries a detail string" || bad "unavailable had an empty detail"

# A missing .jq sibling is an install fault, not missing input.
mkdir -p "$work_ce/orphan"
cp "$lib/candidate-extract.sh" "$work_ce/orphan/"
fresh_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test" > "$fresh_f"
out="$(bash "$work_ce/orphan/candidate-extract.sh" "$fresh_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "error" ]] && ok "missing candidate-extract.jq -> mode:error" || bad "missing .jq gave mode:$mode (out: $out)"
print -r -- "$out" | jq -r .detail | grep -q 'session-continuity:update' \
  && ok "mode:error names the update command" || bad "mode:error detail was unhelpful: $out"

# A contract-skewed .jq sibling is also an install fault.
mkdir -p "$work_ce/skewed"
cp "$lib/candidate-extract.sh" "$work_ce/skewed/"
sed 's/^# CONTRACT_VERSION=2$/# CONTRACT_VERSION=1/' "$lib/candidate-extract.jq" > "$work_ce/skewed/candidate-extract.jq"
out="$(bash "$work_ce/skewed/candidate-extract.sh" "$fresh_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "error" ]] && ok "contract-skewed .jq -> mode:error" || bad "contract-skewed .jq gave mode:$mode"

# A malformed timestamp must not abort the whole filter.
mixed_f="$(mktemp)"
{
  jline '{"type":"assistant","timestamp":"not-a-timestamp","message":{"content":[{"type":"tool_use","name":"Bash","id":"bad","input":{"command":"bun test src/x.test.ts"}}]}}'
  mk_bash_call "2026-09-01T00:00:00.000Z" "m1" "bun test src/x.test.ts"
  mk_edit      "2026-09-01T00:00:30.000Z" "e1"
  mk_bash_call "2026-09-01T00:01:00.000Z" "m2" "bun test src/x.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "m3" "bun test src/x.test.ts"
} > "$mixed_f"
out="$(bash "$lib/candidate-extract.sh" "$mixed_f")"
mode="$(print -r -- "$out" | jq -r .mode)"
[[ "$mode" == "transcript" ]] && ok "a malformed timestamp does not abort the filter" \
  || bad "malformed timestamp gave mode:$mode (out: $out)"
rm -f "$mixed_f" "$fresh_f"

# --- self-timing ------------------------------------------------------------

timing_repo="$(gt_make_repo)"
timing_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "s1" "bun test" > "$timing_f"
( cd "$timing_repo" && bash "$lib/candidate-extract.sh" "$timing_f" > /dev/null )
if grep -q '"step":"step-2-transcript-extraction"' "$timing_repo/.session-continuity/performance.log" 2>/dev/null; then
  ok "the script logs its own step-2-transcript-extraction line"
else
  bad "no step-2-transcript-extraction line was logged by the script"
fi
rm -f "$timing_f"
gt_cleanup "$timing_repo"
```

Add near the top of the same file, after the `lib=` assignment, the shared fixtures the new blocks use:

```zsh
work_ce="$(mktemp -d)"
mk_edit() {  # <ts> <tool_use_id>
  jline "{\"type\":\"assistant\",\"timestamp\":\"$1\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"id\":\"$2\",\"input\":{\"file_path\":\"/tmp/x.ts\"}}]}}"
}
```

and `rm -rf "$work_ce"` immediately before the final `print ""`.

- [ ] **Step 2: Run the tests, confirm they fail**

Run: `zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: `missing .jq gave mode:unavailable`, `unavailable had an empty detail`, `no step-2-transcript-extraction line was logged by the script`.

- [ ] **Step 3: Rewrite `hooks/lib/candidate-extract.sh`**

```bash
#!/usr/bin/env bash
# CONTRACT_VERSION=2
# hooks/lib/candidate-extract.sh — LEARNINGS candidate extraction.
# See meta/superpowers/plans/2026-09-01-learnings-generation-hardening.md
#
# Usage: candidate-extract.sh <transcript-path>
# Prints one JSON object to stdout and always exits 0:
#   {"mode":"transcript"|"unavailable"|"error","candidates":[...],
#    "overflow":N,"detail":"<string>"}
#
#   transcript  — the filter ran; candidates may still be empty.
#   unavailable — bad input: no path, unreadable, empty, or stale (>5min)
#                 transcript. The caller falls back to context-window mode.
#   error       — broken install or environment: jq absent, the .jq filter
#                 missing or from another plugin version, the filter itself
#                 failing, or an mtime that cannot be read on this platform.
#                 The caller surfaces `detail` to the user. Never silently
#                 equivalent to "no candidates" — that equivalence is how the
#                 prose version's derivations went missing for weeks.
#
# Times itself through perf-log.sh so the measurement cannot be dropped by a
# command file being rewritten around it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSCRIPT="${1:-}"
JQ_FILTER="$SCRIPT_DIR/candidate-extract.jq"

# BSD date has no %N and prints a literal "N"; rewrite it to a zero so the
# arithmetic below degrades to whole-second resolution instead of breaking.
_START="$(date +%s.%N 2>/dev/null | sed 's/N$/0/')"
[[ "$_START" =~ ^[0-9]+(\.[0-9]+)?$ ]] || _START=""

json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

finish() {
  if [[ -n "$_START" ]]; then
    local end dur
    end="$(date +%s.%N 2>/dev/null | sed 's/N$/0/')"
    dur="$(awk -v a="$_START" -v b="$end" 'BEGIN{d=b-a; if (d<0) d=0; printf "%.3f", d}' 2>/dev/null)"
    if [[ -n "$dur" ]]; then
      bash "$SCRIPT_DIR/perf-log.sh" record --source=command --name=end-session \
        --step=step-2-transcript-extraction --duration="$dur" >/dev/null 2>&1 || true
    fi
  fi
  exit 0
}

emit() {  # <mode> <detail>
  printf '{"mode":"%s","candidates":[],"overflow":0,"detail":"%s"}\n' "$1" "$(json_escape "$2")"
  finish
}

# GNU stat's -f means --file-system and writes to stdout while exiting 1, so
# the BSD form must never be tried first inside a command substitution.
mtime_epoch() {
  local v
  v="$(stat -c %Y "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  v="$(stat -f %m "$1" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s' "$v"; return 0; }
  return 1
}

[[ -n "$TRANSCRIPT" ]] || emit unavailable "no transcript path was given."
[[ -r "$TRANSCRIPT" ]] || emit unavailable "the transcript is not readable: $TRANSCRIPT"
[[ -s "$TRANSCRIPT" ]] || emit unavailable "the transcript is empty: $TRANSCRIPT"

command -v jq >/dev/null 2>&1 \
  || emit error "jq is not installed, so LEARNINGS candidates cannot be extracted. Install jq and re-run."
[[ -r "$JQ_FILTER" ]] \
  || emit error "candidate-extract.jq is missing from $SCRIPT_DIR — the plugin cache is incomplete. Run \`/session-continuity:update\`."
grep -q '^# CONTRACT_VERSION=2$' "$JQ_FILTER" \
  || emit error "candidate-extract.jq is from a different plugin version — run \`/session-continuity:update\`."

MTIME="$(mtime_epoch "$TRANSCRIPT")" \
  || emit error "neither \`stat -c %Y\` nor \`stat -f %m\` works on this platform, so transcript staleness cannot be checked."
NOW="$(date -u +%s)"
AGE=$(( NOW - MTIME ))
[[ "$AGE" -le 300 ]] \
  || emit unavailable "the transcript is stale (last written $(( AGE / 60 )) minutes ago) — it is probably not this session."

TRACKED_FILES_JSON="$(git ls-files 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null)"
[[ -n "$TRACKED_FILES_JSON" ]] || TRACKED_FILES_JSON="[]"

ERRFILE="$(mktemp)"
RESULT="$(jq -n --argjson tracked_files "$TRACKED_FILES_JSON" -f "$JQ_FILTER" "$TRANSCRIPT" 2>"$ERRFILE")"
JQ_STATUS=$?
DETAIL="$(head -1 "$ERRFILE" 2>/dev/null)"
rm -f "$ERRFILE"

if [[ "$JQ_STATUS" -ne 0 || -z "$RESULT" ]]; then
  emit error "the candidate filter failed: ${DETAIL:-jq exited $JQ_STATUS}"
fi

printf '%s\n' "$RESULT"
finish
```

- [ ] **Step 4: Run the tests, confirm they pass**

Run: `zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: every assertion passes except the ones Task 4 changes; specifically the four new taxonomy assertions and the self-timing assertion pass. Heuristic assertions may still pass here — Task 4 rewrites them.

- [ ] **Step 5: Verify the GNU-stat path directly**

Run:

```bash
bash -c 'PATH=/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH; command -v stat; stat -c %Y hooks/lib/candidate-extract.sh'
```

Expected: a bare epoch integer. If GNU coreutils is not installed in that prefix, run `stat -f %m hooks/lib/candidate-extract.sh` instead and confirm a bare epoch integer — one of the two branches must produce a plain number on any given machine.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/candidate-extract.sh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
git commit -m "fix: separate broken-install failures from missing input in candidate-extract

Every failure returned mode:unavailable, so an absent jq, a missing .jq filter,
and a jq runtime error all rendered as a clean 'no candidates surfaced'. They
now return mode:error with a detail string the command surfaces. Also fixes the
staleness guard on GNU coreutils, where 'stat -f %m' means --file-system and
polluted the mtime with filesystem output, and moves the perf timing into the
script per the design spec."
```

---

### Task 4: Retune the heuristics against real transcripts (F3, F4, F5)

The current rules were written as prose, executed by an agent applying judgment, and then transcribed literally into jq. The transcription is faithful; the rules are not what was being followed. This task replaces them with rules validated against four real sessions.

**Files:**
- Modify: `hooks/lib/candidate-extract.jq` (whole file)
- Test: `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh` (replace the heuristic blocks)

**Interfaces:**
- Consumes: `--argjson tracked_files <array>` and the transcript path, both supplied by `candidate-extract.sh` from Task 3.
- Produces: `{mode:"transcript", candidates:[{heuristic,title,evidence}], overflow:N, detail:""}` where `heuristic` is one of `retry-burst`, `revert`, `error-recurrence`, `fix-burst`. At most 2 candidates per heuristic and at most 5 overall; `overflow` is the count dropped by either cap. Task 6's presentation block renders these fields.

**Rule changes and the evidence for each:**

- **Command identity is the full normalized text, not the first line.** Collapsing whitespace across newlines means two heredoc commits with different bodies are different commands. This alone removes `bun -e '`, `jq -r '`, `python3 - <<'EOF'`, and `git commit -m "$(cat <<'EOF'` from the candidate list.
- **Near-variants merge on a family key** that rewrites digits *following a `-` or `=`* to `N`, plus `N>&N` for redirections. `tail -8`, `tail -10`, and `tail -15` become one family; `2026-08-06-smoke-gate-smoke.zsh` and `2026-06-15-fire-before-action-smoke.zsh` do not (their difference is alphabetic), and `gh pr merge 22` and `gh pr merge 24` do not (the digit does not follow `-` or `=`). Both counter-examples were real over-merges in an earlier draft of this rule.
- **Bookkeeping commands are excluded**, after stripping a leading `cd <path> &&`, `timeout <n>`, or `env VAR=x` prefix so that `cd /repo && bun test` is still a test run.
- **A retry burst requires at least one file edit between the first and last occurrence.** A command repeated with no intervening `Edit`/`Write`/`MultiEdit` is polling, not investigation. Timestamps are compared as ISO strings, which sorts correctly for this format and avoids parsing.
- **Fix-burst titles use the parsed commit subject** — from `-m "…"`, `-m '…'`, or the first non-empty line of a heredoc body — and the fix match anchors on the subject, not anywhere in the command.
- **A fix burst additionally requires a retry cluster in its window**: some command family repeated ≥3 times in the preceding 30 minutes. Measured effect: 8 fix-bursts → 3 on `0e2be32d`, 3 → 0 on `181c4ffb`.
- **Error recurrence drops to ≥2 occurrences spanning ≥5 minutes**, and reads the error from `is_error` results or from text beginning `Exit code [1-9]`. The old `stderr`/`^Error:` sources matched nothing in 1,155 real tool results across two transcripts, and ≥3-identical-over-15-minutes never fired.
- **At most 2 candidates per heuristic**, so one noisy signal cannot fill the list.
- **User home directories are rewritten to `~/`** in every title and evidence line, matching the command file's stated privacy rule.
- **Heuristic B's git verbs must sit at a command position** — start of the command or immediately after `&&`, `;`, or `|`. The unanchored version matched any command whose *text* contained "git revert", and on a real transcript the thing it matched was the jq program the agent wrote to run this very heuristic by hand. Its `rm -rf` branch now requires a tracked path to appear as an actual argument token (or as a parent directory of one) rather than as a substring anywhere in the command.
- **Heuristic B's title shows the matched segment**, not the head of the command. A real `git checkout -- docs/…/.history.jsonl` was sitting behind two `tmux kill-session` calls, so the head of the command said nothing about the revert.
- **The error string prefers a line that reads like an error** over the first line of output, and is capped at 160 characters (120 in the title). The first line of a failing `bun test` is its version banner, which produced the candidate `"bun test v1.3.14 (0d9b296a)" — recurred 2 times over 255 minutes`; a recurring hook-deny message produced a title several hundred characters long.

Expected output after this change, measured by running exactly this filter over the archived transcripts:

| Transcript | Before | After |
|---|---|---|
| `67fb9ff8` (14M) | 3 candidates, 2 of them heredoc/quote fragments | 2, overflow 0: `timeout 90 bun run … build` ×23, `bun test 2>&1 \| tail -15` ×8 |
| `181c4ffb` (11M) | 5 candidates, overflow 1 | 3, overflow 0: two test loops plus a recurring proven-gate rejection |
| `0e2be32d` (8.4M) | 5 candidates, all heredoc commits, overflow 8 | 5, overflow 2: 2 fix-burst with parsed subjects, 2 retry-burst, 1 revert naming `git checkout -- docs/…/.history.jsonl` |
| `7ead1202` (8.0M) | 5 candidates, overflow 4 | 2, overflow 2: `bun test 2>&1 \| tail -20` ×10, `timeout 90 bun run …` ×9 |

Across all 30 transcripts in that project directory the filter completes without error, and the sessions that were short or administrative produce zero candidates rather than filler.

- [ ] **Step 1: Replace the heuristic assertions in the smoke test**

In `meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`, replace everything from the `# --- Heuristic A` comment through the end of the `# --- Heuristic D` block with:

```zsh
# --- Heuristic A: retry burst ------------------------------------------------

a_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:00:01.000Z" "t1" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_edit      "2026-09-01T00:00:30.000Z" "e1"
  mk_bash_call "2026-09-01T00:01:00.000Z" "t2" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:01:01.000Z" "t2" true "Exit code 1\\nFAIL src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "t3" "bun test src/foo.test.ts"
  mk_result    "2026-09-01T00:02:01.000Z" "t3" false "Exit code 0\\nPASS"
} > "$a_f"
out="$(bash "$lib/candidate-extract.sh" "$a_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "retry-burst")' >/dev/null 2>&1 \
  && ok "Heuristic A: 3x identical command with an edit between triggers retry-burst" \
  || bad "Heuristic A did not trigger: $out"

# Same burst, no edit between: polling, not investigation.
noedit_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "n1" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T00:01:00.000Z" "n2" "bun test src/foo.test.ts"
  mk_bash_call "2026-09-01T00:02:00.000Z" "n3" "bun test src/foo.test.ts"
} > "$noedit_f"
out="$(bash "$lib/candidate-extract.sh" "$noedit_f")"
[[ "$(print -r -- "$out" | jq '.candidates | length')" -eq 0 ]] \
  && ok "Heuristic A: a burst with no file edits produces nothing" \
  || bad "Heuristic A fired without any file edit: $out"
rm -f "$noedit_f"

# Regression: three heredoc commits are three different commands, not a burst.
heredoc_f="$(mktemp)"
{
  for i in 1 2 3; do
    jline "{\"type\":\"assistant\",\"timestamp\":\"2026-09-01T00:0${i}:00.000Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"h$i\",\"input\":{\"command\":\"git commit -m \\\"\$(cat <<'EOF'\\nfix(area): change number $i\\nEOF\\n)\\\"\"}}]}}"
    mk_edit "2026-09-01T00:0${i}:30.000Z" "he$i"
  done
} > "$heredoc_f"
out="$(bash "$lib/candidate-extract.sh" "$heredoc_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "retry-burst")' >/dev/null 2>&1 \
  && bad "heredoc commits were grouped as a retry burst: $out" \
  || ok "Heuristic A: heredoc commits with different bodies are not a burst"
rm -f "$heredoc_f"

# Regression: bookkeeping commands never surface.
book_f="$(mktemp)"
{
  for i in 1 2 3 4; do
    mk_bash_call "2026-09-01T00:0${i}:00.000Z" "b$i" "git status --short"
    mk_edit      "2026-09-01T00:0${i}:30.000Z" "be$i"
  done
} > "$book_f"
out="$(bash "$lib/candidate-extract.sh" "$book_f")"
[[ "$(print -r -- "$out" | jq '.candidates | length')" -eq 0 ]] \
  && ok "Heuristic A: git status is bookkeeping, not investigation" \
  || bad "bookkeeping command produced a candidate: $out"
rm -f "$book_f"

# Variants differing only in a numeric flag value merge into one candidate.
fam_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "f1" "bun test 2>&1 | tail -8"
  mk_edit      "2026-09-01T00:00:30.000Z" "fe1"
  mk_bash_call "2026-09-01T00:01:00.000Z" "f2" "bun test 2>&1 | tail -10"
  mk_bash_call "2026-09-01T00:02:00.000Z" "f3" "bun test 2>&1 | tail -15"
} > "$fam_f"
out="$(bash "$lib/candidate-extract.sh" "$fam_f")"
n="$(print -r -- "$out" | jq '[.candidates[] | select(.heuristic=="retry-burst")] | length')"
[[ "$n" -eq 1 ]] && ok "Heuristic A: tail -8/-10/-15 merge into one candidate" \
  || bad "expected 1 merged retry-burst, got $n: $out"
rm -f "$fam_f"

# --- Heuristic B: revert / reset (needs a real tracked file) ---------------

repo_dir="$(gt_make_repo)"
gt_stage "$repo_dir" "src/broken.ts" "old content"
git -C "$repo_dir" commit -q -m "add broken.ts"
b_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "t1" "rm -rf src/broken.ts" > "$b_f"
out="$(cd "$repo_dir" && bash "$lib/candidate-extract.sh" "$b_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "revert")' >/dev/null 2>&1 \
  && ok "Heuristic B: rm -rf on a tracked file triggers revert" \
  || bad "Heuristic B did not trigger: $out"
rm -f "$b_f"
gt_cleanup "$repo_dir"

# Regression: a command that merely mentions the revert verbs is not a revert.
# The real false positive was the jq program that ran this heuristic by hand.
mention_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "m1" \
  "jq -r 'select(.command | test(\\\"git reset --hard|git revert|git restore\\\"))' /tmp/extracted.json" > "$mention_f"
out="$(bash "$lib/candidate-extract.sh" "$mention_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "revert")' >/dev/null 2>&1 \
  && bad "a command merely mentioning the revert verbs was treated as a revert: $out" \
  || ok "Heuristic B: revert verbs only count at a command position"
rm -f "$mention_f"

# A real revert behind unrelated leading commands is still found, and the title
# names the segment that matched rather than the head of the command.
seg_f="$(mktemp)"
mk_bash_call "2026-09-01T00:00:00.000Z" "s1" \
  "tmux kill-session -t smoke 2>/dev/null; git checkout -- docs/history.jsonl; echo done" > "$seg_f"
out="$(bash "$lib/candidate-extract.sh" "$seg_f")"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="revert") | .title')"
[[ "$title" == "Reverted approach: git checkout -- docs/history.jsonl." ]] \
  && ok "Heuristic B: the title names the matched segment" \
  || bad "Heuristic B title was not the matched segment: $title"
rm -f "$seg_f"

# --- Heuristic C: error recurrence ------------------------------------------

c_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "c1" "bun run build"
  mk_result    "2026-09-01T00:00:01.000Z" "c1" true "Exit code 1\\nError: Cannot find module 'foo'"
  mk_bash_call "2026-09-01T00:08:00.000Z" "c2" "bun run build"
  mk_result    "2026-09-01T00:08:01.000Z" "c2" true "Exit code 1\\nError: Cannot find module 'foo'"
} > "$c_f"
out="$(bash "$lib/candidate-extract.sh" "$c_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "error-recurrence")' >/dev/null 2>&1 \
  && ok "Heuristic C: 2x same error over >=5min triggers error-recurrence" \
  || bad "Heuristic C did not trigger: $out"
print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="error-recurrence") | .title' | grep -q 'Cannot find module' \
  && ok "Heuristic C: title carries the error message, not the exit-code line" \
  || bad "Heuristic C title was not the error message: $out"
rm -f "$c_f"

# A test runner's version banner is not the error. Prefer a line that reads
# like one.
banner_f="$(mktemp)"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "v1" "bun test"
  mk_result    "2026-09-01T00:00:01.000Z" "v1" true "Exit code 1\\nbun test v1.3.14 (0d9b296a)\\nFAIL src/x.test.ts"
  mk_bash_call "2026-09-01T00:08:00.000Z" "v2" "bun test"
  mk_result    "2026-09-01T00:08:01.000Z" "v2" true "Exit code 1\\nbun test v1.3.14 (0d9b296a)\\nFAIL src/x.test.ts"
} > "$banner_f"
out="$(bash "$lib/candidate-extract.sh" "$banner_f")"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="error-recurrence") | .title')"
[[ "$title" == *"FAIL src/x.test.ts"* ]] && ok "Heuristic C: skips the version banner for the failing line" \
  || bad "Heuristic C picked the version banner: $title"
rm -f "$banner_f"

# Long error text is capped so a recurring hook-deny message cannot become a
# several-hundred-character candidate title.
long_f="$(mktemp)"
long_err="Error: $(printf 'x%.0s' {1..400})"
{
  mk_bash_call "2026-09-01T00:00:00.000Z" "l1" "bun run build"
  mk_result    "2026-09-01T00:00:01.000Z" "l1" true "Exit code 1\\n$long_err"
  mk_bash_call "2026-09-01T00:08:00.000Z" "l2" "bun run build"
  mk_result    "2026-09-01T00:08:01.000Z" "l2" true "Exit code 1\\n$long_err"
} > "$long_f"
out="$(bash "$lib/candidate-extract.sh" "$long_f")"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="error-recurrence") | .title')"
[[ "${#title}" -lt 200 ]] && ok "Heuristic C: long error text is truncated in the title" \
  || bad "Heuristic C title was ${#title} chars: $title"
rm -f "$long_f"

# --- Heuristic D: fix burst ---------------------------------------------------

d_f="$(mktemp)"
{
  # 12 investigatory calls; the first 3 share a family, giving the cluster.
  for i in 00 01 02; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "d$i" "bun test src/bar.test.ts 2>&1 | tail -10"
    mk_result    "2026-09-01T00:${i}:01.000Z" "d$i" true "Exit code 1\\nFAIL src/bar.test.ts"
    mk_edit      "2026-09-01T00:${i}:30.000Z" "de$i"
  done
  for i in 03 04 05 06 07 08 09 10 11; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "x$i" "bun run build --target $i"
  done
  jline "{\"type\":\"assistant\",\"timestamp\":\"2026-09-01T00:15:00.000Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"dc\",\"input\":{\"command\":\"git commit -m 'fix(bar): correct off-by-one in parser'\"}}]}}"
} > "$d_f"
out="$(bash "$lib/candidate-extract.sh" "$d_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "fix-burst")' >/dev/null 2>&1 \
  && ok "Heuristic D: fix commit after a clustered investigation triggers fix-burst" \
  || bad "Heuristic D did not trigger: $out"
title="$(print -r -- "$out" | jq -r '.candidates[] | select(.heuristic=="fix-burst") | .title')"
[[ "$title" == "fix(bar): correct off-by-one in parser"* ]] \
  && ok "Heuristic D: title starts with the parsed commit subject" \
  || bad "Heuristic D title was not the parsed subject: $title"
[[ "$title" != *"git commit"* ]] && ok "Heuristic D: title carries no raw command text" \
  || bad "Heuristic D title leaked the raw command: $title"
rm -f "$d_f"

# A fix commit with no retry cluster in its window is a straightforward fix.
d2_f="$(mktemp)"
{
  for i in 00 01 02 03 04 05 06 07 08 09 10 11; do
    mk_bash_call "2026-09-01T00:${i}:00.000Z" "y$i" "bun run build --target $i"
  done
  jline "{\"type\":\"assistant\",\"timestamp\":\"2026-09-01T00:15:00.000Z\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"dc2\",\"input\":{\"command\":\"git commit -m 'fix(bar): rename a variable'\"}}]}}"
} > "$d2_f"
out="$(bash "$lib/candidate-extract.sh" "$d2_f")"
print -r -- "$out" | jq -e '.candidates | any(.heuristic == "fix-burst")' >/dev/null 2>&1 \
  && bad "fix-burst fired with no retry cluster in the window: $out" \
  || ok "Heuristic D: no retry cluster means no fix-burst"
rm -f "$d2_f"

# --- per-heuristic cap --------------------------------------------------------

cap_f="$(mktemp)"
{
  for fam in alpha beta gamma; do
    for i in 1 2 3; do
      mk_bash_call "2026-09-01T0${i}:0${i}:00.000Z" "$fam$i" "bun test src/$fam.test.ts"
    done
    mk_edit "2026-09-01T01:30:00.000Z" "ce$fam"
  done
} > "$cap_f"
out="$(bash "$lib/candidate-extract.sh" "$cap_f")"
n="$(print -r -- "$out" | jq '[.candidates[] | select(.heuristic=="retry-burst")] | length')"
[[ "$n" -eq 2 ]] && ok "per-heuristic cap keeps at most 2 retry-bursts" \
  || bad "expected 2 retry-bursts after the cap, got $n: $out"
[[ "$(print -r -- "$out" | jq .overflow)" -eq 1 ]] && ok "the capped candidate is counted in overflow" \
  || bad "overflow did not count the capped candidate: $out"
rm -f "$cap_f"

# --- privacy ------------------------------------------------------------------

priv_f="$(mktemp)"
{
  for i in 1 2 3; do
    mk_bash_call "2026-09-01T00:0${i}:00.000Z" "p$i" "bun test /Users/someone/secretproj/src/a.test.ts"
  done
  mk_edit "2026-09-01T00:01:30.000Z" "pe1"
} > "$priv_f"
out="$(bash "$lib/candidate-extract.sh" "$priv_f")"
print -r -- "$out" | grep -q '/Users/someone/' \
  && bad "a home directory path reached the candidate output: $out" \
  || ok "home directory paths are rewritten to ~/"
rm -f "$priv_f"
```

- [ ] **Step 2: Run the tests, confirm they fail**

Run: `zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: failures on the heredoc regression, the bookkeeping regression, the family merge, the no-edit case, the Heuristic C 2-occurrence case, the fix-burst subject assertions, the per-heuristic cap, and privacy.

- [ ] **Step 3: Rewrite `hooks/lib/candidate-extract.jq`**

```jq
# CONTRACT_VERSION=2
# hooks/lib/candidate-extract.jq — LEARNINGS candidate extraction + heuristics.
# Invoked via: jq -n --argjson tracked_files <json array from `git ls-files`> \
#   -f candidate-extract.jq <transcript.jsonl>
# See meta/superpowers/plans/2026-09-01-learnings-generation-hardening.md.
#
# Every rule here was validated by replaying it over four real multi-megabyte
# session transcripts. The prose in commands/end-session.md documents what this
# file decides; this file is the only thing that decides it.

# Never throws: a record with a timestamp this cannot parse yields null and is
# skipped, instead of aborting the whole filter and rendering as "no candidates".
def to_epoch: try (gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null;

def redact_paths: gsub("/(Users|home)/[^/ ]+/"; "~/");

# Command identity: the whole command with every run of whitespace — newlines
# included — collapsed. Two heredocs with different bodies are different
# commands; identical re-runs remain identical.
def norm_full: gsub("[ \t\r\n]+"; " ") | sub("^ +"; "") | sub(" +$"; "");

def strip_prefix:
  sub("^cd +[^ ]+ +&& +"; "")
  | sub("^timeout +[0-9]+ +"; "")
  | sub("^env +[A-Za-z_][A-Za-z0-9_]*=[^ ]+ +"; "");

# Family key: digits that follow a `-` or `=` are argument values, so
# `tail -8` and `tail -15` are one family. Digits elsewhere (dates in
# filenames, PR numbers) stay, so unrelated commands do not merge.
def fam_key:
  gsub("(?<p>[-=])[0-9]+"; "\(.p)N")
  | gsub("[0-9]+>&[0-9]+"; "N>&N");

def is_bookkeeping:
  strip_prefix
  | (test("^(cat|ls|grep|rg|find|stat|pwd|which|echo|printf|wc|head|tail|sed|awk|jq|du|file|date|env|tree|mkdir|touch|chmod|open)( |$)")
     or test("^git +(status|diff|log|show|branch|add|commit|stash|rev-parse|ls-files)( |$)"));

# A git verb only counts when it sits at a command position. Without this, any
# command whose *text* mentions "git revert" matches — including, measurably,
# the jq program the agent used to run this very heuristic by hand.
def is_revert:
  (test("(^|&& |; |\\| )git +reset +--hard"))
  or (test("(^|&& |; |\\| )git +revert( |$)"))
  or (test("(^|&& |; |\\| )git +restore( |$)"))
  or (test("(^|&& |; |\\| )git +checkout +-- "));

# Show the segment that matched, not the head of a compound command: a real
# `git checkout -- <path>` was found sitting behind two tmux teardowns.
def revert_segment:
  ([splits(" *(&&|;|\\|) *")] | map(select(length > 0))) as $segs
  | (($segs | map(select(is_revert or test("^rm +-rf +"))) | .[0]) // ($segs | .[0]) // .);

def display_of:
  (split("\n")[0]) as $first
  | (if ($first | length) > 76 then ($first[0:76] + "…")
     elif test("\n") then ($first + " …")
     else $first end)
  | redact_paths;

# Prefer a line that reads like an error over the first line of output — the
# first line of a failing `bun test` is its version banner, which produced the
# title "bun test v1.3.14 (0d9b296a) — recurred 2 times" on a real transcript.
def error_line:
  (split("\n") | map(select(length > 0)) | map(select(test("^Exit code") | not))) as $ls
  | (($ls | map(select(test("(?i)(error|fail|fatal|cannot|can.t|no such|not found|no matches|denied|refused|unexpected|invalid|missing)"))) | .[0])
     // ($ls | .[0])
     // "")
  | .[0:160];

def norm_err:
  if (. == null or . == "") then ""
  else
    redact_paths
    | gsub("(?<p>/[^ :\"]+/)(?<b>[^/ :\"]+)"; "\(.b)")
    | gsub(":[0-9]+:[0-9]+"; "")
    | gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?"; "")
    | gsub("[0-9]{2}:[0-9]{2}:[0-9]{2}"; "")
    | gsub("0x[0-9a-fA-F]+"; "0xN")
    | norm_full
  end;

# The subject only: from -m "…", -m '…', or the first non-empty line of a
# heredoc body. Never the whole command — a real commit body ran to 20 lines.
def commit_subject:
  . as $c
  | if ($c | test("<<[ ]*'?\"?EOF")) then
      (($c | split("\n") | .[1:] | map(select(length > 0)) | .[0]) // "unrecorded")
    else
      ((try ($c | capture("-m +\"(?<s>[^\"]*)\"") | .s) catch null)
       // (try ($c | capture("-m +'(?<s>[^']*)'") | .s) catch null)
       // "unrecorded")
    end;

def title_words:
  ascii_downcase
  | gsub("[^a-z0-9 ]+"; " ")
  | [splits(" +")]
  | map(select(length > 0));

def overlap($ta; $tb):
  ($ta | title_words) as $wa
  | ($tb | title_words) as $wb
  | ($wa + $wb | unique) as $u
  | if ($u | length) == 0 then 0
    else (($wa - ($wa - $wb)) | length) / ($u | length)
    end;

[inputs] as $lines

# --- shared extraction -------------------------------------------------------
| ($lines
    | map(select(.type=="assistant"))
    | map(. as $l | $l.message.content[]?
        | select(.type=="tool_use")
        | {ts: $l.timestamp, name: .name, id: (.id // ""), command: (.input.command // "")})
  ) as $tool_uses

| ($tool_uses
    | map(select(.name=="Edit" or .name=="Write" or .name=="MultiEdit"))
    | map(.ts) | sort
  ) as $edit_ts

| ($lines
    | map(select(.type=="user" and (.message.content|type)=="array"))
    | map(. as $l | $l.message.content[]?
        | select(.type=="tool_result")
        | {ts: $l.timestamp,
           tool_use_id: (.tool_use_id // ""),
           is_error: (.is_error // false),
           text: (.content | if type=="string" then . else tostring end)})
  ) as $tool_results

# Failure signal: is_error, or a body that opens with a non-zero exit line.
# stderr and a leading "Error:" matched nothing across 1155 real tool results.
| ($tool_results
    | map(. + {err: (if (.is_error or (.text | test("^Exit code [1-9]")))
                     then (.text | error_line)
                     else "" end)})
  ) as $results

| ($results | map({key: .tool_use_id, value: .}) | from_entries) as $by_id

| ($tool_uses
    | map(select(.name=="Bash"))
    | map(. as $b
        | ($by_id[$b.id] // {is_error: false, err: ""}) as $r
        | {ts: $b.ts,
           command: $b.command,
           key: ($b.command | norm_full),
           fam: ($b.command | norm_full | fam_key),
           is_error: $r.is_error,
           err: ($r.err | norm_err)})
  ) as $bash

# --- Heuristic A: retry burst ------------------------------------------------
| ($bash
    | map(select(.key | is_bookkeeping | not))
    | group_by(.fam)
    | map(select(length >= 3))
    | map(. as $g
        | ($g | group_by(.key) | max_by(length)) as $top
        | ([$edit_ts[] | select(. > $g[0].ts and . < $g[-1].ts)] | length) as $edits
        | if $edits >= 1 then
            {heuristic: "retry-burst",
             title: (($top[0].command | display_of)
                     + " — re-run " + ($g | length | tostring)
                     + " times with " + ($edits | tostring) + " file edits in between."),
             evidence: ($g[0:3] | map("Bash @ " + .ts + " → "
                        + (if .err != "" then ("failed: " + .err) else "ok" end))),
             evidence_count: ($g | length)}
          else empty
          end)
  ) as $heuristic_a

# --- Heuristic B: revert / reset ---------------------------------------------
| ($bash
    | map(select(
        (.key | is_revert)
        or ((.key | test("(^|&& |; )rm +-rf +"))
            and ((.key | [splits(" +")]) as $toks
                 | $tracked_files
                 | any(. as $f
                       | ($f | length) > 0
                       and ($toks | any(. as $t | $t == $f or ($f | startswith($t + "/")))))))))
    | map({heuristic: "revert",
           title: ("Reverted approach: " + (.key | revert_segment | display_of) + "."),
           evidence: [("Bash @ " + .ts + " → " + (.key | revert_segment | display_of))],
           evidence_count: 1})
  ) as $heuristic_b

# --- Heuristic C: error recurrence -------------------------------------------
| ($bash | map(select(.err != "")) | map({ts: .ts, err: .err})) as $errors
| ($errors
    | group_by(.err)
    | map(select(length >= 2))
    | map(. as $g
        | ((($g[-1].ts | to_epoch) // 0) - (($g[0].ts | to_epoch) // 0)) as $span
        | if $span >= 300 then
            {heuristic: "error-recurrence",
             title: ("\"" + ($g[0].err | if length > 120 then .[0:120] + "…" else . end)
                     + "\" — recurred " + ($g | length | tostring)
                     + " times over " + (($span / 60) | floor | tostring) + " minutes."),
             evidence: ($g[0:3] | map("@ " + .ts)),
             evidence_count: ($g | length)}
          else empty
          end)
  ) as $heuristic_c

# --- Heuristic D: fix burst ---------------------------------------------------
| ($bash
    | map(select(.key | test("git +commit")))
    | map(. + {subject: (.command | commit_subject)})
    | map(select(.subject | test("^fix(\\([^)]*\\))?: ")))
  ) as $fix_commits
| ($fix_commits
    | map(. as $c
        | (($c.ts | to_epoch) // null) as $e
        | if $e == null then empty
          else
            ($bash | map(select(
                ((.ts | to_epoch) // 0) < $e
                and ((.ts | to_epoch) // 0) >= ($e - 1800)
                and (.key | is_bookkeeping | not)))) as $w
            | ($w | group_by(.fam) | map(select(length >= 3)) | length) as $clusters
            | if ($w | length) >= 10 and $clusters >= 1 then
                {heuristic: "fix-burst",
                 title: ($c.subject + " — fix preceded by a "
                         + ($w | length | tostring) + "-action investigation."),
                 evidence: ([$w[0], $w[(($w | length) / 2 | floor)], $w[-1]]
                            | map("Bash @ " + .ts + " → " + (.command | display_of))),
                 evidence_count: ($w | length)}
              else empty
              end
          end)
  ) as $heuristic_d

# --- union, dedupe, per-heuristic cap, overall cap ---------------------------
| ($heuristic_a + $heuristic_b + $heuristic_c + $heuristic_d) as $all
| ($all | sort_by(-.evidence_count)) as $sorted
| (reduce $sorted[] as $cand ([];
      if (. as $kept | any($kept[]; overlap($cand.title; .title) >= 0.7)) then .
      else . + [$cand]
      end)) as $deduped
| (reduce $deduped[] as $cand ({kept: [], counts: {}};
      ((.counts[$cand.heuristic] // 0)) as $n
      | if $n >= 2 then .
        else {kept: (.kept + [$cand]),
              counts: (.counts | .[$cand.heuristic] = ($n + 1))}
        end)
   | .kept) as $balanced
| ($balanced[0:5] | map(del(.evidence_count))) as $capped
| {mode: "transcript",
   candidates: $capped,
   overflow: (($deduped | length) - ($capped | length)),
   detail: ""}
```

- [ ] **Step 4: Run the tests, confirm they pass**

Run: `zsh meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh`
Expected: `0 failed`. Every assertion in the file runs, including the ones Task 3 added.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/candidate-extract.jq meta/superpowers/validation/2026-09-01-candidate-extract-smoke.zsh
git commit -m "fix: retune the LEARNINGS heuristics against real transcripts

Replaying the shipped filter over four real sessions produced titles like
\"bun -e ' — investigated for 6 retries\", \"git status --short — investigated
for 4 retries\", and fix-burst titles carrying an entire 20-line commit body.
Command identity is now the full normalized text rather than the first line,
near-variants merge on a digit-family key, bookkeeping commands are excluded,
a retry burst requires an intervening file edit, fix bursts use the parsed
subject and require a retry cluster in their window, error recurrence reads the
signal that actually exists in the schema, and no heuristic may contribute more
than 2 of the 5 candidates."
```

---

### Task 5: Replay harness for real transcripts (F3, F4, F11)

The smoke tests are hermetic and prove the rules behave as written. They cannot prove the rules are the right rules — that took real transcripts, and nothing in the repo lets a future contributor repeat it. This task ships the tool.

**Files:**
- Create: `meta/superpowers/validation/2026-09-01-candidate-replay.zsh`
- Modify: `CONTRIBUTING.md:80-86` (document it alongside the hook smoke runners)

**Interfaces:**
- Consumes: `hooks/lib/candidate-extract.jq` from Task 4. It calls the jq filter directly rather than `candidate-extract.sh`, because archived transcripts are by definition stale and the wrapper would correctly reject every one of them.
- Produces: a human-readable report on stdout. Not a pass/fail runner — it takes no position on what the right candidates are, it shows what the current rules produce so a human can judge.

- [ ] **Step 1: Write the harness**

Create `meta/superpowers/validation/2026-09-01-candidate-replay.zsh`:

```zsh
#!/usr/bin/env zsh
# Replays hooks/lib/candidate-extract.jq over a directory of archived Claude
# Code transcripts and prints what each one would produce. NOT a pass/fail
# smoke test — archived transcripts are not in the repo and differ per machine.
# Run this after changing any heuristic and read the output: a candidate list
# full of heredoc fragments or bookkeeping commands means the rules regressed.
#
# Usage:
#   zsh meta/superpowers/validation/2026-09-01-candidate-replay.zsh [dir] [n]
#
#   dir  directory of *.jsonl transcripts
#        (default: ~/.claude/projects/<url-encoded cwd of this repo>)
#   n    how many of the largest transcripts to replay (default 6)
#
# It calls the .jq filter directly, bypassing candidate-extract.sh's 5-minute
# staleness guard, which would reject every archived file by design.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
filter="$repo/hooks/lib/candidate-extract.jq"

default_dir() {
  local enc="${PWD//\//-}"
  print -r -- "$HOME/.claude/projects/$enc"
}

dir="${1:-$(default_dir)}"
count="${2:-6}"

if [[ ! -d "$dir" ]]; then
  print -u2 "no transcript directory at $dir"
  print -u2 "pass one explicitly: zsh ${0:t} ~/.claude/projects/<encoded-cwd> 6"
  exit 1
fi

files=("${(@f)$(ls -S -- "$dir"/*.jsonl 2>/dev/null | head -"$count")}")
if (( ${#files} == 0 )); then
  print -u2 "no .jsonl transcripts in $dir"
  exit 1
fi

tracked="$(git ls-files 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null || print -r -- '[]')"

for f in $files; do
  [[ -n "$f" ]] || continue
  size="$(du -h "$f" | cut -f1)"
  start=$(date +%s%N 2>/dev/null | sed 's/N$/0/')
  out="$(jq -n --argjson tracked_files "$tracked" -f "$filter" "$f" 2>&1)"
  end=$(date +%s%N 2>/dev/null | sed 's/N$/0/')
  print -P "%F{cyan}== ${f:t} ($size, $(( (end - start) / 1000000 ))ms)%f"
  if ! print -r -- "$out" | jq -e . >/dev/null 2>&1; then
    print -P "  %F{red}filter error:%f $out"
    continue
  fi
  print -r -- "$out" | jq -r '
    "  mode=\(.mode) candidates=\(.candidates|length) overflow=\(.overflow)",
    (.candidates[] | "  [\(.heuristic)] \(.title)"),
    (.candidates[] | .evidence[0] | "      e: \(.)")'
done

print ""
print "Read the titles. Each one should name a command or a commit subject you"
print "recognise as a real investigation. Heredoc fragments (\"bun -e '\"),"
print "bookkeeping commands (\"git status\"), and raw multi-line commit bodies"
print "are regressions, not candidates."
```

- [ ] **Step 2: Run it against the real transcript archive**

Run:

```bash
zsh meta/superpowers/validation/2026-09-01-candidate-replay.zsh \
  ~/.claude/projects/-Users-tal-golan-active-development-TG-architect-workbench 4
```

Expected, matching the measured prototype:

```
== 67fb9ff8-3f6c-4f07-84e9-1187937bdd50.jsonl (14M, ~150ms)
  mode=transcript candidates=2 overflow=0
  [retry-burst] timeout 90 bun run --cwd ~/active_development/TG/architect-wo… — re-run 23 times with 123 file edits in between.
  [retry-burst] bun test 2>&1 | tail -15 — re-run 8 times with 152 file edits in between.
```

Each of the four transcripts must show between 2 and 5 candidates, no title beginning `bun -e '`, `jq -r '`, or `git commit`, no title containing a newline, and no title longer than about 160 characters. If any of those appear, stop and fix Task 4 rather than proceeding — that is the whole point of running this before shipping.

- [ ] **Step 3: Document the harness in CONTRIBUTING.md**

Add after the existing `zsh meta/superpowers/validation/2026-08-06-smoke-gate-smoke.zsh` example:

```markdown
The LEARNINGS candidate heuristics also have a non-hermetic replay harness. The
hermetic smoke test proves the rules do what they say; the replay shows what
they produce on real sessions, which is the only way to catch a rule that is
faithfully implemented and wrong:

```bash
zsh meta/superpowers/validation/2026-09-01-candidate-replay.zsh ~/.claude/projects/<encoded-cwd> 6
```

Run it after any change to `hooks/lib/candidate-extract.jq` and read the titles.
```

- [ ] **Step 4: Commit**

```bash
git add meta/superpowers/validation/2026-09-01-candidate-replay.zsh CONTRIBUTING.md
git commit -m "test: add a real-transcript replay harness for the candidate heuristics

The hermetic smoke fixtures were built from the same assumptions as the rules
they test, so they passed while the rules produced heredoc fragments on every
real session. This replays the filter over archived transcripts and prints what
a human has to read to catch that class of failure."
```

---

### Task 6: Rewire the command prose (F10, and the new `mode:"error"`)

**Files:**
- Modify: `commands/end-session.md:360-380` (the extraction call), `:391-470` (heuristic documentation and output rules), `:563-573` (the capture flow's reindex call)
- Modify: `commands/learning.md:54-77` (Step 4), `:110-128` (Step 6)

**Interfaces:**
- Consumes: `candidate-extract.sh` `CONTRACT_VERSION=2` producing `mode`/`candidates`/`overflow`/`detail`; `learnings-index.sh` `CONTRACT_VERSION=2` exiting 2 on an install fault.
- Produces: no script interface. This is the last task that can reintroduce the original cost problem, because prose is what the agent reads.

- [ ] **Step 1: Replace the extraction call block in `commands/end-session.md`**

Replace the fenced bash block under `### Candidate extraction (transcript-file mode only)` (currently lines 367-379, the one containing `_PERF_START`) with:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" 2; then
  CANDIDATE_JSON="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/candidate-extract.sh" "$TRANSCRIPT")"
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  CANDIDATE_JSON='{"mode":"error","candidates":[],"overflow":0,"detail":"candidate-extract.sh is missing or outdated."}'
fi
```

and replace the sentence following it with:

```markdown
The script times itself — do not wrap this call in a timer, and do not add a
`perf-log.sh record` line for `step-2-transcript-extraction`; you would
double-log it.

Parse `$CANDIDATE_JSON`'s `.mode`, `.candidates[]` (each with `.heuristic`,
`.title`, `.evidence[]`), `.overflow`, and `.detail`.
```

- [ ] **Step 2: Rewrite the heuristics section header in `commands/end-session.md`**

Replace the two lines under `### Heuristics` (currently line 393 plus the "Apply each heuristic…" sentence at line 395-397) with:

```markdown
`hooks/lib/candidate-extract.jq` decides all of this. The subsections below
record what it decides so a reader can audit the output without reading jq —
they are **not instructions to you**. In transcript-file mode you have already
received the finished candidate list from the script; do not re-derive, re-filter,
or re-check any of it. Re-deriving these by hand is what made this step cost
~88 seconds of round trips before the script existed (Finding 2 of the design
spec).

In context-window mode there is no script and no transcript to run it against.
There, and only there, apply the rules below by hand against what you can still
see in the conversation, skipping the wall-clock gates you cannot evaluate.
```

- [ ] **Step 3: Correct the drifted heuristic documentation in `commands/end-session.md`**

Under `#### Heuristic A — retry burst`, replace the bullet list and Trigger/Title/Evidence lines with:

```markdown
Commands are grouped by **full normalized text** — every run of whitespace,
newlines included, collapsed to a single space. A heredoc's body is part of its
identity, so two commits with different messages are two commands, not two runs
of one.

Near-variants merge on a **family key**: digits following a `-` or `=` are
rewritten to `N`, so `tail -8` and `tail -15` are one family, while
`gh pr merge 22` and `gh pr merge 24` are not (that digit follows a space).

Bookkeeping commands never count: `cat`, `ls`, `grep`, `rg`, `find`, `stat`,
`pwd`, `which`, `echo`, `printf`, `wc`, `head`, `tail`, `sed`, `awk`, `jq`,
`du`, `file`, `date`, `env`, `tree`, `mkdir`, `touch`, `chmod`, `open`, and
`git status|diff|log|show|branch|add|commit|stash|rev-parse|ls-files` — tested
after stripping a leading `cd <path> &&`, `timeout <n>`, or `env VAR=x`.

**Trigger:** one command family appears ≥3 times AND at least one `Edit`,
`Write`, or `MultiEdit` call falls between the first and last occurrence. A
command repeated with no intervening edit is polling, not investigation.

**Candidate title:** `<command> — re-run N times with M file edits in between.`

**Evidence:** up to 3 timestamps, each annotated `ok` or `failed: <first error line>`.
```

Under `#### Heuristic B — revert / reset`, replace the "Candidate title" and "Evidence" lines with:

```markdown
A git verb counts only at a **command position** — the start of the command, or
directly after `&&`, `;`, or `|`. A command that merely contains the string
`git revert` (a jq program filtering for it, say) is not a revert. The `rm -rf`
branch requires a tracked path to appear as an actual argument token, or as a
parent directory of one, not as a substring anywhere in the command.

**Candidate title:** `Reverted approach: <the matched segment, ≤76 chars>.` The
segment, not the head of the command — a real `git checkout -- <path>` was found
sitting behind two unrelated `tmux kill-session` calls.

**Evidence:** the offending Bash invocation.
```

Under `#### Heuristic C — error recurrence`, replace the source bullets and Trigger line with:

```markdown
The error string comes from any tool result that either carries `is_error: true`
or whose body opens with `Exit code <non-zero>`. Within that body, the first
line matching an error vocabulary (`error`, `fail`, `fatal`, `cannot`, `no such`,
`not found`, `no matches`, `denied`, `refused`, `unexpected`, `invalid`,
`missing`) wins over the first line of output, because the first line of a
failing `bun test` is its version banner. Capped at 160 characters, and at 120
in the title. Normalized: home directories
rewritten to `~/`, absolute paths reduced to basenames, `:line:col` refs,
ISO-8601 and `HH:MM:SS` timestamps, and hex addresses stripped.

**Trigger:** the same normalized error appears ≥2 times spanning ≥5 minutes.
(Measured on real transcripts: a multi-megabyte session carries 5-8 error
results total, so the previous ≥3-over-15-minutes threshold could never fire.)
```

Under `#### Heuristic D — fix burst`, replace the Trigger and Candidate title lines with:

```markdown
**Trigger:** a commit whose **parsed subject** — from `-m "…"`, `-m '…'`, or
the first non-empty line of a `<<'EOF'` body — matches `^fix(\(…\))?: `, AND
whose preceding 30 minutes contain ≥10 non-bookkeeping Bash calls, AND among
those a command family repeated ≥3 times. Without that cluster the fix was
straightforward and there is nothing to learn; with the cluster requirement,
one measured session went from 8 fix-burst candidates to 3.

**Candidate title:** `<commit subject> — fix preceded by a N-action investigation.`
The subject only — never the raw command, which on a real commit runs to 20
lines including the trailer.
```

- [ ] **Step 4: Add the caps and the `mode:"error"` branch to the Output section**

In `### Output`, replace the `mode:"unavailable"` bullet and add a new one:

```markdown
- **`mode:"unavailable"`**: the transcript could not be used (absent, stale,
  unreadable). Fall back to context-window mode exactly as before, and append
  the compaction note to the candidate list.
- **`mode:"error"`**: the plugin or its environment is broken — print
  `⚠️ LEARNINGS candidates unavailable: <detail>` using `.detail` verbatim,
  then continue to Step 3. Do **not** silently treat this as "no candidates";
  a derivation that fails invisibly is the failure this whole design exists to
  prevent.
- **`.overflow > 0`**: append the `+N more candidates…` line as before. Note
  that no heuristic contributes more than 2 of the 5 shown, so an overflow can
  mean "one signal fired many times", not "there are 5 better ones hidden".
- **Zero candidates** (`.candidates` empty, `.overflow` 0, `mode:"transcript"`):
  print `No LEARNINGS candidates surfaced from this session — Step 2 is a no-op.`
```

Then update the `### Presentation` example block's first entry to the new title shape:

```
1. [retry-burst] `bun test 2>&1 | tail -10` — re-run 31 times with 112 file edits in between.
   Evidence:
   - Bash @ 2026-09-01T00:12:04Z → failed: FAIL src/foo.test.ts
   - Bash @ 2026-09-01T00:19:41Z → failed: FAIL src/foo.test.ts
   - Bash @ 2026-09-01T00:26:02Z → ok
```

- [ ] **Step 5: Handle the reindex install fault in the capture flow**

In `commands/end-session.md`, replace the reindex block (currently lines 566-572) with:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 2; then
  if ! bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" reindex .session-continuity/LEARNINGS.md; then
    echo "⚠️ Symptoms index not regenerated — LEARNINGS.md was left untouched (see the message above)."
  fi
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG — Symptoms index not regenerated this run."
fi
git add .session-continuity/LEARNINGS.md
```

- [ ] **Step 6: Make the same two edits in `commands/learning.md`**

Step 4's block becomes:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 2; then
  REPORT="$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" report .session-continuity/LEARNINGS.md)"
  if [ -z "$REPORT" ]; then
    echo "⚠️ learnings-index.sh report failed — see the message above."
  fi
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
  REPORT=""
fi
```

Step 6's block becomes:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" 2; then
  if ! bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/learnings-index.sh" reindex .session-continuity/LEARNINGS.md; then
    echo "⚠️ Symptoms index not regenerated — LEARNINGS.md was left untouched (see the message above)."
  fi
else
  echo "⚠️ $SC_REQUIRE_SCRIPT_MSG — Symptoms index not regenerated this run."
fi
```

Add one sentence to Step 4's item 1, after the duplicate-number refusal paragraph:

```markdown
An empty `$REPORT` means the script could not run at all — report that and stop,
rather than treating it as "no duplicates found".
```

- [ ] **Step 7: Verify the contract versions line up**

Run:

```bash
grep -n 'CONTRACT_VERSION=' hooks/lib/candidate-extract.sh hooks/lib/candidate-extract.jq \
  hooks/lib/learnings-index.sh hooks/lib/learnings-index-*.awk
grep -n 'require_script' commands/*.md
```

Expected: every listed file reports `CONTRACT_VERSION=2`, and every `require_script` call in `commands/` passes `2`. Any `1` left in either list is version skew that would fire on the next run.

- [ ] **Step 8: Commit**

```bash
git add commands/end-session.md commands/learning.md
git commit -m "docs: align Step 2 prose with the scripts it delegates to

The heuristics section still opened with 'Apply each heuristic to the resolved
input source' inside the block labelled as documentation, which is an
instruction to re-derive exactly what the script already returned. It now says
what the script decides and, separately, what to do in context-window mode.
Heuristic A/B/C/D documentation matches the retuned rules, both commands require
CONTRACT_VERSION=2, and mode:'error' and a failed reindex are surfaced instead
of read as 'nothing to report'."
```

---

### Task 7: Run the ritual end to end and release (F11)

Nothing in Tasks 1-6 proves the ritual works, only that the pieces do. The spec's end-to-end check has never been run.

**Files:**
- Modify: `.claude-plugin/plugin.json` (version)
- Modify: `CHANGELOG.md` (new section at the top)
- Create: `meta/superpowers/validation/2026-09-01-learnings-hardening-verification.md`

**Interfaces:**
- Consumes: everything from Tasks 1-6.
- Produces: a validation record naming what was run and what it produced, in the style of `meta/superpowers/validation/2026-07-30-outstanding-items-verification.md`.

- [ ] **Step 1: Run every affected smoke suite**

Run:

```bash
for t in require-script candidate-extract learnings-index; do
  echo "=== $t"
  zsh meta/superpowers/validation/2026-09-01-$t-smoke.zsh
done
```

Expected: `0 failed` from all three. Record the pass counts.

- [ ] **Step 2: Install the working copy into the plugin cache and run the ritual**

The measured failure in F11 was that a completed change never executed, because commands run from `${CLAUDE_PLUGIN_ROOT}`, not from the repo. Sync first:

```bash
CACHE="$HOME/.claude/plugins/cache/talgolan/session-continuity"
ls "$CACHE"          # note the version directory in use
```

Copy `hooks/`, `commands/`, and `.claude-plugin/` from the repo into that directory (or reinstall the plugin from the working tree, whichever the local setup uses), then start a fresh Claude Code session in a scratch git repo with a `.session-continuity/` directory and run `/session-continuity:end-session`.

- [ ] **Step 3: Confirm the four end-to-end invariants**

In the scratch repo, run:

```bash
grep -E 'step-2-transcript-extraction|step-4-agent-active|step-4-compute-only' .session-continuity/performance.log
```

Expected:
- exactly one `step-2-transcript-extraction` line for the invocation, with `duration_s` under 1.0;
- one `step-4-agent-active` line with a plausible value;
- zero `step-4-compute-only` lines;
- in the session transcript, exactly one Bash call to `candidate-extract.sh` and no follow-up `jq` call against a temp file — the behaviour Finding 2 measured as seven round trips.

- [ ] **Step 4: Write the validation record**

Create `meta/superpowers/validation/2026-09-01-learnings-hardening-verification.md` covering: the three smoke suites and their pass counts; the replay output for at least four real transcripts, pasted; the four end-to-end invariants above with the actual log lines; and the before/after candidate counts per transcript. State plainly anything that did not hold.

- [ ] **Step 5: Bump the version and write the changelog**

`.claude-plugin/plugin.json`: `"version": "0.25.0"`.

Add to `CHANGELOG.md` above the `## [0.24.0]` section:

```markdown
## [0.25.0] — 2026-09-01

### Fixed
- **`hooks/lib/learnings-index.sh reindex` could empty `LEARNINGS.md`.** It copied awk's output over the source file without checking awk's exit status, so a missing `.awk` sibling — an interrupted or partial plugin-cache update — produced an empty temp file that was then written over the corpus, with exit 0 and the message `regenerated 0 bullet(s)`. The write site now verifies every sibling's presence and contract version, checks each awk exit status, and requires the regenerated file to be non-empty with an unchanged entry count. Installation faults exit 2 and never open the target for writing.
- **LEARNINGS candidate heuristics produced mostly noise on real sessions.** Replaying the v0.23.0 filter over four real multi-megabyte transcripts produced titles like `bun -e ' — investigated for 6 retries`, `git status --short — investigated for 4 retries`, and fix-burst titles carrying an entire multi-line commit body — one session surfaced five heredoc fragments plus an eight-candidate overflow warning. Command identity is now the full normalized command text rather than its first line, near-variants merge on a digit-family key, bookkeeping commands are excluded, a retry burst requires an intervening file edit, fix bursts use the parsed commit subject and require a repeated-command cluster in their window, and no heuristic contributes more than two of the five candidates.
- **Error recurrence could never fire.** It read `toolUseResult.stderr` and lines beginning `Error:`, neither of which appears in the current transcript schema (0 matches across 1,155 real tool results), and then required three identical errors spanning fifteen minutes. It now reads `is_error` results and bodies opening with a non-zero `Exit code` line, at two occurrences spanning five minutes.
- **Every candidate-extraction failure looked like "no candidates".** A missing `jq`, a missing or version-skewed filter file, and any filter runtime error all returned `mode:"unavailable"`. They now return `mode:"error"` with a `detail` string the command prints. A malformed timestamp no longer aborts the whole filter.
- **The transcript staleness guard was skipped on GNU coreutils**, where `stat -f %m` means `--file-system`, writes to stdout, and exits 1 — polluting the mtime value so the age check silently never ran.
- **The Symptoms index could be spliced into YAML front matter**, and entry headings inside fenced code examples counted as real entries, producing false duplicate-number reports that block `/session-continuity:learning` from appending.

### Changed
- `hooks/lib/candidate-extract.sh` times itself through `perf-log.sh` instead of relying on a timing wrapper in the command prose.
- `commands/end-session.md` Step 2's heuristic section no longer instructs the agent to "apply each heuristic"; it documents what `candidate-extract.jq` decides and scopes hand-application to context-window mode, where no script can run.
```

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md meta/superpowers/validation/2026-09-01-learnings-hardening-verification.md
git commit -m "chore: bump to 0.25.0 — LEARNINGS write gate, retuned heuristics, failure taxonomy"
```

---

## Not in this plan

- **`hooks/lib/agent-active.sh`.** It shares the throwing `to_epoch` with the candidate filter, and its fallback path treats only `turn_duration` as a turn boundary while the schema also carries `away_summary` on exactly the idle stretches that matter. Every transcript checked carries `turn_duration`, so the fallback is currently unexecuted code. That is a separate mechanism from LEARNINGS generation and gets its own plan; the spec's "fallback coverage" test item is still outstanding either way.
- **Retiring `mode:"unavailable"`'s context-window fallback.** Step 2's hand-applied path stays, because a session that outran its context window has no transcript and no script can help it.
- **The `LEARNINGS.md` file format.** Unchanged, as in the original spec.
- **Token accounting.** Still deferred.

## Self-review

- **Spec coverage.** The original spec's Change 1 and Change 3 are what this plan repairs. Its Testing plan items "Replay against the archived transcripts", "Index script", and "End to end" are implemented as Tasks 5, 2, and 7. "Metric correction" and "Fallback coverage" belong to `agent-active.sh` and are listed above as out of scope, not silently dropped.
- **Type consistency.** `mode`, `candidates`, `overflow`, `detail` are the four output keys throughout Tasks 3, 4, and 6. `heuristic` values are exactly `retry-burst`, `revert`, `error-recurrence`, `fix-burst` in the jq, the smoke tests, and the presentation block. `report`/`reindex` subcommand names and the `MAX`/`DUPNUM`/`DUPSLUG` output lines are unchanged from v0.23.0, so `learning.md`'s parsing needs no edit beyond the empty-`$REPORT` check.
- **Contract versions.** Six files move to `CONTRACT_VERSION=2` (`candidate-extract.sh`, `candidate-extract.jq`, `learnings-index.sh`, and the three `.awk` files) and four `require_script` call sites move to `2`. Task 6 Step 7 checks this mechanically.
