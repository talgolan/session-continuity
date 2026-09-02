# CONTRACT_VERSION=1
# Renders .session-continuity/BACKLOG.md as one line per item:
#   "<counter> [<tag>] [<date>] <Title>"
# <counter> is this pass's OWN 1..N count — the file's own <position> number
# is discarded, so gaps/duplicates in the file self-heal on display.
#
# Lines inside a fenced code block (```) or an HTML comment (<!-- ... -->),
# including either nested inside the other, are never entries — this is the
# same defect class hooks/lib/count-entries.sh was written to close for the
# same two files (BACKLOG.md/LEARNINGS.md example headings shipped inside
# template comments). Emits nothing for a file with no items; render.sh
# handles the empty case.
#
# A "### N. [tag] — closed. ..." stub (kept only so tag cross-references
# still resolve, per BACKLOG.md's own convention) has no "[date]" segment,
# so it fails the shape check below and is silently skipped — exactly the
# self-healing behavior the counter re-numbering is meant to provide.

BEGIN { fence = 0; in_comment = 0; n = 0 }

{
  line = $0

  # A fence delimiter always toggles fence state, whether or not we are
  # currently inside a comment — this is what keeps a fence nested inside a
  # comment (or vice versa) from leaking state once the outer block closes.
  if (line ~ /^```/) { fence = !fence; next }
  if (fence) next

  if (in_comment) {
    if (index(line, "-->") > 0) in_comment = 0
    next
  }

  if (index(line, "<!--") > 0) {
    rest = substr(line, index(line, "<!--") + 4)
    if (index(rest, "-->") == 0) { in_comment = 1; next }
    next
  }
}

/^### [0-9]+\./ {
  rest = $0
  sub(/^### [0-9]+\.[ \t]+/, "", rest)

  if (substr(rest, 1, 1) != "[") next
  close1 = index(rest, "]")
  if (close1 == 0) next
  tag = substr(rest, 2, close1 - 2)

  after_tag = substr(rest, close1 + 1)
  sub(/^[ \t]+/, "", after_tag)
  if (substr(after_tag, 1, 1) != "[") next
  close2 = index(after_tag, "]")
  if (close2 == 0) next
  date = substr(after_tag, 2, close2 - 2)
  if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) next

  title = substr(after_tag, close2 + 1)
  sub(/^[ \t]+/, "", title)
  if (title == "") next

  n++
  printf "%d [%s] [%s] %s\n", n, tag, date, title
}
