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
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$1")"
  exit 0
}

# --- driver ----------------------------------------------------------------
# Caller defines two functions and passes their names:
#   <in_scope_fn> <relpath>            -> return 0 if this gate should scan it
#   <check_fn>    <content> <relpath>  -> inspect; call deny (exits) on violation
gate_scan_staged() {
  local in_scope="$1" check="$2" f content
  while IFS= read -r f; do
    if [ -z "$f" ]; then continue; fi
    "$in_scope" "$f" || continue
    if gate_is_scratch "$f"; then continue; fi
    content="$(gate_staged_blob "$f")"
    if [ -z "$content" ]; then continue; fi
    "$check" "$content" "$f" || true
  done <<EOF
$(gate_staged_files)
EOF
}
