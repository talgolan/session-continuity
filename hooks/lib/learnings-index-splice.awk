function emit_block() {
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
}
BEGIN { replaced = 0; in_old = 0; skip_one_blank = 0 }
/^## Symptoms index/ && !replaced {
  emit_block()
  print ""
  print "---"
  print ""
  in_old = 1
  replaced = 1
  next
}
in_old && /^## / { in_old = 0 }
in_old { next }
!has_index && !replaced && /^---$/ {
  emit_block()
  print ""
  print "---"
  print ""
  replaced = 1
  skip_one_blank = 1
  next
}
skip_one_blank && /^$/ { skip_one_blank = 0; next }
skip_one_blank { skip_one_blank = 0 }
{ print }
