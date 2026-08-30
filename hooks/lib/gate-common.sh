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
