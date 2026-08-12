#!/usr/bin/env zsh
# Hook JSON output-contract runner. Hermetic: synthetic payloads in, stdout out.
#
# Invariant: every JSON object a hook writes to stdout PARSES. Asserted with a
# real parser, never with a substring match — a substring assert on 'deny'
# passes against malformed JSON, which is precisely how the proven-gate and
# smoke-gate defects shipped green (see 2026-08-12-hook-json-escaping-fix.md).
#
# The per-gate runners still own behaviour (which input denies, which allows).
# This runner owns encoding only, for every gate at once.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
hooks="$repo/hooks"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# parses <desc> <hook-basename> <payload>
# Requires BOTH that the hook emitted something and that it parses. A gate that
# stays silent here means the fixture stopped triggering it — also a failure,
# because then this runner is asserting nothing.
parses() {
  local desc="$1" hook="$2" payload="$3" out
  out="$(printf '%s' "$payload" | bash "$hooks/$hook" 2>/dev/null)"
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

spec_payload()  { printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }
plan_payload()  { printf '{"file_path":"/x/plans/p.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }
learn_payload() { printf '{"file_path":"/x/.session-continuity/LEARNINGS.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }

# One deny fixture per gate. Keep in sync with the completeness check below.
parses "proven-gate: claim, no fields" \
  proven-gate.sh "$(spec_payload 'Approach is proven, option A.')"
parses "smoke-gate: weak word beside smoke" \
  smoke-gate.sh "$(plan_payload 'The smoke test is optional for this change.')"
parses "smoke-gate: engine keyword, no smoke task" \
  smoke-gate.sh "$(plan_payload 'This plan rebuilds the binary and restarts the daemon.')"
parses "evidence-gate: first branch" \
  evidence-gate.sh "$(spec_payload 'Smoke section 01: runs the container then does cleanup at the end.')"
parses "evidence-gate: second branch" \
  evidence-gate.sh "$(spec_payload 'Smoke section 02: wait_for the service to come up, timeout 60s.')"
parses "flaky-gate: transient, no cause named" \
  flaky-gate.sh "$(learn_payload 'The build failed again, looks transient.')"
parses "backend-parity-gate: one named only" \
  backend-parity-gate.sh "$(plan_payload 'This plan needs full backend parity coverage in smoke.')"
parses "occurrence-gate: repeat, no invariant" \
  occurrence-gate.sh "$(learn_payload 'Occurrence count: 3 of 5\nYet another trigger patch.')"

# Adversarial reasons: a captured line carrying the characters that break a
# hand-built JSON string. smoke-gate echoes the matched line into its reason,
# so these exercise the interpolation path end to end.
#
# Both fixture strings are pre-encoded as if they were already valid JSON
# content (this repo's hooks read tool_input off the raw JSON text, so a
# real payload always arrives properly escaped). `\\\"` (JSON-decodes to one
# literal backslash + one literal quote) puts an actual `"` next to "old" in
# the decoded content, so the captured offender line itself carries a quote.
# `\\\\` (JSON-decodes to two literal backslashes) puts two literal `\`
# bytes in the decoded path text — more than the single backslash a real
# Windows-style path would carry, but it still exercises backslash-doubling
# in json_escape() the same way one would.
parses "smoke-gate: offender line with quotes" \
  smoke-gate.sh "$(plan_payload 'The smoke test is optional per the \\\"old\\\" policy.')"
parses "smoke-gate: offender line with backslashes" \
  smoke-gate.sh "$(plan_payload 'The smoke test is optional, see C:\\\\tmp\\\\notes.')"

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
