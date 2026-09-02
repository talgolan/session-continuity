# CONTRACT_VERSION=1
# Renders .session-continuity/LEARNINGS.md grouped by "## <section>"
# heading, in file order, as:
#   ## <section>
#   <n>. <Title>
#   <n>. <Title>
#
#   ## <next section>
#   ...
#
# Entry numbers are printed verbatim (LEARNINGS.md numbers are permanent —
# sorting or renumbering them is a bug). The "## Symptoms index" section is
# skipped outright (bullets, not entries); any other section that yields
# zero entries is also skipped (this repo has three today: "## Security
# incidents", "## Anti-patterns we were tempted by (and rejected)", and
# "## Checklist for a fresh dev-env setup").
#
# Lines inside a fenced code block (```) or an HTML comment (<!-- ... -->),
# including either nested inside the other, are never entries or section
# headings — same defect class hooks/lib/count-entries.sh closes for this
# same file (shipped templates carry example "### N." headings inside
# "<!-- Example: ... -->" comments).

function flush() {
  if (have_section && entry_count > 0) {
    print "## " section
    printf "%s", buf
    print ""
  }
}

BEGIN {
  fence = 0; in_comment = 0
  section = ""; have_section = 0; entry_count = 0; buf = ""
}

{
  line = $0

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

/^## / {
  flush()
  section = substr($0, 4)
  have_section = 1
  entry_count = 0
  buf = ""
  next
}

/^### [0-9]+\./ {
  if (section == "Symptoms index") next
  rest = $0
  sub(/^### /, "", rest)
  buf = buf rest "\n"
  entry_count++
  next
}

END { flush() }
