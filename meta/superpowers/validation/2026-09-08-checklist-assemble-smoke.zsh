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
