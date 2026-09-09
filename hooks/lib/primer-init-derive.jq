# CONTRACT_VERSION=1
# hooks/lib/primer-init-derive.jq — pure placeholder-derivation for
# /session-continuity:primer Step 2 (Init mode). Invoked via
# primer-init-derive.sh; see that file for the CLI contract and
# meta/superpowers/specs/2026-09-09-primer-init-derive-design.md for the
# full output contract this implements.

(if $pkg_name != "" then $pkg_name
 elif $cargo_name != "" then $cargo_name
 elif $pyproject_name != "" then $pyproject_name
 else $dirname end) as $project_name

| ($git_log | split("\n") | map(select(length > 0))
   | map(if test("^\\S+\\s+.*$") then capture("^(?<hash>\\S+)\\s+(?<subject>.*)$")
         else {hash: ., subject: ""} end)
   | .[0:5]) as $commits
| ($commits | length) as $commit_count

| (if $test_cmd == "" then "TBD"
   else
     ( ($test_output | [scan("[0-9]+ pass(?:ed)?")] | .[0]?
        | if . then capture("^(?<n>[0-9]+)").n else null end) as $p
     | ($test_output | [scan("[0-9]+ fail(?:ed)?")] | .[0]?
        | if . then capture("^(?<n>[0-9]+)").n else null end) as $f
     | if $p != null and $f != null then
         "`" + $test_cmd + "` — " + $p + " pass / " + $f + " fail"
       else
         "`" + $test_cmd + "`"
       end
     )
   end) as $test_summary

| "PROJECT_NAME=" + $project_name,
  "WORKING_DIRECTORY_ABSOLUTE_PATH=" + $pwd,
  "COMMIT_COUNT=" + ($commit_count|tostring),
  (range(0;5) as $i
   | "LATEST_COMMIT_HASH_\($i+1)=" + ($commits[$i].hash // ""),
     "LATEST_COMMIT_SUBJECT_\($i+1)=" + ($commits[$i].subject // "")),
  "TEST_CMD=" + $test_cmd,
  "TEST_COMMAND_SUMMARY=" + $test_summary
