#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/agent-active.sh — agent-active-time derivation (Change 2).
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
#
# Usage: agent-active.sh <transcript-path> <start-epoch>
# Prints a single number (seconds, 3 decimals) to stdout: time spent inside
# an assistant turn within [start-epoch, now]. Prints nothing and exits 0
# if the transcript is unreadable/empty or start-epoch isn't a plain
# integer — callers must check for empty output before logging
# step-4-agent-active.
#
# Primary mechanism: sums durationMs from every type=="system",
# subtype=="turn_duration" record in range -- the harness's own per-turn
# timer, already excluding idle time. Verified present in both a real
# architect-workbench transcript and this repo's own transcripts (see the
# spec's Change 2). Falls back to a timestamp turn-boundary walk (weaker:
# infers boundaries from record adjacency rather than reading an explicit
# field) only when zero turn_duration records exist in range at all.

set -u

TRANSCRIPT="${1:-}"
START_EPOCH="${2:-}"

[[ -r "$TRANSCRIPT" && -s "$TRANSCRIPT" ]] || exit 0
[[ "$START_EPOCH" =~ ^[0-9]+$ ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

RESULT="$(jq -s --argjson start "$START_EPOCH" '
  def to_epoch: gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  (map(select(.timestamp != null and (.timestamp | to_epoch) >= $start))) as $in_range
  | ($in_range | map(select(.type=="system" and .subtype=="turn_duration"))) as $turns
  | if ($turns | length) > 0 then
      ($turns | map(.durationMs) | add) / 1000
    else
      ($in_range | sort_by(.timestamp | to_epoch)) as $sorted
      | (reduce range(0; (($sorted|length) - 1)) as $i (0;
          . as $acc
          | $sorted[$i] as $a
          | $sorted[$i+1] as $b
          | if ($a.type=="system" and $a.subtype=="turn_duration") then $acc
            else $acc + (($b.timestamp | to_epoch) - ($a.timestamp | to_epoch))
            end
        ))
    end
' "$TRANSCRIPT" 2>/dev/null)"

[[ -n "$RESULT" ]] || exit 0
awk -v v="$RESULT" 'BEGIN{printf "%.3f", v}'
