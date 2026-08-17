#!/usr/bin/env zsh
# perf-wrap.sh timing-wrapper smoke test. Hermetic: stub scripts in a temp
# dir, plus one real-gate regression check (the plugin's own claim-checking
# gate hook) to prove the wrapper never alters block/allow behavior — the
# one real regression risk in this whole feature.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
wrap="$repo/hooks/lib/perf-wrap.sh"
hooks="$repo/hooks"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"

# Stub scripts with known exit codes and known stdout/stderr.
for code in 0 1 2; do
  cat > "$work/stub-$code.sh" <<EOF
#!/usr/bin/env bash
echo "stub-$code-stdout"
echo "stub-$code-stderr" >&2
exit $code
EOF
  chmod +x "$work/stub-$code.sh"
done

for code in 0 1 2; do
  out="$(cd "$work" && bash "$wrap" "$work/stub-$code.sh" 2>/tmp/perf-wrap-smoke-stderr.$$)"
  rc=$?
  err="$(cat /tmp/perf-wrap-smoke-stderr.$$)"; rm -f /tmp/perf-wrap-smoke-stderr.$$
  if [[ "$rc" == "$code" && "$out" == "stub-$code-stdout" && "$err" == "stub-$code-stderr" ]]; then
    ok "stub exit $code: exit code + stdout + stderr pass through unchanged"
  else
    bad "stub exit $code: got rc=$rc out='$out' err='$err'"
  fi
done

log="$work/.session-continuity/performance.log"
lines="$(wc -l < "$log" 2>/dev/null || echo 0)"
lines="${lines##*[[:space:]]}"  # trim leading whitespace
if [[ "$lines" == "3" ]]; then
  ok "one log line per wrapped invocation (3 stubs => 3 lines)"
else
  bad "expected 3 log lines, got $lines"
fi
if tail -3 "$log" | python3 -c '
import sys, json
lines = [json.loads(l) for l in sys.stdin]
exits = sorted(l["exit"] for l in lines)
assert exits == [0,1,2], exits
' 2>/dev/null; then
  ok "logged exit codes match [0,1,2]"
else
  bad "logged exit codes do not match [0,1,2]: $(tail -3 "$log")"
fi

# Real-gate regression check: wrapping this plugin's claim-checking gate
# hook must not change its deny decision. Fixture matches the one already
# used in 2026-08-12-hook-json-contract-smoke.zsh.
# Proven-gate: N/A — this smoke test names proven-gate.sh as its fixture
# target, not a verification claim about this plan.
spec_payload() { printf '{"file_path":"/x/specs/s.md","tool_name":"Write","tool_input":{"content":"%s"}}' "$1"; }
payload="$(spec_payload 'Approach is proven, option A.')"
gate_hook="proven-gate.sh"
out="$(printf '%s' "$payload" | bash "$wrap" "$gate_hook" 2>/dev/null)"
rc=$?
if [[ "$rc" == "0" ]] && printf '%s' "$out" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["permissionDecision"]=="deny"' 2>/dev/null; then
  ok "wrapped $gate_hook still denies the claim (exit 0, JSON deny)"
else
  bad "wrapped $gate_hook regression: rc=$rc out=$out"
fi

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
