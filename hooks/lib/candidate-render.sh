#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/candidate-render.sh — renders candidate-extract.sh's JSON into the
# user-facing Step 2 block.
# See meta/superpowers/specs/2026-09-02-end-session-step2-rendering-design.md.
#
# Usage: candidate-extract.sh <transcript> | candidate-render.sh
# Reads one JSON object on stdin — the extractor's contract:
#   {"mode":"transcript"|"unavailable"|"error","candidates":[...],
#    "overflow":N,"detail":"..."}
# — and prints the finished user-facing block on stdout. Always exits 0: a
# rendering failure must fall back to context-window mode, never abort the
# ritual.
#
#   mode:"transcript", candidates present -> numbered list, indented evidence
#     bullets, the "+N more…" line when overflow>0, the capture prompt.
#   mode:"transcript", no candidates, no overflow -> the single no-op line.
#   mode:"error" -> "⚠️ LEARNINGS candidates unavailable: <detail>", verbatim.
#   mode:"unavailable", or unparseable/unrecognized stdin -> one line:
#     "SC-FALLBACK: context-window — <detail>"
#
# The caller's only branch: if the output starts with "SC-FALLBACK:", switch
# to context-window mode; otherwise print the output verbatim.

set -uo pipefail

INPUT="$(cat)"

fallback() {  # <detail>
  printf 'SC-FALLBACK: context-window — %s\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 || fallback "jq is not installed."

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  fallback "malformed candidate JSON."
fi

MODE="$(printf '%s' "$INPUT" | jq -r 'if (type=="object" and (.mode|type)=="string") then .mode else "" end')"

case "$MODE" in
  error)
    DETAIL="$(printf '%s' "$INPUT" | jq -r '.detail // "unknown error"')"
    printf '⚠️ LEARNINGS candidates unavailable: %s\n' "$DETAIL"
    exit 0
    ;;
  unavailable)
    DETAIL="$(printf '%s' "$INPUT" | jq -r '.detail // "the transcript is unavailable."')"
    fallback "$DETAIL"
    ;;
  transcript)
    ;;
  *)
    fallback "unrecognized mode '${MODE:-<none>}'."
    ;;
esac

printf '%s' "$INPUT" | jq -r '
  def render_candidate($i; $c):
    (($i+1)|tostring) + ". [" + $c.heuristic + "] " + $c.title + "\n"
    + "   Evidence:\n"
    + ([$c.evidence[] | "   - " + .] | join("\n"));

  (.candidates // []) as $cands
  | ((.overflow // 0)) as $overflow
  | if ($cands | length) == 0 and $overflow == 0 then
      "No LEARNINGS candidates surfaced from this session — Step 2 is a no-op."
    else
      "LEARNINGS candidates from this session:\n\n"
      + ([range(0; $cands|length) as $i | render_candidate($i; $cands[$i])] | join("\n\n"))
      + "\n"
      + (if $overflow > 0 then
           "\n+" + ($overflow|tostring) + " more candidates not shown — capture these first, then re-run /session-continuity:end-session.\n"
         else "" end)
      + "\nCapture any? (1, 2, 3, all, none, or describe another)"
    end
'
