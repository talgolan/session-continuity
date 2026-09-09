#!/usr/bin/env bash
# CONTRACT_VERSION=1
# primer-validate.sh — hard-template + banlist gate for SESSION_PRIMER.md
# Usage: primer-validate.sh <primer-file>
# Exit 0 if valid; 1 if invalid. Stderr: INVALID: <reason> (all reasons).
set -u

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "INVALID: primer file required (readable path)" >&2
  exit 1
fi

# Single awk pass collects reasons (one per line); bash prints INVALID: prefixes.
reasons=$(awk '
function add(msg) {
  if (msg in seen_reason) return
  seen_reason[msg] = 1
  n_reasons++
  reasons[n_reasons] = msg
}

BEGIN {
  allowed["Boot order"] = 1
  allowed["Mid-flight"] = 1
  allowed["Confirm"] = 1
  allowed["Peers"] = 1
}

{
  lines[NR] = $0
}

END {
  # --- H1 / ## headings (ignore fenced bodies) ----------------------------
  h1_ok = 0
  h1_total = 0
  in_fence = 0
  for (i = 1; i <= NR; i++) {
    if (lines[i] ~ /^```/) {
      in_fence = !in_fence
      continue
    }
    if (in_fence) continue
    if (lines[i] ~ /^# / && lines[i] !~ /^## /) {
      h1_total++
      if (lines[i] ~ /^# Session Primer — /) h1_ok++
    }
    if (lines[i] ~ /^## /) {
      h = substr(lines[i], 4)
      if (!(h in allowed))
        add("unknown heading '\''## " h "'\''")
      else
        present[h] = 1
    }
  }
  if (h1_ok != 1 || h1_total != 1)
    add("expected exactly one H1 matching '\''^# Session Primer — '\''")
  if (!("Boot order" in present)) add("missing heading '\''## Boot order'\''")
  if (!("Mid-flight" in present)) add("missing heading '\''## Mid-flight'\''")
  if (!("Confirm" in present)) add("missing heading '\''## Confirm'\''")
  if (!("Peers" in present)) add("missing heading '\''## Peers'\''")

  # --- Locate first ```bash fence under ## Confirm ------------------------
  in_confirm = 0
  fence_start = 0
  fence_end = 0
  for (i = 1; i <= NR; i++) {
    if (lines[i] ~ /^## Confirm$/) { in_confirm = 1; continue }
    if (in_confirm && lines[i] ~ /^## /) { in_confirm = 0 }
    if (in_confirm && lines[i] ~ /^```bash[[:space:]]*$/ && fence_start == 0) {
      fence_start = i
      continue
    }
    if (fence_start > 0 && fence_end == 0 && lines[i] ~ /^```[[:space:]]*$/) {
      fence_end = i
      break
    }
  }

  # --- Confirm command count ----------------------------------------------
  cmd_count = 0
  if (fence_start > 0 && fence_end > fence_start) {
    for (i = fence_start + 1; i < fence_end; i++) {
      line = lines[i]
      if (line ~ /^[[:space:]]*$/) continue
      if (line ~ /^#/) continue
      cmd_count++
    }
  }
  if (cmd_count > 5)
    add("Confirm counted commands (" cmd_count ") exceed 5")

  # --- Line budget ≤80 excluding Confirm fence ----------------------------
  fence_lines = 0
  if (fence_start > 0 && fence_end >= fence_start)
    fence_lines = fence_end - fence_start + 1
  budget = NR - fence_lines
  if (budget > 80)
    add("line budget (" budget ") exceeds 80 excluding Confirm fence")

  # --- Mid-flight bullets ≤5 ----------------------------------------------
  in_mf = 0
  bullets = 0
  for (i = 1; i <= NR; i++) {
    if (lines[i] ~ /^## Mid-flight$/) { in_mf = 1; continue }
    if (in_mf && lines[i] ~ /^## /) { in_mf = 0 }
    if (in_mf && (lines[i] ~ /^ - / || lines[i] ~ /^- /)) bullets++
  }
  if (bullets > 5)
    add("Mid-flight bullets (" bullets ") exceed 5")

  # --- Banlist: whole-file precise substrings -----------------------------
  for (i = 1; i <= NR; i++) {
    if (index(lines[i], "git log --oneline") > 0)
      add("banlist: contains '\''git log --oneline'\''")
    if (lines[i] ~ /^## Outstanding/)
      add("banlist: contains '\''## Outstanding'\''")
    if (lines[i] ~ /^## Current state/)
      add("banlist: contains '\''## Current state'\''")
  }

  # --- Banlist: any fenced block body -------------------------------------
  in_fence = 0
  body = ""
  for (i = 1; i <= NR; i++) {
    if (lines[i] ~ /^```/) {
      if (in_fence) {
        if (index(body, "git log") > 0)
          add("banlist: fenced block body contains '\''git log'\''")
        n = split(body, blines, "\n")
        for (j = 1; j <= n; j++) {
          if (blines[j] ~ /^git log( |$)/) {
            add("banlist: fenced line matching ^git log( |$)")
            break
          }
        }
        in_fence = 0
        body = ""
        continue
      }
      in_fence = 1
      body = ""
      continue
    }
    if (in_fence) {
      if (body != "") body = body "\n"
      body = body lines[i]
    }
  }

  for (i = 1; i <= n_reasons; i++)
    print reasons[i]
}
' "$FILE")

rc=0
if [[ -n "$reasons" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    echo "INVALID: $line" >&2
    rc=1
  done <<<"$reasons"
fi
exit "$rc"
