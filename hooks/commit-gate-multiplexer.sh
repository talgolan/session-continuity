#!/usr/bin/env bash
# hooks/commit-gate-multiplexer.sh — single-process driver for the Family A
# commit-time content gates (session-continuity plugin, #73 remediation 4).
#
# Replaces eight separate PreToolUse processes (pre-commit-check.sh plus the
# seven deny gates), each of which called gate_load and re-ran
# `git diff --cached` independently. Sources every gate script once — their
# own driver tails stay dormant when sourced (BASH_SOURCE[0] != $0) — loads
# the payload once, and runs each gate's scan in the same order the old
# hooks.json array used. The first gate to call deny() exits this whole
# process; see meta/superpowers/plans/2026-09-14-hooks-sprawl-remediation.md
# for why that's an accepted, intentional narrowing versus the old N-process
# design.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/gate-common.sh"
# shellcheck disable=SC1091
source "$HERE/pre-commit-check.sh"
# shellcheck disable=SC1091
source "$HERE/flaky-gate.sh"
# shellcheck disable=SC1091
source "$HERE/proven-gate.sh"
# shellcheck disable=SC1091
source "$HERE/smoke-gate.sh"
# shellcheck disable=SC1091
source "$HERE/evidence-gate.sh"
# shellcheck disable=SC1091
source "$HERE/backend-parity-gate.sh"
# shellcheck disable=SC1091
source "$HERE/occurrence-gate.sh"
# shellcheck disable=SC1091
source "$HERE/derived-value-gate.sh"

gate_load
gate_is_commit || exit 0

# Warm gate_staged_entries's memoized cache with a plain (non-substitution)
# call before any gate runs. Every downstream caller reaches it through
# `$(gate_staged_entries)` (inside a heredoc or a pipe), which forks a
# subshell — a cache write made *inside* that subshell never makes it back
# to this process, so without this warm-up each of the 7 gate_scan_staged
# calls below would still pay for its own `git diff --cached --name-status`.
# This plain call has no pipe/substitution around it, so it runs in this
# shell and the cache it populates is inherited by every later subshell.
gate_staged_entries >/dev/null

# shellcheck disable=SC2034 # consumed by sourced helpers
GATE_LABEL="Flaky-gate"
gate_scan_commit_message flaky_check_message || true
gate_scan_staged flaky_in_scope flaky_check_file

GATE_LABEL="Proven-gate"
gate_scan_staged proven_in_scope proven_check

GATE_LABEL="Smoke"
gate_scan_staged smoke_in_scope smoke_check

GATE_LABEL="Evidence-gate"
gate_scan_staged evidence_in_scope evidence_check

GATE_LABEL="Backend-parity"
gate_scan_staged backend_parity_in_scope backend_parity_check

GATE_LABEL="Occurrence-gate"
gate_scan_staged occurrence_in_scope occurrence_check

GATE_LABEL="Derived-value-gate"
gate_scan_staged derived_value_in_scope derived_value_check

precommit_check || true
exit 0
