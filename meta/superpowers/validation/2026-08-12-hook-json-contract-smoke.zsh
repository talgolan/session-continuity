#!/usr/bin/env zsh
# Hook JSON output-contract runner. Hermetic: staged-content + git-commit
# payloads in, stdout out.
#
# Invariant: every JSON object a hook writes to stdout PARSES. Asserted with a
# real parser, never with a substring match — a substring assert on 'deny'
# passes against malformed JSON, which is precisely how the proven-gate and
# smoke-gate defects shipped green (see 2026-08-12-hook-json-escaping-fix.md).
#
# The per-gate runners still own behaviour (which input denies, which allows).
# This runner owns encoding only, for every gate at once. Tasks 2-7 moved
# every content gate off Write|Edit onto Bash(git commit *), so each fixture
# below builds a hermetic repo, stages the violating content at the gate's
# actual in-scope path, and drives the gate through the same commit-payload
# shape hooks.json wires up for real.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
hooks="$repo/hooks"
source "$here/lib/gate-test-common.zsh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# commit_parses <desc> <hook-basename> <relpath> <content>
# Stages <content> at <relpath> in a fresh hermetic repo, drives <hook>
# through a real `git commit` payload, and requires BOTH that the hook
# emitted something and that it parses. A gate that stays silent here means
# the fixture stopped triggering it — also a failure, because then this
# runner is asserting nothing.
commit_parses() {
  local desc="$1" hook="$2" relpath="$3" content="$4" repo_dir out
  repo_dir="$(gt_make_repo)"
  gt_stage "$repo_dir" "$relpath" "$content"
  out="$(gt_run "$hook" "$(gt_commit_payload "$repo_dir")" 2>/dev/null)"
  gt_cleanup "$repo_dir"
  if [[ -z "$out" ]]; then
    bad "$desc (expected a JSON object, got silence — fixture no longer triggers)"
    return 0
  fi
  if printf '%s' "$out" | python3 -c 'import sys, json; json.load(sys.stdin)' 2>/dev/null; then
    ok "$desc"
  else
    bad "$desc — stdout is not valid JSON: $out"
  fi
}

# One deny fixture per gate, staged at each gate's real in-scope path. Keep
# in sync with the completeness check below.
commit_parses "proven-gate: claim, no fields" \
  proven-gate.sh "meta/specs/s.md" 'Approach is proven, option A.'
commit_parses "smoke-gate: weak word beside smoke" \
  smoke-gate.sh "meta/plans/p.md" 'The smoke test is optional for this change.'
commit_parses "smoke-gate: engine keyword, no smoke task" \
  smoke-gate.sh "meta/plans/p.md" 'This plan rebuilds the binary and restarts the daemon.'
commit_parses "evidence-gate: first branch" \
  evidence-gate.sh "meta/specs/s.md" 'Smoke section 01: runs the container then does cleanup at the end.'
commit_parses "evidence-gate: second branch" \
  evidence-gate.sh "meta/specs/s.md" 'Smoke section 02: wait_for the service to come up, timeout 60s.'
commit_parses "flaky-gate: transient, no cause named" \
  flaky-gate.sh ".session-continuity/LEARNINGS.md" 'The build failed again, looks transient.'
commit_parses "backend-parity-gate: one named only" \
  backend-parity-gate.sh "meta/plans/p.md" 'This plan needs full backend parity coverage in smoke.'
commit_parses "occurrence-gate: repeat, no invariant" \
  occurrence-gate.sh ".session-continuity/LEARNINGS.md" $'Occurrence count: 3 of 5\nYet another trigger patch.'

# Adversarial reasons: staged content carrying the characters that break a
# hand-built JSON string. smoke-gate echoes the matched line into its
# reason, so these exercise the interpolation path (json_escape()) end to
# end — real quote/backslash bytes in a real staged file, exactly as a real
# commit would carry them.
commit_parses "smoke-gate: offender line with quotes" \
  smoke-gate.sh "meta/plans/p.md" 'The smoke test is optional per the "old" policy.'
commit_parses "smoke-gate: offender line with backslashes" \
  smoke-gate.sh "meta/plans/p.md" 'The smoke test is optional, see C:\tmp\notes.'

# Completeness: every gate must own at least one fixture above. A newly added
# gate fails this runner until someone adds one — that is the point.
covered=(proven-gate.sh smoke-gate.sh evidence-gate.sh flaky-gate.sh backend-parity-gate.sh occurrence-gate.sh)
for f in "$hooks"/*-gate.sh; do
  b="${f:t}"
  if (( ${covered[(Ie)$b]} )); then
    ok "coverage: $b has a fixture"
  else
    bad "coverage: $b has NO fixture in this runner — add one"
  fi
done

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
