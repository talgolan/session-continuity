# hooks/lib/candidate-extract.jq — LEARNINGS candidate extraction + heuristics A-D.
# Invoked via: jq -n --argjson tracked_files <json array from `git ls-files`> \
#   -f candidate-extract.jq <transcript.jsonl>
# See meta/superpowers/specs/2026-09-01-end-session-step2-cost-attribution-design.md
# Change 1. Absorbs the previously-inline Step-2 extraction filter unchanged,
# plus Heuristics A-D and the dedup/sort/cap output rules, so the agent
# invokes this once instead of re-filtering per heuristic.

def to_epoch: gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;

def norm_err:
  if (. == null or . == "") then ""
  else
    .
    | gsub("(?<p>/[^ :\"]+/)(?<b>[^/ :\"]+)"; "\(.b)")
    | gsub(":[0-9]+:[0-9]+"; "")
    | gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?"; "")
    | gsub("[0-9]{2}:[0-9]{2}:[0-9]{2}"; "")
    | gsub("0x[0-9a-fA-F]+"; "0xN")
  end;

def first_line_from_text:
  (split("\n") | map(select(length>0))) as $ls
  | if ($ls|length)==0 then ""
    elif ($ls[0] | test("^Exit code")) then ($ls[1] // "")
    else $ls[0]
    end;

def err_line_of($is_error; $stderr; $text):
  if ($stderr // "") != "" then $stderr
  elif $is_error then ($text // "" | first_line_from_text)
  else (($text // "" | split("\n") | map(select(test("^Error:"))) | .[0]) // "")
  end;

def norm_cmd: (split("\n")[0]) | gsub("[ \t]+"; " ") | sub("^ +"; "") | sub(" +$"; "");

def is_pure_read($cmd): $cmd | test("^ *(cat|ls|grep|find|stat|pwd|which|echo)( |$)");

def title_words:
  ascii_downcase
  | gsub("[^a-z0-9 ]+"; " ")
  | [splits(" +")]
  | map(select(length > 0));

def overlap($ta; $tb):
  ($ta | title_words) as $wa
  | ($tb | title_words) as $wb
  | ($wa + $wb | unique) as $u
  | if ($u|length) == 0 then 0
    else (($wa - ($wa - $wb)) | length) / ($u | length)
    end;

[inputs] as $lines

# --- shared extraction (unchanged from the previously-inline filter) -------
| ($lines
    | map(select(.type=="user" and (.message.content|type)=="array"))
    | map(. as $line
        | $line.message.content[]?
        | select(.type=="tool_result")
        | {
            ts: $line.timestamp,
            tool_use_id: .tool_use_id,
            is_error: (.is_error // false),
            text: (.content | if type=="string" then . else tostring end),
            stderr: ($line.toolUseResult | if type=="object" then .stderr else null end)
          })
  ) as $tool_results
| ($tool_results | map(. + {err_line: err_line_of(.is_error; .stderr; .text)})) as $tool_results2
| ($tool_results2 | map({key: .tool_use_id, value: .}) | from_entries) as $results_by_id
| ($lines
    | map(select(.type=="assistant"))
    | map(. as $line | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | {
        ts: $line.timestamp,
        tool_use_id: .id,
        command: .input.command,
        result: ($results_by_id[.id] // {is_error:false, err_line:""})
      })
  ) as $bash_calls_raw
| ($bash_calls_raw | map({
      ts, command,
      is_error: .result.is_error,
      first_err_line: (.result.err_line | norm_err),
      norm_command: (.command | norm_cmd)
    })) as $bash_calls
| ($bash_calls_raw | map(select(.command | test("git commit"))) | map({ts, command})) as $commits
| ($tool_results2 | map(select(.err_line != "")) | map({ts, err: (.err_line | norm_err)})) as $errors

# --- Heuristic A: retry burst ---------------------------------------------
| ($bash_calls
    | map(select(is_pure_read(.norm_command) | not))
    | group_by(.norm_command)
    | map(select(length >= 3))
    | map({
        heuristic: "retry-burst",
        title: (.[0].norm_command + " — investigated for " + (length|tostring) + " retries."),
        evidence: (.[0:3] | map("Bash @ " + .ts + " → " + (if .is_error then ("exit 1 (\"" + .first_err_line + "\")") else "exit 0" end))),
        evidence_count: length
      })
  ) as $heuristic_a

# --- Heuristic B: revert / reset -------------------------------------------
| ($bash_calls
    | map(select(
        (.command | test("git\\s+reset\\s+--hard"))
        or (.command | test("git\\s+checkout\\s+--\\s"))
        or (.command | test("git\\s+revert"))
        or (.command | test("git\\s+restore"))
        or ((.command | test("rm\\s+-rf\\s+"))
            and (.command as $cmd | $tracked_files | any(. as $f | ($f|length) > 0 and ($cmd | contains($f)))))
      ))
    | map({
        heuristic: "revert",
        title: ("Reverted approach: " + .command + "."),
        evidence: [("Bash @ " + .ts + " → " + .command)],
        evidence_count: 1
      })
  ) as $heuristic_b

# --- Heuristic C: error recurrence -----------------------------------------
| ($errors
    | map(select(.err != ""))
    | group_by(.err)
    | map(select(length >= 3))
    | map(select((((.[-1].ts | to_epoch) - (.[0].ts | to_epoch))) >= 900))
    | map({
        heuristic: "error-recurrence",
        title: (.[0].err + " — recurred " + (length|tostring) + " times over "
                + ((((.[-1].ts | to_epoch) - (.[0].ts | to_epoch)) / 60) | floor | tostring) + " minutes."),
        evidence: (.[0:3] | map("@ " + .ts)),
        evidence_count: length
      })
  ) as $heuristic_c

# --- Heuristic D: fix burst -------------------------------------------------
| ($commits
    | map(select(.command | test("fix(\\([^)]*\\))?:")))
    | map(. as $c
        | ($c.ts | to_epoch) as $c_epoch
        | ($bash_calls | map(select((.ts | to_epoch) < $c_epoch and (.ts | to_epoch) >= ($c_epoch - 1800)))) as $preceding
        | if ($preceding|length) >= 10 then
            {
              heuristic: "fix-burst",
              title: ($c.command + " — fix preceded by " + ($preceding|length|tostring) + "-action investigation."),
              evidence: ([$preceding[0], $preceding[($preceding|length)/2|floor], $preceding[-1]] | map("Bash @ " + .ts)),
              evidence_count: ($preceding|length)
            }
          else empty
          end
      )
  ) as $heuristic_d

# --- union, dedupe by title-word overlap, sort, cap -------------------------
| ($heuristic_a + $heuristic_b + $heuristic_c + $heuristic_d) as $all
| ($all | sort_by(-.evidence_count)) as $sorted_all
| (reduce $sorted_all[] as $cand ([];
      if (. as $kept | any($kept[]; overlap($cand.title; .title) >= 0.7)) then .
      else . + [$cand]
      end
    )) as $deduped
| ($deduped | length) as $total
| ($deduped[0:5] | map(del(.evidence_count))) as $capped
| {
    mode: "transcript",
    candidates: $capped,
    overflow: (if $total > 5 then $total - 5 else 0 end)
  }
