# CONTRACT_VERSION=2
# hooks/lib/candidate-extract.jq — LEARNINGS candidate extraction + heuristics.
# Invoked via: jq -n --argjson tracked_files <json array from `git ls-files`> \
#   -f candidate-extract.jq <transcript.jsonl>
# See meta/superpowers/plans/2026-09-01-learnings-generation-hardening.md.
#
# Every rule here was validated by replaying it over four real multi-megabyte
# session transcripts. The prose in commands/end-session.md documents what this
# file decides; this file is the only thing that decides it.

# Never throws: a record with a timestamp this cannot parse yields null and is
# skipped, instead of aborting the whole filter and rendering as "no candidates".
def to_epoch: try (gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null;

def redact_paths: gsub("/(Users|home)/[^/ ]+/"; "~/");

# Command identity: the whole command with every run of whitespace — newlines
# included — collapsed. Two heredocs with different bodies are different
# commands; identical re-runs remain identical.
def norm_full: gsub("[ \t\r\n]+"; " ") | sub("^ +"; "") | sub(" +$"; "");

def strip_prefix:
  sub("^cd +[^ ]+ +&& +"; "")
  | sub("^timeout +[0-9]+ +"; "")
  | sub("^env +[A-Za-z_][A-Za-z0-9_]*=[^ ]+ +"; "");

# Family key: digits that follow a `-` or `=` are argument values, so
# `tail -8` and `tail -15` are one family. Digits elsewhere (dates in
# filenames, PR numbers) stay, so unrelated commands do not merge.
def fam_key:
  gsub("(?<p>[-=])[0-9]+"; "\(.p)N")
  | gsub("[0-9]+>&[0-9]+"; "N>&N");

def is_bookkeeping:
  strip_prefix
  | (test("^(cat|ls|grep|rg|find|stat|pwd|which|echo|printf|wc|head|tail|sed|awk|jq|du|file|date|env|tree|mkdir|touch|chmod|open)( |$)")
     or test("^git +(status|diff|log|show|branch|add|commit|stash|rev-parse|ls-files)( |$)"));

# A git verb only counts when it sits at a command position. Without this, any
# command whose *text* mentions "git revert" matches — including, measurably,
# the jq program the agent used to run this very heuristic by hand.
def is_revert:
  (test("(^|&& |; |\\| )git +reset +--hard"))
  or (test("(^|&& |; |\\| )git +revert( |$)"))
  or (test("(^|&& |; |\\| )git +restore( |$)"))
  or (test("(^|&& |; |\\| )git +checkout +-- "));

# Show the segment that matched, not the head of a compound command: a real
# `git checkout -- <path>` was found sitting behind two tmux teardowns.
def revert_segment:
  ([splits(" *(&&|;|\\|) *")] | map(select(length > 0))) as $segs
  | (($segs | map(select(is_revert or test("^rm +-rf +"))) | .[0]) // ($segs | .[0]) // .);

def display_of:
  (split("\n")[0]) as $first
  | (if ($first | length) > 76 then ($first[0:76] + "…")
     elif test("\n") then ($first + " …")
     else $first end)
  | redact_paths;

# Prefer a line that reads like an error over the first line of output — the
# first line of a failing `bun test` is its version banner, which produced the
# title "bun test v1.3.14 (0d9b296a) — recurred 2 times" on a real transcript.
def error_line:
  (split("\n") | map(select(length > 0)) | map(select(test("^Exit code") | not))) as $ls
  | (($ls | map(select(test("(?i)(error|fail|fatal|cannot|can.t|no such|not found|no matches|denied|refused|unexpected|invalid|missing)"))) | .[0])
     // ($ls | .[0])
     // "")
  | .[0:160];

def norm_err:
  if (. == null or . == "") then ""
  else
    redact_paths
    | gsub("(?<p>/[^ :\"]+/)(?<b>[^/ :\"]+)"; "\(.b)")
    | gsub(":[0-9]+:[0-9]+"; "")
    | gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?"; "")
    | gsub("[0-9]{2}:[0-9]{2}:[0-9]{2}"; "")
    | gsub("0x[0-9a-fA-F]+"; "0xN")
    | norm_full
  end;

# The subject only: from -m "…", -m '…', or the first non-empty line of a
# heredoc body. Never the whole command — a real commit body ran to 20 lines.
def commit_subject:
  . as $c
  | if ($c | test("<<[ ]*'?\"?EOF")) then
      (($c | split("\n") | .[1:] | map(select(length > 0)) | .[0]) // "unrecorded")
    else
      ((try ($c | capture("-m +\"(?<s>[^\"]*)\"") | .s) catch null)
       // (try ($c | capture("-m +'(?<s>[^']*)'") | .s) catch null)
       // "unrecorded")
    end;

def title_words:
  ascii_downcase
  | gsub("[^a-z0-9 ]+"; " ")
  | [splits(" +")]
  | map(select(length > 0));

def overlap($ta; $tb):
  ($ta | title_words) as $wa
  | ($tb | title_words) as $wb
  | ($wa + $wb | unique) as $u
  | if ($u | length) == 0 then 0
    else (($wa - ($wa - $wb)) | length) / ($u | length)
    end;

[inputs] as $lines

# --- shared extraction -------------------------------------------------------
| ($lines
    | map(select(.type=="assistant"))
    | map(. as $l | $l.message.content[]?
        | select(.type=="tool_use")
        | {ts: $l.timestamp, name: .name, id: (.id // ""), command: (.input.command // "")})
  ) as $tool_uses

| ($tool_uses
    | map(select(.name=="Edit" or .name=="Write" or .name=="MultiEdit"))
    | map(.ts) | sort
  ) as $edit_ts

| ($lines
    | map(select(.type=="user" and (.message.content|type)=="array"))
    | map(. as $l | $l.message.content[]?
        | select(.type=="tool_result")
        | {ts: $l.timestamp,
           tool_use_id: (.tool_use_id // ""),
           is_error: (.is_error // false),
           text: (.content | if type=="string" then . else tostring end)})
  ) as $tool_results

# Failure signal: is_error, or a body that opens with a non-zero exit line.
# stderr and a leading "Error:" matched nothing across 1155 real tool results.
| ($tool_results
    | map(. + {err: (if (.is_error or (.text | test("^Exit code [1-9]")))
                     then (.text | error_line)
                     else "" end)})
  ) as $results

| ($results | map({key: .tool_use_id, value: .}) | from_entries) as $by_id

| ($tool_uses
    | map(select(.name=="Bash"))
    | map(. as $b
        | ($by_id[$b.id] // {is_error: false, err: ""}) as $r
        | {ts: $b.ts,
           command: $b.command,
           key: ($b.command | norm_full),
           fam: ($b.command | norm_full | fam_key),
           is_error: $r.is_error,
           err: ($r.err | norm_err)})
  ) as $bash

# --- Heuristic A: retry burst ------------------------------------------------
| ($bash
    | map(select(.key | is_bookkeeping | not))
    | group_by(.fam)
    | map(select(length >= 3))
    | map(. as $g
        | ($g | group_by(.key) | max_by(length)) as $top
        | ([$edit_ts[] | select(. > $g[0].ts and . < $g[-1].ts)] | length) as $edits
        | if $edits >= 1 then
            {heuristic: "retry-burst",
             title: (($top[0].command | display_of)
                     + " — re-run " + ($g | length | tostring)
                     + " times with " + ($edits | tostring) + " file edits in between."),
             evidence: ($g[0:3] | map("Bash @ " + .ts + " → "
                        + (if .err != "" then ("failed: " + .err) else "ok" end))),
             evidence_count: ($g | length)}
          else empty
          end)
  ) as $heuristic_a

# --- Heuristic B: revert / reset ---------------------------------------------
| ($bash
    | map(select(
        (.key | is_revert)
        or ((.key | test("(^|&& |; )rm +-rf +"))
            and ((.key | [splits(" +")]) as $toks
                 | $tracked_files
                 | any(. as $f
                       | ($f | length) > 0
                       and ($toks | any(. as $t | $t == $f or ($f | startswith($t + "/")))))))))
    | map({heuristic: "revert",
           title: ("Reverted approach: " + (.key | revert_segment | display_of) + "."),
           evidence: [("Bash @ " + .ts + " → " + (.key | revert_segment | display_of))],
           evidence_count: 1})
  ) as $heuristic_b

# --- Heuristic C: error recurrence -------------------------------------------
| ($bash | map(select(.err != "")) | map({ts: .ts, err: .err})) as $errors
| ($errors
    | group_by(.err)
    | map(select(length >= 2))
    | map(. as $g
        | ((($g[-1].ts | to_epoch) // 0) - (($g[0].ts | to_epoch) // 0)) as $span
        | if $span >= 300 then
            {heuristic: "error-recurrence",
             title: ("\"" + ($g[0].err | if length > 120 then .[0:120] + "…" else . end)
                     + "\" — recurred " + ($g | length | tostring)
                     + " times over " + (($span / 60) | floor | tostring) + " minutes."),
             evidence: ($g[0:3] | map("@ " + .ts)),
             evidence_count: ($g | length)}
          else empty
          end)
  ) as $heuristic_c

# --- Heuristic D: fix burst ---------------------------------------------------
| ($bash
    | map(select(.key | test("git +commit")))
    | map(. + {subject: (.command | commit_subject)})
    | map(select(.subject | test("^fix(\\([^)]*\\))?: ")))
  ) as $fix_commits
| ($fix_commits
    | map(. as $c
        | (($c.ts | to_epoch) // null) as $e
        | if $e == null then empty
          else
            ($bash | map(select(
                ((.ts | to_epoch) // 0) < $e
                and ((.ts | to_epoch) // 0) >= ($e - 1800)
                and (.key | is_bookkeeping | not)))) as $w
            | ($w | group_by(.fam) | map(select(length >= 3)) | length) as $clusters
            | if ($w | length) >= 10 and $clusters >= 1 then
                {heuristic: "fix-burst",
                 title: ($c.subject + " — fix preceded by a "
                         + ($w | length | tostring) + "-action investigation."),
                 evidence: ([$w[0], $w[(($w | length) / 2 | floor)], $w[-1]]
                            | map("Bash @ " + .ts + " → " + (.command | display_of))),
                 evidence_count: ($w | length)}
              else empty
              end
          end)
  ) as $heuristic_d

# --- union, dedupe, per-heuristic cap, overall cap ---------------------------
| ($heuristic_a + $heuristic_b + $heuristic_c + $heuristic_d) as $all
| ($all | sort_by(-.evidence_count)) as $sorted
| (reduce $sorted[] as $cand ([];
      if (. as $kept | any($kept[]; overlap($cand.title; .title) >= 0.7)) then .
      else . + [$cand]
      end)) as $deduped
| (reduce $deduped[] as $cand ({kept: [], counts: {}};
      ((.counts[$cand.heuristic] // 0)) as $n
      | if $n >= 2 then .
        else {kept: (.kept + [$cand]),
              counts: (.counts | .[$cand.heuristic] = ($n + 1))}
        end)
   | .kept) as $balanced
| ($balanced[0:5] | map(del(.evidence_count))) as $capped
| {mode: "transcript",
   candidates: $capped,
   overflow: (($deduped | length) - ($capped | length)),
   detail: ""}
