#!/usr/bin/env bash
# CONTRACT_VERSION=1
# peer-probes.sh — ENGRIM + GRAPHIFY probes. Always exit 0.
# Usage: peer-probes.sh [<project-dir>]
# Stdout order (locked): ENGRIM line, then GRAPHIFY line.
set -u
DIR="${1:-.}"
ENGRIM_BIN="${ENGRIM_BIN:-engrim}"
TIMEOUT="${PEER_PROBES_TIMEOUT:-2}"

# ENGRIM — path with / must be -x; bare name uses command -v
if [[ "$ENGRIM_BIN" == */* ]]; then
  if [[ ! -x "$ENGRIM_BIN" ]]; then
    echo "ENGRIM=missing"
  elif timeout "$TIMEOUT" "$ENGRIM_BIN" context -b 200 >/dev/null 2>&1; then
    echo "ENGRIM=ok"
  else
    echo "ENGRIM=error"
  fi
elif ! command -v "$ENGRIM_BIN" >/dev/null 2>&1; then
  echo "ENGRIM=missing"
elif timeout "$TIMEOUT" "$ENGRIM_BIN" context -b 200 >/dev/null 2>&1; then
  echo "ENGRIM=ok"
else
  echo "ENGRIM=error"
fi

# GRAPHIFY
if [[ -s "$DIR/graphify-out/graph.json" ]]; then
  echo "GRAPHIFY=ok"
else
  echo "GRAPHIFY=missing"
fi
exit 0
