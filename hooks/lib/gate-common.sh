#!/usr/bin/env bash
# hooks/lib/gate-common.sh — shared helpers for the commit-time content gates.
# SOURCED, never executed. Callers run `set -euo pipefail`; every function here
# is written to be safe under it (if-form, never `cmd && var=1`).

# --- payload parsing -------------------------------------------------------
gate_field() {  # <json-key> -> scalar string value from $GATE_PAYLOAD
  printf '%s' "${GATE_PAYLOAD:-}" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' \
    || true
}

gate_command() {  # decoded git command string from $GATE_PAYLOAD
  printf '%s' "${GATE_PAYLOAD:-}" \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | head -1 \
    | sed -E 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g; s/\\\\/\\/g' \
    || true
}

gate_load() {  # read stdin once; populate globals
  GATE_PAYLOAD="$(cat || true)"
  GATE_TOOL="$(gate_field tool_name)"
  GATE_CWD="$(gate_field cwd)"
  GATE_COMMAND="$(gate_command)"
}

gate_is_commit() {  # true iff a Bash `git commit` invocation
  [ "${GATE_TOOL:-}" = "Bash" ] || return 1
  printf '%s' "${GATE_COMMAND:-}" | grep -Eq 'git[[:space:]]+commit'
}

# --- staged content --------------------------------------------------------
gate_staged_files() {  # relative paths staged in the index
  [ -n "${GATE_CWD:-}" ] || return 0
  [ -d "$GATE_CWD" ] || return 0
  git -C "$GATE_CWD" diff --cached --name-only 2>/dev/null || true
}

gate_staged_blob() {  # <relpath> -> staged (index) content of the file
  git -C "${GATE_CWD:-}" show ":$1" 2>/dev/null || true
}

gate_staged_status() {  # <relpath> -> A|M|D|R100|... or empty
  local path="$1" line
  [ -n "${GATE_CWD:-}" ] || { printf ''; return 0; }
  # Rename-aware on purpose — do NOT pass --no-renames here.
  # Do not path-filter the diff: `diff -- <path>` collapses R* into A/D for
  # the single remaining side (verified: pure git mv → A when filtered).
  line="$(git -C "$GATE_CWD" diff --cached --name-status -M --no-color 2>/dev/null \
    | awk -v p="$path" -F '\t' '
        $1 ~ /^R/ && ($2 == p || $3 == p) { print; exit }
        $1 !~ /^R/ && $2 == p { print; exit }
      ' || true)"
  # R100\told\tnew  or  A\tpath  or  M\tpath
  printf '%s' "${line%%$'\t'*}"
}

gate_staged_entries() {  # -> status<TAB>dest<TAB>source-or-empty
  [ -n "${GATE_CWD:-}" ] || return 0
  [ -d "$GATE_CWD" ] || return 0
  # Collect rename-aware status once for the whole scan. Pairing status with
  # destination and source here makes the driver's status lookup O(1).
  git -C "$GATE_CWD" diff --cached --name-status -M --no-color 2>/dev/null \
    | awk -F '\t' '
        $1 ~ /^R/ { print $1 "\t" $3 "\t" $2; next }
        { print $1 "\t" $2 "\t" }
      ' || true
}

gate_staged_delta() {  # <relpath> -> sets GATE_DELTA_ADDED, GATE_DELTA_REMOVED
  local path="$1" raw
  GATE_DELTA_ADDED=""
  GATE_DELTA_REMOVED=""
  [ -n "${GATE_CWD:-}" ] || return 0
  [ -d "$GATE_CWD" ] || return 0
  raw="$(git -C "$GATE_CWD" -c diff.algorithm=myers diff --cached --no-color \
    --no-ext-diff --no-textconv --no-renames -U0 -- "$path" 2>/dev/null || true)"
  # Trailing x sentinel: command substitution strips a final newline, which
  # would drop the last empty segment when callers split on \n.
  GATE_DELTA_ADDED="$( { printf '%s\n' "$raw" | grep -E '^\+' | grep -Ev '^\+\+\+' | sed 's/^+//' || true; printf x; } )"
  GATE_DELTA_ADDED="${GATE_DELTA_ADDED%x}"
  GATE_DELTA_REMOVED="$( { printf '%s\n' "$raw" | grep -E '^-' | grep -Ev '^---' | sed 's/^-//' || true; printf x; } )"
  GATE_DELTA_REMOVED="${GATE_DELTA_REMOVED%x}"
}

gate_triggered() {  # [-w] TRIGGER_ERE [SAT_ERE…] -> 0 fire, 1 quiet
  local word=0 trigger
  if [ "${1:-}" = "-w" ]; then word=1; shift; fi
  trigger="${1:-}"; shift || true
  if [ -z "$trigger" ]; then return 1; fi
  if [ "$word" -eq 1 ]; then
    if printf '%s' "${GATE_DELTA_ADDED:-}" | LC_ALL=C grep -Eiqw -- "$trigger"; then return 0; fi
  else
    if printf '%s' "${GATE_DELTA_ADDED:-}" | LC_ALL=C grep -Eiq -- "$trigger"; then return 0; fi
  fi
  local sat
  for sat in "$@"; do
    if [ -n "$sat" ] && printf '%s' "${GATE_DELTA_REMOVED:-}" | LC_ALL=C grep -Eiq -- "$sat"; then
      return 0
    fi
  done
  return 1
}

gate_is_scratch() {  # <relpath> -> true if basename is dot-prefixed
  case "${1##*/}" in
    .*) return 0 ;;
    *)  return 1 ;;
  esac
}

# --- escape hatch (decoration-tolerant) ------------------------------------
gate_has_escape() {  # <text> <Label> -> true if an escape line is present
  # Strip markdown emphasis/code marks so `**Label:**` and `` `Label:` ``
  # still match. Leading blockquote `>`/heading `#` are harmless: the match
  # is not anchored to line start.
  printf '%s' "$1" \
    | sed -E 's/[`*]//g' \
    | grep -Eiq "$2:[[:space:]]*N/A[[:space:]]*(—|--)[[:space:]]*[^[:space:]]"
}

gate_hatch_class() {  # <text> <Label> -> accepted|near-miss|absent
  local text="$1" label="$2"
  if gate_has_escape "$text" "$label"; then
    printf 'accepted'
    return 0
  fi
  if printf '%s' "$text" | sed -E 's/[`*]//g' | grep -Eiq "$label:[[:space:]]*N/A"; then
    printf 'near-miss'
    return 0
  fi
  printf 'absent'
}

gate_near_miss_line() {  # <text> <Label> -> "N:<line>" or empty
  printf '%s' "$1" | sed -E 's/[`*]//g' | grep -Ein "$2:[[:space:]]*N/A" | head -1 || true
}

gate_mask_escape() {  # <text> <Label> -> text with this gate's escape lines blanked
  # Every gate's escape label matches its own claim regex ("Proven-gate"
  # contains "proven", "Flaky-gate" contains "flaky", and so on). Since
  # gate_has_escape short-circuits, that is invisible while escape matching
  # works — but the moment it does not, the line added to EXEMPT the doc
  # becomes the sole "claim" that condemns it, and a doc with no real claim
  # has no other trigger word. Masking the hatch before the claim scan makes
  # each gate fail OPEN on its own hatch instead of fail closed.
  #
  # Deliberately wider than gate_has_escape: no dash/reason required, so a
  # MALFORMED hatch attempt is masked too. That is the observed failure — a
  # hatch gate_has_escape rejects is exactly the one that self-condemns.
  #
  # Blanks rather than deletes, so line count is preserved and the line
  # numbers gate_first_match reports still match the real file. awk, not
  # `sed -I`, because case-insensitive deletion is a GNU extension and this
  # ships to arbitrary machines (verified on macOS awk 20200816).
  printf '%s' "$1" | awk -v lbl="$2" '
    BEGIN { re = tolower(lbl) ":[ \t]*n/a" }
    { probe = tolower($0); gsub(/[`*]/, "", probe)
      if (probe ~ re) { print ""; next }
      print }
  '
}

gate_first_match() {  # <text> <ere> -> "N:<line>" of the first word-boundary match
  printf '%s' "$1" | grep -Einw "$2" | head -1 || true
}

# --- output contract -------------------------------------------------------
json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' '
}

deny() {
  local reason="$1" norm wt_class st_class
  if [ -n "${GATE_NEAR_MISS:-}" ]; then
    reason="$reason Near-miss escape at line ${GATE_NEAR_MISS%%:*}: use \`${GATE_LABEL}: N/A — <reason>\` (em dash or --)."
  fi
  norm="$(printf '%s' "${GATE_COMMAND:-}" | tr '\n' ' ')"
  if printf '%s' "$norm" | grep -Eq 'git[[:space:]]+add\b.*(&&|;|\|\|).*git[[:space:]]+commit\b'; then
    reason="$reason This command chained git add with git commit; the add did not run. Stage and commit as two separate tool calls."
  fi
  if [ -n "${GATE_CWD:-}" ] && [ -n "${GATE_SCAN_PATH:-}" ] && [ -f "$GATE_CWD/$GATE_SCAN_PATH" ]; then
    wt_class="$(gate_hatch_class "$(cat "$GATE_CWD/$GATE_SCAN_PATH" 2>/dev/null || true)" "${GATE_LABEL:-}")"
    st_class="$(gate_hatch_class "$(gate_staged_blob "$GATE_SCAN_PATH")" "${GATE_LABEL:-}")"
    if [ "$wt_class" = "accepted" ] && [ "$st_class" != "accepted" ]; then
      reason="$reason Working-tree copy has an accepted hatch that is not staged; gates read the index (git show :path)."
    fi
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$reason")"
  exit 0
}

# --- driver ----------------------------------------------------------------
gate_scan_commit_message() {  # <check_fn>
  local check="$1" class
  class="$(gate_hatch_class "${GATE_COMMAND:-}" "$GATE_LABEL")"
  GATE_NEAR_MISS=""
  GATE_SCAN_PATH=""
  if [ "$class" = "accepted" ]; then
    GATE_NEAR_MISS=""
    return 0
  fi
  if [ "$class" = "near-miss" ]; then
    GATE_NEAR_MISS="$(gate_near_miss_line "${GATE_COMMAND:-}" "$GATE_LABEL")"
  fi
  "$check" "$(gate_mask_escape "${GATE_COMMAND:-}" "$GATE_LABEL")"
  GATE_NEAR_MISS=""
}

# Caller defines two functions and passes their names:
#   <in_scope_fn> <relpath>            -> return 0 if this gate should scan it
#   <check_fn>    <content> <relpath>  -> inspect; call deny (exits) on violation
gate_scan_staged() {
  local in_scope="$1" check="$2" f source raw class status empty_m_fallback
  if [ -z "${GATE_LABEL:-}" ]; then
    deny "internal: GATE_LABEL unset before gate_scan_staged"
  fi
  while IFS=$'\t' read -r status f source; do
    if [ -z "$f" ]; then continue; fi
    if ! "$in_scope" "$f"; then continue; fi
    if gate_is_scratch "$f"; then continue; fi
    raw="$(gate_staged_blob "$f")"
    GATE_SCAN_PATH="$f"
    class="$(gate_hatch_class "$raw" "$GATE_LABEL")"
    GATE_NEAR_MISS=""
    if [ "$class" = "accepted" ]; then continue; fi
    if [ "$class" = "near-miss" ]; then
      GATE_NEAR_MISS="$(gate_near_miss_line "$raw" "$GATE_LABEL")"
    fi
    case "$status" in
      R100)
        if [ -n "$source" ] && "$in_scope" "$source"; then continue; fi
        ;;
    esac
    gate_staged_delta "$f"
    empty_m_fallback=0
    if [ "$status" = "M" ] && [ -z "${GATE_DELTA_ADDED}" ] && [ -z "${GATE_DELTA_REMOVED}" ]; then
      GATE_DELTA_ADDED="$raw"
      empty_m_fallback=1
    fi
    # Skip empty blobs except empty-M whole-document fallback (mode-only / empty file).
    if [ -z "$raw" ] && [ "$empty_m_fallback" -eq 0 ]; then continue; fi
    GATE_DELTA_ADDED="$(gate_mask_escape "${GATE_DELTA_ADDED}" "$GATE_LABEL")"
    GATE_DELTA_REMOVED="$(gate_mask_escape "${GATE_DELTA_REMOVED}" "$GATE_LABEL")"
    raw="$(gate_mask_escape "$raw" "$GATE_LABEL")"
    "$check" "$raw" "$f" || true
  done <<EOF
$(gate_staged_entries)
EOF
}
