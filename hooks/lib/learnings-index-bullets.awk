# CONTRACT_VERSION=2
# Emits one "- <first 12 words of the symptom> — #<entry number>" line per
# entry. Lines inside fenced code blocks are examples, never entries.
/^```/ { fence = !fence; next }
fence { next }
/^### [0-9]+\./ {
  line = $0
  sub(/^### /, "", line)
  sub(/\..*/, "", line)
  num = line + 0
  have_num = 1
}
/^\*\*Symptom\.\*\* / && have_num {
  text = $0
  sub(/^\*\*Symptom\.\*\* /, "", text)
  n = split(text, words, /[ \t]+/)
  lim = (n < 12) ? n : 12
  out = ""
  for (i = 1; i <= lim; i++) out = out (i > 1 ? " " : "") words[i]
  if (n > 12) out = out "…"
  print "- " out " — #" num
  have_num = 0
}
