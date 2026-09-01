#!/usr/bin/env zsh
# agent-active.sh smoke test. Hermetic: synthetic JSONL fixtures only.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

jline() { print -r -- "$1"; }

# --- degradation ------------------------------------------------------------

out="$(bash "$lib/agent-active.sh" /no/such/file.jsonl 1000)"
[[ -z "$out" ]] && ok "missing transcript prints nothing" || bad "missing transcript printed: $out"

out="$(bash "$lib/agent-active.sh" "$repo/README.md" not-a-number)"
[[ -z "$out" ]] && ok "non-numeric start_epoch prints nothing" || bad "bad start_epoch printed: $out"

# --- primary mechanism: sum turn_duration.durationMs ------------------------

f1="$(mktemp)"
{
  jline '{"type":"system","subtype":"turn_duration","durationMs":5000,"timestamp":"2026-09-01T00:00:10.000Z"}'
  jline '{"type":"system","subtype":"away_summary","timestamp":"2026-09-01T00:10:00.000Z"}'
  jline '{"type":"system","subtype":"turn_duration","durationMs":3000,"timestamp":"2026-09-01T00:10:05.000Z"}'
} > "$f1"
start_epoch=1
out="$(bash "$lib/agent-active.sh" "$f1" "$start_epoch")"
# 5000ms + 3000ms = 8.000s active, regardless of the ~10-minute away_summary gap between them.
if [[ "$out" == "8.000" ]]; then
  ok "primary mechanism: sums turn_duration.durationMs, excludes the away gap"
else
  bad "primary mechanism: expected 8.000, got '$out'"
fi
rm -f "$f1"

# --- start_epoch filtering ---------------------------------------------------

f2="$(mktemp)"
{
  jline '{"type":"system","subtype":"turn_duration","durationMs":9999,"timestamp":"2020-01-01T00:00:00.000Z"}'
  jline '{"type":"system","subtype":"turn_duration","durationMs":1500,"timestamp":"2026-09-01T00:00:10.000Z"}'
} > "$f2"
start_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-09-01T00:00:00Z' +%s 2>/dev/null || date -u -d '2026-09-01T00:00:00Z' +%s)"
out="$(bash "$lib/agent-active.sh" "$f2" "$start_epoch")"
[[ "$out" == "1.500" ]] && ok "start_epoch filter excludes records before it" || bad "expected 1.500, got '$out'"
rm -f "$f2"

# --- fallback mechanism: no turn_duration records at all --------------------

f3="$(mktemp)"
{
  jline '{"type":"assistant","timestamp":"2026-09-01T00:00:00.000Z"}'
  jline '{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-09-01T00:00:05.000Z"}'
  jline '{"type":"user","timestamp":"2026-09-01T00:10:00.000Z"}'
  jline '{"type":"assistant","timestamp":"2026-09-01T00:10:02.000Z"}'
}  > "$f3"
start_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-09-01T00:00:00Z' +%s 2>/dev/null || date -u -d '2026-09-01T00:00:00Z' +%s)"
out="$(bash "$lib/agent-active.sh" "$f3" "$start_epoch")"
# Fallback sums gaps whose left edge is NOT a turn_duration record:
# assistant->stop_hook_summary (5s, counted) + stop_hook_summary->user (595s,
# NOT counted -- this transcript has no turn_duration record at all, so the
# *only* boundary marker the fallback recognizes is a turn_duration record;
# since none exists, every gap counts, including the 595s one. This fixture
# exists to prove the fallback activates (produces a non-empty number) when
# turn_duration is absent, not to pin an exact value -- see Step 5.
if [[ -n "$out" ]]; then
  ok "fallback mechanism activates when turn_duration is absent (got $out)"
else
  bad "fallback mechanism produced no output"
fi
rm -f "$f3"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
