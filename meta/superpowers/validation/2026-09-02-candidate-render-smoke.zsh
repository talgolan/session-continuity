#!/usr/bin/env zsh
# candidate-render.sh smoke test. Hermetic: fixture JSON on stdin only — no
# transcript, no git state.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

render() { print -rn -- "$1" | bash "$lib/candidate-render.sh"; }

# --- malformed JSON on stdin must not crash, must fall back -------------------
out="$(render 'not json at all')"
[[ "$out" == SC-FALLBACK:* ]] && ok "malformed JSON -> SC-FALLBACK" \
  || bad "expected SC-FALLBACK, got: $out"

# --- mode:unavailable -----------------------------------------------------------
out="$(render '{"mode":"unavailable","candidates":[],"overflow":0,"detail":"the transcript is stale."}')"
[[ "$out" == "SC-FALLBACK: context-window — the transcript is stale." ]] \
  && ok "mode:unavailable -> SC-FALLBACK carrying detail" \
  || bad "got: $out"

# --- mode:error -------------------------------------------------------------------
out="$(render '{"mode":"error","candidates":[],"overflow":0,"detail":"jq is not installed."}')"
[[ "$out" == "⚠️ LEARNINGS candidates unavailable: jq is not installed." ]] \
  && ok "mode:error -> warning line with detail verbatim" \
  || bad "got: $out"

# --- detail containing quotes and a newline ---------------------------------------
detail_json='{"mode":"error","candidates":[],"overflow":0,"detail":"failed on \"weird\" input\nsecond line"}'
out="$(render "$detail_json")"
expected='⚠️ LEARNINGS candidates unavailable: failed on "weird" input
second line'
[[ "$out" == "$expected" ]] && ok "detail with embedded quotes and a newline renders verbatim" \
  || bad "got: $out"

# --- zero candidates, mode:transcript ---------------------------------------------
out="$(render '{"mode":"transcript","candidates":[],"overflow":0,"detail":""}')"
[[ "$out" == "No LEARNINGS candidates surfaced from this session — Step 2 is a no-op." ]] \
  && ok "zero candidates -> the no-op line" \
  || bad "got: $out"

# --- one candidate, command-bearing evidence (heuristic A shape) -----------------
one='{"mode":"transcript","candidates":[{"heuristic":"retry-burst","title":"bun test — re-run 3 times with 1 file edits in between.","evidence":["Bash @ 2026-09-01T00:00:00Z → failed: FAIL","Bash @ 2026-09-01T00:01:00Z → ok"]}],"overflow":0,"detail":""}'
out="$(render "$one")"
expected="LEARNINGS candidates from this session:

1. [retry-burst] bun test — re-run 3 times with 1 file edits in between.
   Evidence:
   - Bash @ 2026-09-01T00:00:00Z → failed: FAIL
   - Bash @ 2026-09-01T00:01:00Z → ok

Capture any? (1, 2, 3, all, none, or describe another)"
[[ "$out" == "$expected" ]] && ok "single candidate renders the numbered list exactly" \
  || bad "got: $out"

# --- all four heuristic ids, mixed bare-timestamp vs command-bearing evidence -----
four='{"mode":"transcript","candidates":[
  {"heuristic":"retry-burst","title":"T-A","evidence":["Bash @ t1 → ok"]},
  {"heuristic":"revert","title":"T-B","evidence":["Bash @ t2 → git checkout -- x"]},
  {"heuristic":"error-recurrence","title":"T-C","evidence":["@ t3","@ t4"]},
  {"heuristic":"fix-burst","title":"T-D","evidence":["Bash @ t5 → git commit"]}
],"overflow":0,"detail":""}'
out="$(render "$four")"
expected="LEARNINGS candidates from this session:

1. [retry-burst] T-A
   Evidence:
   - Bash @ t1 → ok

2. [revert] T-B
   Evidence:
   - Bash @ t2 → git checkout -- x

3. [error-recurrence] T-C
   Evidence:
   - @ t3
   - @ t4

4. [fix-burst] T-D
   Evidence:
   - Bash @ t5 → git commit

Capture any? (1, 2, 3, all, none, or describe another)"
[[ "$out" == "$expected" ]] && ok "all four heuristic ids render, bare-ts and command-bearing evidence both printed plainly" \
  || bad "got: $out"

# --- overflow > 0 appends the +N more candidates line -----------------------------
ov='{"mode":"transcript","candidates":[{"heuristic":"retry-burst","title":"T","evidence":["e1"]}],"overflow":2,"detail":""}'
out="$(render "$ov")"
[[ "$out" == *"+2 more candidates not shown — capture these first, then re-run /session-continuity:end-session."* ]] \
  && ok "overflow>0 appends the +N more candidates line" \
  || bad "got: $out"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
