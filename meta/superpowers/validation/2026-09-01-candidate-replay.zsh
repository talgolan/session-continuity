#!/usr/bin/env zsh
# Replays hooks/lib/candidate-extract.jq over a directory of archived Claude
# Code transcripts and prints what each one would produce. NOT a pass/fail
# smoke test — archived transcripts are not in the repo and differ per machine.
# Run this after changing any heuristic and read the output: a candidate list
# full of heredoc fragments or bookkeeping commands means the rules regressed.
#
# Usage:
#   zsh meta/superpowers/validation/2026-09-01-candidate-replay.zsh [dir] [n]
#
#   dir  directory of *.jsonl transcripts
#        (default: ~/.claude/projects/<url-encoded cwd of this repo>)
#   n    how many of the largest transcripts to replay (default 6)
#
# It calls the .jq filter directly, bypassing candidate-extract.sh's 5-minute
# staleness guard, which would reject every archived file by design.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
filter="$repo/hooks/lib/candidate-extract.jq"

default_dir() {
  local enc="${PWD//\//-}"
  print -r -- "$HOME/.claude/projects/$enc"
}

dir="${1:-$(default_dir)}"
count="${2:-6}"

if [[ ! -d "$dir" ]]; then
  print -u2 "no transcript directory at $dir"
  print -u2 "pass one explicitly: zsh ${0:t} ~/.claude/projects/<encoded-cwd> 6"
  exit 1
fi

setopt local_options nullglob
matched=("$dir"/*.jsonl)
if (( ${#matched} == 0 )); then
  print -u2 "no .jsonl transcripts in $dir"
  exit 1
fi
files=("${(@f)$(ls -S -- "${matched[@]}" 2>/dev/null | head -"$count")}")

tracked="$(git ls-files 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null || print -r -- '[]')"

for f in $files; do
  [[ -n "$f" ]] || continue
  size="$(du -h "$f" | cut -f1)"
  start=$(date +%s%N 2>/dev/null | sed 's/N$/0/')
  out="$(jq -n --argjson tracked_files "$tracked" -f "$filter" "$f" 2>&1)"
  end=$(date +%s%N 2>/dev/null | sed 's/N$/0/')
  print -P "%F{cyan}== ${f:t} ($size, $(( (end - start) / 1000000 ))ms)%f"
  if ! print -r -- "$out" | jq -e . >/dev/null 2>&1; then
    print -P "  %F{red}filter error:%f $out"
    continue
  fi
  print -r -- "$out" | jq -r '
    "  mode=\(.mode) candidates=\(.candidates|length) overflow=\(.overflow)",
    (.candidates[] | "  [\(.heuristic)] \(.title)"),
    (.candidates[] | .evidence[0] | "      e: \(.)")'
done

print ""
print "Read the titles. Each one should name a command or a commit subject you"
print "recognise as a real investigation. Heredoc fragments (\"bun -e '\"),"
print "bookkeeping commands (\"git status\"), and raw multi-line commit bodies"
print "are regressions, not candidates."
