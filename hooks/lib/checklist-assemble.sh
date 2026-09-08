#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/checklist-assemble.sh — Step 3 checklist renderer for
# /session-continuity:end-session (session-continuity plugin).
#
# Usage: checklist-assemble.sh [<backlog-tsv-path>]
# Reads one JSON object on stdin (see
# meta/superpowers/plans/2026-09-08-determinism-phase-4-checklist-assembly.md
# Task 1 for the full contract) and prints the finished eight-row checklist,
# suggested-commit block, and terminal sign-off line on stdout. Always exits
# 0: a rendering failure must degrade to SC-FALLBACK, never abort the ritual.
#
# <backlog-tsv-path> is read only when the input's backlog_mode=="normal".
# Each line is tag\tverdict\tcitation, one per open backlog item still
# subject to Step 1's overlap gate. A missing/unreadable path in that mode
# degrades to zero tracked items rather than falling back — an empty
# backlog is a valid state, distinct from malformed input.

set -uo pipefail

INPUT="$(cat)"
TSV_PATH="${1:-}"

fallback() {  # <detail>
  printf 'SC-FALLBACK: manual — %s\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 || fallback "jq is not installed."

if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  fallback "malformed checklist JSON."
fi

for key in staged unstaged untracked branch primer learnings backlog_mode; do
  if ! printf '%s' "$INPUT" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
    fallback "checklist JSON missing required key '$key'."
  fi
done

# --- backlog TSV -> a JSON array jq can fold in ------------------------------
BACKLOG_MODE="$(printf '%s' "$INPUT" | jq -r '.backlog_mode')"
case "$BACKLOG_MODE" in
  normal|none|unavailable|not-migrated|fast-path) ;;
  *) fallback "unrecognized backlog_mode '$BACKLOG_MODE'." ;;
esac

BACKLOG_ITEMS_JSON='[]'
if [[ "$BACKLOG_MODE" == "normal" && -n "$TSV_PATH" && -r "$TSV_PATH" ]]; then
  # jq's own JSON string encoding handles quotes, backslashes, and control
  # characters correctly — no hand-rolled escaping. Split each line on tab;
  # a citation containing a literal tab (columns 4+) is rejoined with "\t"
  # rather than truncated.
  BACKLOG_ITEMS_JSON="$(
    jq -R -s '
      split("\n") | map(select(length > 0)) | map(split("\t")) |
      map(select(length >= 3)) |
      map({tag: .[0], verdict: .[1], citation: (.[2:] | join("\t"))})
    ' "$TSV_PATH" 2>/dev/null
  )"
  if ! printf '%s' "$BACKLOG_ITEMS_JSON" | jq -e . >/dev/null 2>&1; then
    BACKLOG_ITEMS_JSON='[]'
  fi
fi

OUT="$(
  printf '%s' "$INPUT" | jq -r --argjson items "$BACKLOG_ITEMS_JSON" '
    # --- row 1: primer -------------------------------------------------------
    def primer_row:
      if .primer == "refreshed" then "✓ Primer refreshed and staged"
      elif .primer == "closed" then "✓ Primer updated (outstanding item(s) closed)"
      else "✓ Primer already current (no-op)" end;

    # --- row 2: learnings -----------------------------------------------------
    def learnings_row:
      (.learnings // []) as $l
      | if ($l | length) == 0 then "✓ No new learnings"
        else
          ($l | length) as $n
          | (if $n == 1 then "entry" else "entries" end) as $noun
          | ([$l[] | "#" + (.number|tostring) + ", \"" + .title + "\""] | join(", ")) as $cited
          | "✓ " + ($n|tostring) + " LEARNINGS " + $noun + " captured (" + $cited + ")"
        end;

    # --- row 3: backlog ---------------------------------------------------------
    def backlog_row:
      if .backlog_mode == "none" then {marker:"✓", text:"Backlog: none tracked"}
      elif .backlog_mode == "unavailable" then {marker:"✓", text:"Backlog: GitHub queue unavailable — run /session-continuity:doctor"}
      elif .backlog_mode == "not-migrated" then {marker:"✓", text:"Backlog: not migrated — run /session-continuity:primer"}
      elif .backlog_mode == "fast-path" then {marker:"✓", text:"Backlog: " + (.backlog_fastpath_count|tostring) + " tracked — not re-verified this session (no repo changes since last close-out)"}
      else
        ($items) as $it
        | ($it | length) as $n
        | ($it | map(select(.verdict=="appears-DONE"))) as $done
        | ($it | map(select(.verdict=="still-open"))) as $open
        | ($it | map(select(.verdict=="manual"))) as $man
        | ([
            (if ($done|length) > 0 then ($done|length|tostring) + " appears-DONE (" + ([$done[] | .tag + ", \"" + .citation + "\""] | join(", ")) + ")" else empty end),
            (if ($open|length) > 0 then ($open|length|tostring) + " still-open (" + ([$open[] | .tag] | join(", ")) + ")" else empty end),
            (if ($man|length) > 0 then ($man|length|tostring) + " manual (" + ([$man[] | .tag] | join(", ")) + ")" else empty end)
          ] | join(", ")) as $clauses
        | {marker: (if ($done|length) > 0 then "⚠️" else "✓" end),
           text: "Backlog: " + ($n|tostring) + " tracked" + (if $n > 0 then " — " + $clauses else "" end)}
      end;

    # --- rows 4-6: file lists ---------------------------------------------------
    def staged_row:
      (.staged // []) as $s
      | if ($s|length) == 0 then {marker:"✓", text:"Nothing staged"}
        else {marker:"✓", text:"Staged: " + ($s|join(", "))} end;

    def unstaged_row:
      (.unstaged // []) as $u
      | if ($u|length) == 0 then {marker:"✓", text:"No unstaged modifications"}
        else {marker:"⚠️", text:"Unstaged: " + ($u|join(", "))} end;

    def untracked_row:
      (.untracked // []) as $t
      | if ($t|length) == 0 then {marker:"✓", text:"No untracked files"}
        else {marker:"⚠️", text:($t|length|tostring) + " untracked: " + ($t|join(", ")) + " — ignore, add, or delete?"} end;

    # --- row 7: unpushed commits -------------------------------------------------
    def unpushed_row:
      if .detached == true then
        {marker:"⚠️", text:"detached HEAD at " + (.short_sha // "?")}
      elif .upstream == null then
        {marker:"⚠️", text:"branch `" + .branch + "` has no upstream — set one with `git push -u origin " + .branch + "`"}
      elif (.ahead // 0) == 0 then
        {marker:"✓", text:"Up to date with " + .upstream}
      else
        {marker:"⚠️", text:"Branch `" + .branch + "` is " + (.ahead|tostring) + " commits ahead of origin — push before closing?"}
      end;

    # --- row 8: suggested commit --------------------------------------------------
    def suggested_row:
      (.staged // []) as $s
      | if ($s|length) == 0 then null
        else
          (if ([$s[] | startswith(".session-continuity/")] | all) then "docs: update session continuity"
           elif .commit_subject != null then .commit_subject
           else "chore: update " + ($s|length|tostring) + " file(s)" end) as $subject
          | "→ Suggested:\n```\ngit commit -m \"" + $subject + "\"\n```"
        end;

    (primer_row) as $r1
    | (learnings_row) as $r2
    | (backlog_row) as $r3
    | (staged_row) as $r4
    | (unstaged_row) as $r5
    | (untracked_row) as $r6
    | (unpushed_row) as $r7
    | (suggested_row) as $r8
    | [$r1, $r2, ($r3.marker + " " + $r3.text), ($r4.marker + " " + $r4.text),
       ($r5.marker + " " + $r5.text), ($r6.marker + " " + $r6.text),
       ($r7.marker + " " + $r7.text)] as $rows
    | ($rows | map(test("⚠️")) | any) as $any_warn
    | ($rows + (if $r8 != null then [$r8] else [] end)) as $all_lines
    | ($all_lines | join("\n"))
      + "\n\n"
      + (if $any_warn then
           "✅ Session complete. Safe to close. (Warnings above are advisory — review before closing if relevant.)"
         else
           "✅ Session complete. Safe to close."
         end)
  ' 2>/dev/null
)"
JQ_STATUS=$?

if [[ "$JQ_STATUS" -ne 0 || -z "$OUT" ]]; then
  fallback "checklist JSON did not match the expected shape."
fi

printf '%s\n' "$OUT"
