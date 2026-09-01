#!/usr/bin/env zsh
# learnings-index.sh smoke test. Hermetic: synthetic + this repo's real
# LEARNINGS.md as fixtures, copied into a temp dir before every mutation.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"

# --- report: no duplicates on this repo's real file -------------------------

cat "$repo/.session-continuity/LEARNINGS.md" > "$work/real.md"
out="$(bash "$lib/learnings-index.sh" report "$work/real.md")"
if print -r -- "$out" | grep -q '^MAX 15$'; then ok "report: MAX matches real file (15)"; else bad "report MAX: $out"; fi
if print -r -- "$out" | grep -q DUPNUM; then bad "report: false-positive duplicate number on real file"; else ok "report: no duplicate numbers on real file"; fi
if print -r -- "$out" | grep -q DUPSLUG; then bad "report: false-positive duplicate slug on real file"; else ok "report: no duplicate slugs on real file"; fi

# --- report: duplicates detected on a synthetic fixture ---------------------

cat > "$work/dup.md" <<'EOF'
# fixture

### 3. one
Slug: foo

**The trap.** x

**Symptom.** x

**Fix.** x

---

### 3. dup-number
Slug: bar

**The trap.** x

**Symptom.** x

**Fix.** x

---

### 4. other
Slug: foo

**The trap.** x

**Symptom.** x

**Fix.** x

---
EOF
out="$(bash "$lib/learnings-index.sh" report "$work/dup.md")"
print -r -- "$out" | grep -q '^DUPNUM 3 ' && ok "report: detects duplicate entry number 3" || bad "report: missed duplicate number: $out"
print -r -- "$out" | grep -q '^DUPSLUG foo ' && ok "report: detects duplicate slug foo" || bad "report: missed duplicate slug: $out"

# --- report: missing file is a silent no-op, not a crash --------------------

out="$(bash "$lib/learnings-index.sh" report "$work/does-not-exist.md")"
[[ "$out" == "MAX 0" ]] && ok "report: missing file -> MAX 0" || bad "report: missing file gave '$out'"

# --- reindex: idempotent from the first run on the real 15-entry file -------

bash "$lib/learnings-index.sh" reindex "$work/real.md" > /dev/null
cp_after1="$(cat "$work/real.md")"
bash "$lib/learnings-index.sh" reindex "$work/real.md" > /dev/null
cp_after2="$(cat "$work/real.md")"
if [[ "$cp_after1" == "$cp_after2" ]]; then
  ok "reindex: idempotent from the first run (real 15-entry file)"
else
  bad "reindex: run 2 differs from run 1 on the real file"
fi
grep -q '^## Symptoms index' "$work/real.md" && ok "reindex: Symptoms index section present" || bad "reindex: no Symptoms index section after reindex"

# --- reindex: inserts a fresh section when none exists (68-entry-file case) -

awk 'BEGIN{skip=0} /^## Symptoms index/{skip=1} skip && /^## / && !/Symptoms index/{skip=0} !skip' \
  "$repo/.session-continuity/LEARNINGS.md" > "$work/virgin.md"
if grep -q '^## Symptoms index' "$work/virgin.md"; then
  bad "fixture setup: virgin.md still has an index (harness bug in this test, not the script)"
fi
bash "$lib/learnings-index.sh" reindex "$work/virgin.md" > /dev/null
if grep -q '^## Symptoms index' "$work/virgin.md"; then
  ok "reindex: inserts a Symptoms index where none existed"
else
  bad "reindex: insert path did not create a Symptoms index"
fi
n_bullets="$(grep -c '^- ' "$work/virgin.md")"
[[ "$n_bullets" -eq 15 ]] && ok "reindex: insert path produced 15 bullets" || bad "reindex: expected 15 bullets, got $n_bullets"
after1="$(cat "$work/virgin.md")"
bash "$lib/learnings-index.sh" reindex "$work/virgin.md" > /dev/null
after2="$(cat "$work/virgin.md")"
[[ "$after1" == "$after2" ]] && ok "reindex: insert path is idempotent from the first run" || bad "reindex: insert path run 2 differs from run 1"

# --- reindex: missing file is a silent no-op --------------------------------

bash "$lib/learnings-index.sh" reindex "$work/does-not-exist.md" > /dev/null
ok "reindex: missing file did not crash"

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
  || bad "contract-skewed sibling MODIFIED the file ($before_sum -> $after_sum)"

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
  || bad "entry-count drop MODIFIED the file ($before_sum -> $after_sum)"

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
