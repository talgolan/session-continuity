#!/usr/bin/env bash
# derived-value-gate.sh — commit-time content gate (session-continuity plugin,
# Determinism Phase 7, closes #44).
#
# Fires before Bash(git commit *). For each staged commands/*.md file, BLOCKS
# prompt text instructing a model to (1) compute a duration by hand, (2)
# tally/vote on a count by eye, (3) eyeball-compare a claimed value against an
# actual one, or (4) print fixed reference text as if it were an instruction —
# the four defect classes Phases 0-6 of the determinism program removed. See
# meta/superpowers/specs/2026-09-02-determinism-program-design.md and
# meta/superpowers/plans/2026-09-09-determinism-phase-7-derived-value-gate.md
# for the grounding (which real diff each pattern below is anchored to).
#
# A fifth class named in #44 — "renumber" — is deliberately NOT checked here:
# no real removed instance exists to ground a pattern on (see the plan above),
# and a naive word-anchor false-positives on learning.md's own anti-renumber
# stability guarantees.
#
# Escape: `Derived-value-gate: N/A — <reason>`.
set -euo pipefail
# shellcheck disable=SC1091 # dynamically-resolved path; gate-common.sh is shellcheck-clean standalone
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/gate-common.sh"

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_in_scope() {
  case "$1" in commands/*.md) return 0 ;; *) return 1 ;; esac
}

# Each check takes (masked-content, path) and calls deny (exits) on a hit.
# Citation format matches occurrence-gate.sh's own: grep -n gives "N:match".

_dvg_deny() {  # <path> <label> <hit "N:text"> <explanation>
  local path="$1" label="$2" hit="$3" explanation="$4" line matched
  line="${hit%%:*}"
  matched="$(printf '%s' "${hit#*:}" | cut -c1-120)"
  deny "In staged file $path, line $line: $label (\"$matched\"). $explanation Add: Derived-value-gate: N/A — <reason> (decoration fine)."
}

_dvg_check_duration() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE 'date -u -j -f|date -u -d "|\$\(\([^)]*_epoch[^)]*-[^)]*_epoch' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to compute a duration by hand (epoch subtraction)" "$hit" \
    "A script owns duration math — see hooks/lib/perf-log.sh's since subcommand."
}

_dvg_check_count() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE 'cardinality|Pin to the count seen in|RETRIES count|saw.*across[[:space:]]+[0-9]+[[:space:]]+runs[[:space:]]*—' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to tally or vote on a count by eye" "$hit" \
    "A script owns cardinality/majority-vote math — see hooks/lib/token-overlap.sh and hooks/lib/test-count-rerun.sh."
}

_dvg_check_compare() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE '^[[:space:]]*[Dd]oes[^.]*match[^.]*above|match(es)?[[:space:]]+the[^.]*output above|disagrees with the recorded' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "instructs a model to eyeball-compare a claimed value against an actual one" "$hit" \
    "A script owns the comparison (an awk range extract plus diff, or the same shape as hooks/lib/primer-detect.sh)."
}

_dvg_check_verbatim() {
  local content="$1" path="$2" hit
  hit="$(printf '%s' "$content" | grep -inoE 'not instructions to you|Illustrative only|List every file[^.]*do not summarize|Never omit it\. Never replace it with paraphrased prose|Always emit[^.]*exactly:' | head -1)"
  [ -n "$hit" ] || return 0
  _dvg_deny "$path" "ships fixed reference text or a determinism-compensating instruction as prompt prose" "$hit" \
    "Fixed output belongs in the script that computes the values around it (skills/session-continuity/REFERENCE.md or a spec, not a command body)."
}

# shellcheck disable=SC2329 # called indirectly by gate_scan_staged
gate_check() {
  local content="$1" path="$2" masked
  if gate_has_escape "$content" "Derived-value-gate"; then return 0; fi
  masked="$(gate_mask_escape "$content" "Derived-value-gate")"
  # Fixed priority order below (duration > count > compare > verbatim): a
  # line tripping two categories at once is cited under the first one
  # checked, not necessarily the earliest line in the file. Harmless — one
  # escape hatch clears every category — but worth knowing when reading a
  # denial that names a category other than the one you expected.
  _dvg_check_duration "$masked" "$path"
  _dvg_check_count "$masked" "$path"
  _dvg_check_compare "$masked" "$path"
  _dvg_check_verbatim "$masked" "$path"
}

gate_load
gate_is_commit || exit 0
gate_scan_staged gate_in_scope gate_check
exit 0
