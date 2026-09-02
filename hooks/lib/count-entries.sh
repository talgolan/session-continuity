#!/usr/bin/env bash
# CONTRACT_VERSION=1
# hooks/lib/count-entries.sh — counts "### N." entry headings in a markdown
# file, ignoring any that fall inside an HTML comment (<!-- ... -->) or a
# fenced code block (```), including either nested inside the other.
# See meta/superpowers/plans/2026-09-02-fresh-install-count-defects.md
#
# Usage:
#   count-entries.sh <file>   Prints one integer on stdout and exits 0.
#
# Bad input (no argument, missing file, unreadable file, empty file) prints
# 0 and exits 0 — this is not an error, matching learnings-index.sh's
# contract. This script never writes anything.
#
# `grep -cE '^### [0-9]+\.'`, the expression this replaces, cannot do this
# job: it has no notion of "inside a comment" or "inside a fence", so it
# counts the exemplar headings shipped in the templates as real entries, and
# `grep -c` prints "0" and exits 1 at zero matches, so a caller relying on
# `grep -c ... || echo 0` gets two lines instead of one at the very count
# (zero) it was written to handle.

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" || ! -r "$FILE" ]]; then
  echo 0
  exit 0
fi

awk '
  BEGIN { in_comment = 0; in_fence = 0; count = 0 }
  {
    line = $0

    # A fence delimiter always toggles fence state, whether or not we are
    # currently inside a comment — this is what keeps a fence nested inside
    # a comment (or vice versa) from leaking state once the outer block
    # closes.
    if (line ~ /^```/) { in_fence = !in_fence; next }
    if (in_fence) next

    if (in_comment) {
      if (index(line, "-->") > 0) in_comment = 0
      next
    }

    if (index(line, "<!--") > 0) {
      # A comment that opens and closes on the same line leaves in_comment
      # unchanged (false); one that opens without closing sets in_comment
      # and every line up to the closer is skipped, including this one.
      rest = substr(line, index(line, "<!--") + 4)
      if (index(rest, "-->") == 0) { in_comment = 1; next }
    }

    if (line ~ /^### [0-9]+\./) count++
  }
  END { print count + 0 }
' "$FILE"
