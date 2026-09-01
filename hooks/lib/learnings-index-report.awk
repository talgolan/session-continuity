# CONTRACT_VERSION=2
/^### [0-9]+\./ {
  line = $0
  sub(/^### /, "", line)
  sub(/\..*/, "", line)
  num = line + 0
  cnt[num]++
  lines[num] = (cnt[num] == 1) ? NR : (lines[num] "," NR)
  if (num > max) max = num
}
/^Slug:[ \t]*/ {
  s = $0
  sub(/^Slug:[ \t]*/, "", s)
  gsub(/[ \t]+$/, "", s)
  scnt[s]++
  slines[s] = (scnt[s] == 1) ? NR : (slines[s] "," NR)
}
END {
  print "MAX", max + 0
  for (n in cnt) if (cnt[n] > 1) print "DUPNUM", n, lines[n]
  for (s in scnt) if (scnt[s] > 1) print "DUPSLUG", s, slines[s]
}
