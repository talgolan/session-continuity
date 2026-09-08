# CONTRACT_VERSION=1
# hooks/lib/token-overlap.jq — commit-subject / backlog-issue-title token
# overlap. Invoked via token-overlap.sh; see that file for the CLI contract.
#
# This is the cardinality-threshold overlap gate (tokenize, drop stopwords,
# intersect, threshold >=3) used to decide whether a commit plausibly
# touches a backlog item. It is unrelated to candidate-extract.jq's
# overlap() (a Jaccard *ratio* used for LEARNINGS-candidate dedup) — the two
# solve different problems and must not be conflated.

def stopwords: [
  "the","and","for","fix","add","update","from","with","into","feat",
  "chore","docs","primer","learnings","session","continuity","tag",
  "version","release"
];

def tokenize:
  ascii_downcase
  | gsub("[^a-z0-9]+"; " ")
  | [splits(" +")]
  | map(select(length >= 3))
  | map(select(. as $t | (stopwords | index($t)) == null))
  | unique;

def parse_issue_line:
  try (capture("^[0-9]+\\.\\s+#(?<n>[0-9]+)\\s+(?<title>.+)$")) catch null;

def parse_commit_line:
  try (capture("^\\S+\\s+(?<subject>.+)$")) catch null;

($issues_raw | split("\n") | map(select(length > 0)) | map(parse_issue_line)
  | map(select(. != null))
  | map({id: ("#" + .n), tokens: (.title | tokenize)})
) as $issues

| ($commits_raw | split("\n") | map(select(length > 0)) | map(parse_commit_line)
    | map(select(. != null))
    | map({subject: .subject, tokens: (.subject | tokenize)})
  ) as $commits

| $issues[] as $i
| $commits[] as $c
| ($i.tokens - ($i.tokens - $c.tokens)) as $inter
| select(($inter | length) >= 3)
| "\($i.id)\t\($c.subject)"
