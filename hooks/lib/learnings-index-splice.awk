# CONTRACT_VERSION=2
# Replaces (or inserts) the "## Symptoms index" section. Reads the sorted
# bullet lines from the file named by -v bfile; -v has_index tells it whether
# the input already contains the section. Every input line is printed exactly
# once except the old section body, which is replaced wholesale.
function emit_section(   bline) {
  print "## Symptoms index"
  print ""
  print "<!--"
  print "  Fully derived — never hand-edit. The /session-continuity:learning"
  print "  command regenerates this list from every entry's **Symptom.** line"
  print "  each time it appends a new entry."
  print "-->"
  print ""
  while ((getline bline < bfile) > 0) print bline
  close(bfile)
  print ""
  print "---"
  print ""
}
BEGIN { replaced = 0; in_old = 0; fence = 0 }
/^```/ { fence = !fence; print; next }
fence { print; next }
/^## Symptoms index/ && !replaced {
  emit_section()
  in_old = 1
  replaced = 1
  next
}
in_old && /^## / { in_old = 0 }
in_old { next }
!has_index && !replaced && /^## / {
  emit_section()
  replaced = 1
}
{ print }
END {
  if (!replaced) emit_section()
}
