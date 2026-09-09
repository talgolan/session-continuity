# CONTRACT_VERSION=1
# hooks/lib/test-count-rerun.jq — pure vote/drift/spread decision for
# /session-continuity:primer Step 4's test-count rerun. Invoked via
# test-count-rerun.sh; see that file for the CLI contract and
# meta/superpowers/specs/2026-09-09-test-count-rerun-design.md for the
# full output contract this implements.
#
# Mode-agnostic by design: $mode is pass-through only (it never gates a
# branch here). skip/no-command/no-count's "always empty" outputs fall
# out of running this same algorithm against a 0- or 1-element $observed
# array — see the design spec's "MODE=run" outcomes table for why a
# majority can never be pinned from fewer than 2 parseable votes.

($observed | length) as $n
| ($observed | map(select(. != null))) as $parseable
| (if $n == 0 then 0 else $n - 1 end) as $retries
| (any($observed[]; . == null)) as $unparseable
| ($parseable | group_by(.) | map({value: .[0], count: length})
   | map(select(.count >= 2))) as $majority
| ($majority[0].value // null) as $pinned
| (if $pinned != null then false
   else ($parseable | unique | length) >= 2
   end) as $spread
| ($pinned != null and $recorded != null and $pinned != $recorded) as $drift

| "TEST_CMD=" + ($test_cmd // ""),
  "RECORDED_COUNT=" + (if $recorded == null then "" else ($recorded|tostring) end),
  "MODE=" + $mode,
  "RETRIES=" + ($retries|tostring),
  "OBSERVED=" + ($observed | map(if . == null then "" else (.|tostring) end) | join(",")),
  "UNPARSEABLE=" + (if $unparseable then "1" else "0" end),
  "DRIFT=" + (if $drift then "1" else "0" end),
  "PINNED_COUNT=" + (if $pinned == null then "" else ($pinned|tostring) end),
  "SPREAD=" + (if $spread then "1" else "0" end)
