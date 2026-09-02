#!/usr/bin/env zsh
# hooks/prompt-intercept.sh smoke test.
#
# A false positive here erases real user work with no transcript entry — see
# the Global Constraints in meta/superpowers/plans/2026-09-02-zero-turn-
# read-only-commands.md. This runner therefore weighs the must-NOT-block set
# (Step 2) and the fail-open set (Step 3) as heavily as the must-block set
# (Step 1), never as an afterthought to it.
#
# Hermetic: every payload is built with `jq -n` (never hand-interpolated
# JSON), and the render.sh-stub / no-jq fixtures run against throwaway
# copies under one `mktemp -d`, removed at the end.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
hooks="$repo/hooks"
intercept="$hooks/prompt-intercept.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"

# --- helpers -----------------------------------------------------------

# build_payload <prompt> [cwd] -> a UserPromptSubmit-shaped JSON payload,
# built with jq so embedded quotes/newlines in <prompt> are handled by a
# real serializer, never hand-escaped.
build_payload() {
  local p="$1" c="${2:-$repo}"
  jq -n --arg prompt "$p" --arg cwd "$c" '{prompt: $prompt, cwd: $cwd}'
}

# run_intercept <payload-json> [script] [PATH] -> stdout (stderr discarded,
# matching the hook's own contract: it never surfaces render.sh's stderr).
run_intercept() {
  local payload="$1" script="${2:-$intercept}" pathv="${3:-$PATH}"
  print -rn -- "$payload" | env PATH="$pathv" bash "$script" 2>/dev/null
}

# assert_blocks <desc> <prompt> — requires exit 0, non-empty stdout, and
# that stdout is a REAL parsed JSON object with the exact shape the design
# spec measured: decision:"block", a non-empty string reason, and
# suppressOriginalPrompt nested under hookSpecificOutput (not top-level —
# the placement that was measured to NOT suppress the echoed prompt).
assert_blocks() {
  local desc="$1" prompt="$2" payload out rc
  payload="$(build_payload "$prompt")"
  out="$(run_intercept "$payload")"; rc=$?
  if [[ $rc -ne 0 ]]; then
    bad "$desc: expected exit 0, got $rc"
    return 0
  fi
  if [[ -z "$out" ]]; then
    bad "$desc: expected a block JSON on stdout, got silence"
    return 0
  fi
  if print -rn -- "$out" | jq -e '
        .decision == "block"
        and (.reason | type) == "string" and (.reason | length) > 0
        and .hookSpecificOutput.hookEventName == "UserPromptSubmit"
        and .hookSpecificOutput.suppressOriginalPrompt == true
        and (has("suppressOriginalPrompt") | not)
      ' >/dev/null 2>&1; then
    ok "$desc"
  else
    bad "$desc: stdout did not parse as the expected block shape: $out"
  fi
}

# assert_passthrough <desc> <prompt> — the must-NOT-block contract: exit 0
# AND empty stdout. Either half failing means the prompt was altered or the
# hook errored where it must have stayed silent.
assert_passthrough() {
  local desc="$1" prompt="$2" payload out rc
  payload="$(build_payload "$prompt")"
  out="$(run_intercept "$payload")"; rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then
    ok "$desc"
  else
    bad "$desc: expected exit 0 + empty stdout, got rc=$rc out='$out'"
  fi
}

# --- Step 1: the must-block set ---------------------------------------------
# Every approved table entry, exact per the review in task-3's brief.

table_entries=(
  "backlog" "the backlog" "backlog list" "show backlog" "show the backlog"
  "show me the backlog" "list the backlog" "what's in the backlog"
  "/session-continuity:backlog"
  "learnings" "the learnings" "learnings list" "show the learnings"
  "show me the learnings" "list the learnings" "what's in learnings"
  "/session-continuity:learnings"
  "/session-continuity:help"
  "/session-continuity:update"
)
for t in $table_entries; do
  assert_blocks "table entry blocks: '$t'" "$t"
done

# Casing/whitespace/punctuation/politeness variants — same normalization
# path, different literal bytes.
assert_blocks "casing variant: 'Show The Backlog'" "Show The Backlog"
assert_blocks "whitespace variant: '  backlog  '" "  backlog  "
assert_blocks "trailing-punctuation variant: 'backlog?'" "backlog?"
assert_blocks "please-prefix variant: 'please show me the backlog'" "please show me the backlog"
assert_blocks "casing variant: 'LEARNINGS'" "LEARNINGS"
assert_blocks "internal-whitespace-run variant: 'show   the   learnings'" "show   the   learnings"
assert_blocks "trailing-period variant: 'the learnings.'" "the learnings."

# --- Step 2: the must-NOT-block set — equal weight, more important ---------

assert_passthrough "compound: show the backlog and then fix item 3" \
  "show the backlog and then fix item 3"
assert_passthrough "compound: add this to the backlog" \
  "add this to the backlog"
assert_passthrough "compound: is item 3 in the backlog still open" \
  "is item 3 in the backlog still open"
assert_passthrough "incidental mention: what does the backlog file look like on disk" \
  "what does the backlog file look like on disk"
assert_passthrough "prose merely containing the word: backlog is getting long" \
  "I think our backlog is getting long, can you help me triage it?"
assert_passthrough "prose merely containing the word: learnings entry" \
  "can you add a learnings entry for the bug we just fixed?"
assert_passthrough "bare unscoped slash /backlog does not match (deliberate — see hooks/prompt-intercept.sh header)" \
  "/backlog"
assert_passthrough "bare unscoped slash /learnings does not match (deliberate)" \
  "/learnings"
assert_passthrough "bare unscoped slash /help does not match (deliberate)" \
  "/help"
assert_passthrough "embedded quotes and newlines" \
  $'He typed "show the backlog" in his message, then said:\nnever mind, do something else instead.'

# --- Step 3: the fail-open set ----------------------------------------------

# 3a. jq absent from PATH. Built from real coreutils symlinked into a fresh
# dir that never includes jq — NOT "every PATH dir that happens to also
# contain jq", because on this machine /usr/bin holds both a system jq AND
# coreutils the hook needs (dirname, sed, grep, awk) to reach its own
# `command -v jq` check in the first place; excluding whole directories
# would produce a false "fail open" for the wrong reason.
nojq_bin="$work/nojq-bin"
mkdir -p "$nojq_bin"
for b in bash cat sed grep awk dirname basename mktemp tr head wc env printf; do
  b_path="$(command -v "$b" 2>/dev/null)"
  [[ -n "$b_path" ]] && ln -sf "$b_path" "$nojq_bin/$b"
done
payload="$(build_payload backlog)"
out="$(run_intercept "$payload" "$intercept" "$nojq_bin")"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "fail-open: jq absent from PATH" \
  || bad "fail-open: jq absent from PATH — rc=$rc out='$out'"

# 3b. Payload is not JSON at all.
out="$(print -rn -- 'this is not json' | bash "$intercept" 2>/dev/null)"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "fail-open: payload is not valid JSON" \
  || bad "fail-open: payload is not valid JSON — rc=$rc out='$out'"

# 3c. Payload has no `prompt` field.
payload="$(jq -n --arg cwd "$repo" '{cwd: $cwd}')"
out="$(run_intercept "$payload")"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "fail-open: payload has no prompt field" \
  || bad "fail-open: payload has no prompt field — rc=$rc out='$out'"

# 3c'. `prompt` field present but not a string.
payload="$(jq -n --arg cwd "$repo" '{prompt: 12345, cwd: $cwd}')"
out="$(run_intercept "$payload")"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "fail-open: prompt field is not a string" \
  || bad "fail-open: prompt field is not a string — rc=$rc out='$out'"

# 3d. render.sh replaced by a stub that exits 2 (broken install). Mirrors
# the real hooks/ layout (prompt-intercept.sh + lib/render.sh) under a
# throwaway dir, since prompt-intercept.sh resolves render.sh relative to
# its own path.
stub_dir="$work/stub-nonzero"
mkdir -p "$stub_dir/lib"
cp "$intercept" "$stub_dir/prompt-intercept.sh"
cat > "$stub_dir/lib/render.sh" <<'EOF'
#!/usr/bin/env bash
echo "render.sh: simulated broken install" >&2
exit 2
EOF
chmod +x "$stub_dir/prompt-intercept.sh" "$stub_dir/lib/render.sh"
payload="$(build_payload backlog)"
out="$(run_intercept "$payload" "$stub_dir/prompt-intercept.sh")"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "fail-open: render.sh exits non-zero (broken install)" \
  || bad "fail-open: render.sh exits non-zero — rc=$rc out='$out'"

# 3e. render.sh exits 0 but prints nothing (also named explicitly in the
# handler's contract: non-zero OR empty output both fail open).
stub_dir2="$work/stub-empty"
mkdir -p "$stub_dir2/lib"
cp "$intercept" "$stub_dir2/prompt-intercept.sh"
cat > "$stub_dir2/lib/render.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$stub_dir2/prompt-intercept.sh" "$stub_dir2/lib/render.sh"
payload="$(build_payload learnings)"
out="$(run_intercept "$payload" "$stub_dir2/prompt-intercept.sh")"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && ok "fail-open: render.sh exits 0 with empty output" \
  || bad "fail-open: render.sh exits 0 with empty output — rc=$rc out='$out'"

# --- bonus: perf-wrap.sh passthrough ----------------------------------------
# perf-wrap.sh is how hooks.json actually registers this hook — confirm the
# block JSON survives the wrapper untouched (perf-wrap.sh never reads or
# rewrites stdin/stdout, per its own header). perf-wrap.sh shells out to
# perf-log.sh, which writes `.session-continuity/performance.log` relative
# to `git rev-parse --show-toplevel` of the CALLER's cwd — running it from
# this script's own cwd would silently pollute the real repo (see
# LEARNINGS.md #12, "a smoke test's own hermeticity bug recurred twice").
# `$work` is a plain mktemp dir, not a git repo, so `git rev-parse` there
# fails and perf-log.sh no-ops instead of writing anywhere real.
payload="$(build_payload backlog)"
out="$(cd "$work" && print -rn -- "$payload" | bash "$hooks/lib/perf-wrap.sh" prompt-intercept.sh 2>/dev/null)"; rc=$?
if [[ $rc -eq 0 ]] && print -rn -- "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
  ok "perf-wrap.sh passthrough: block JSON survives the wrapper unchanged"
else
  bad "perf-wrap.sh passthrough: expected a block JSON via perf-wrap.sh, got rc=$rc out='$out'"
fi

# --- hooks.json registration -------------------------------------------------
# Structural check only (parses, has the right shape) — not a live Claude
# Code run.
if jq -e '.hooks.UserPromptSubmit[0].hooks[0].command | test("prompt-intercept\\.sh$")' \
    "$hooks/hooks.json" >/dev/null 2>&1; then
  ok "hooks.json: UserPromptSubmit registers prompt-intercept.sh via perf-wrap.sh"
else
  bad "hooks.json: no UserPromptSubmit entry wired to prompt-intercept.sh"
fi

rm -rf "$work"
print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
