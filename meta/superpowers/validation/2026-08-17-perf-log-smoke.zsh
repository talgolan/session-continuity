#!/usr/bin/env zsh
# perf-log.sh writer smoke test. Hermetic: runs against a throwaway temp
# git repo, never touches this repo's own working tree.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
perflog="$repo/hooks/lib/perf-log.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" config user.email "test@example.com"
git -C "$work" config user.name "Test"

# 1. Basic record call appends a parseable JSON line with the right fields.
( cd "$work" && bash "$perflog" record --source=hook --name=session-start.sh --duration=0.42 --exit=0 )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if [[ -z "$line" ]]; then
  bad "record: no line written"
else
  if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["source"]=="hook"; assert d["name"]=="session-start.sh"; assert d["duration_s"]==0.42; assert d["exit"]==0' 2>/dev/null; then
    ok "record: hook line parses with correct fields"
  else
    bad "record: hook line malformed: $line"
  fi
fi

# 2. Command-source line carries step/retries/items, omits exit.
( cd "$work" && bash "$perflog" record --source=command --name=end-session --step=step-1-outstanding-items-verification --duration=12.5 --items=5 )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["step"]=="step-1-outstanding-items-verification"; assert d["items"]==5; assert "exit" not in d' 2>/dev/null; then
  ok "record: command line carries step/items, omits exit"
else
  bad "record: command line malformed: $line"
fi

# 3. Gitignore marker: two calls => one gitignore line, one marker file.
gitignore_count="$(grep -c '^\.session-continuity/performance\.log$' "$work/.gitignore" 2>/dev/null || echo 0)"
if [[ "$gitignore_count" == "1" ]]; then
  ok "gitignore: exactly one entry after two record calls"
else
  bad "gitignore: expected 1 entry, got $gitignore_count"
fi
if [[ -f "$work/.session-continuity/.gitignore-ensured" ]]; then
  ok "gitignore: marker file created"
else
  bad "gitignore: marker file missing"
fi

# 4. Outside a git repo: silent no-op, no directory created, exit 0.
nogit="$(mktemp -d)"
( cd "$nogit" && bash "$perflog" record --source=hook --name=x.sh --duration=0.1 --exit=0 )
rc=$?
if [[ "$rc" == "0" && ! -d "$nogit/.session-continuity" ]]; then
  ok "non-git dir: silent no-op, exit 0"
else
  bad "non-git dir: expected no-op+exit0, got rc=$rc dir-exists=$([[ -d "$nogit/.session-continuity" ]] && echo yes || echo no)"
fi
rm -rf "$nogit"

# 5. Missing required flags: exit 0, no crash, no line written.
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" record --source=hook ) 2>/dev/null
rc=$?
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$rc" == "0" && "$before" == "$after" ]]; then
  ok "missing flags: exit 0, no line appended"
else
  bad "missing flags: expected exit0+no-append, got rc=$rc before=$before after=$after"
fi

# 6. Non-numeric --duration is rejected same as missing --duration: exit 0, no line written.
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" record --source=hook --name=x --duration=abc --exit=0 ) 2>/dev/null
rc=$?
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$rc" == "0" && "$before" == "$after" ]]; then
  ok "non-numeric duration: exit 0, no line appended"
else
  bad "non-numeric duration: expected exit0+no-append, got rc=$rc before=$before after=$after"
fi

# 7. Non-numeric optional --items is silently omitted from JSON (line still parses, no 'items' key).
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" record --source=command --name=end-session --step=test --duration=1.0 --items=notanumber ) 2>/dev/null
after="$(wc -l < "$work/.session-continuity/performance.log")"
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if [[ "$before" != "$after" ]] && print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert "items" not in d; assert d["duration_s"]==1.0' 2>/dev/null; then
  ok "non-numeric items: silently omitted, line still valid JSON"
else
  bad "non-numeric items: expected valid JSON without items key, got: $line"
fi

# 8. Non-numeric optional --exit is silently omitted from JSON (line still parses, no 'exit' key).
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" record --source=hook --name=test.sh --duration=0.5 --exit=nocode ) 2>/dev/null
after="$(wc -l < "$work/.session-continuity/performance.log")"
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if [[ "$before" != "$after" ]] && print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert "exit" not in d; assert d["duration_s"]==0.5' 2>/dev/null; then
  ok "non-numeric exit: silently omitted, line still valid JSON"
else
  bad "non-numeric exit: expected valid JSON without exit key, got: $line"
fi

# 9. String fields with quotes and backslashes round-trip correctly through json_escape.
( cd "$work" && bash "$perflog" record --source=hook --name='test"quote\slash.sh' --duration=0.1 --exit=0 ) 2>/dev/null
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["name"] == """test"quote\\slash.sh"""' 2>/dev/null; then
  ok "json_escape: quotes and backslashes escape correctly"
else
  bad "json_escape: quotes/backslashes malformed, got: $line"
fi

# 10. After record call, git status --porcelain does NOT list .gitignore-ensured as untracked.
untracked="$(cd "$work" && git status --porcelain | grep -cF '.session-continuity/.gitignore-ensured' 2>/dev/null || true)"
if [[ -z "$untracked" || "$untracked" == "0" ]]; then
  ok "gitignore-ensured: marker file is gitignored, not in git status"
else
  bad "gitignore-ensured: marker file shows as untracked (breaks fast path)"
fi

# 11. mark: writes a duration_s:0.000 record under the given step.
( cd "$work" && bash "$perflog" mark --source=command --name=markable --step=step-a-shown )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["name"]=="markable"; assert d["step"]=="step-a-shown"; assert d["duration_s"]==0.0' 2>/dev/null; then
  ok "mark: writes a step-tagged zero-duration record"
else
  bad "mark: malformed line: $line"
fi

# 12. mark: missing --step is rejected, exit 0, no line written.
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" mark --source=command --name=markable ) 2>/dev/null
rc=$?
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$rc" == "0" && "$before" == "$after" ]]; then
  ok "mark: missing --step rejected, exit 0, no line appended"
else
  bad "mark: expected exit0+no-append, got rc=$rc before=$before after=$after"
fi

# 13. since: resolves the prior mark and records elapsed time under --emit-step.
( cd "$work" && bash "$perflog" mark --source=command --name=sincetest --step=step-shown )
sleep 1
( cd "$work" && bash "$perflog" since --source=command --name=sincetest --mark-step=step-shown --emit-step=step-wait )
line="$(tail -1 "$work/.session-continuity/performance.log" 2>/dev/null)"
if print -r -- "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); assert d["name"]=="sincetest"; assert d["step"]=="step-wait"; assert d["duration_s"] >= 1.0' 2>/dev/null; then
  ok "since: records elapsed duration under emit-step"
else
  bad "since: malformed/wrong line: $line"
fi

# 14. since: no matching mark found -> silent no-op, exit 0, no line written.
before="$(wc -l < "$work/.session-continuity/performance.log")"
( cd "$work" && bash "$perflog" since --source=command --name=sincetest --mark-step=step-never-marked --emit-step=step-wait ) 2>/dev/null
rc=$?
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$rc" == "0" && "$before" == "$after" ]]; then
  ok "since: no matching mark -> exit 0, no line appended"
else
  bad "since: expected exit0+no-append, got rc=$rc before=$before after=$after"
fi

# 15. since --print-epoch: prints the mark's epoch, writes nothing to the log.
( cd "$work" && bash "$perflog" mark --source=command --name=epochtest --step=step-shown )
before="$(wc -l < "$work/.session-continuity/performance.log")"
epoch_out="$(cd "$work" && bash "$perflog" since --print-epoch --name=epochtest --mark-step=step-shown)"
after="$(wc -l < "$work/.session-continuity/performance.log")"
if [[ "$epoch_out" =~ ^[0-9]+$ && "$before" == "$after" ]]; then
  ok "since --print-epoch: prints a bare epoch, appends nothing"
else
  bad "since --print-epoch: expected numeric epoch + no-append, got epoch='$epoch_out' before=$before after=$after"
fi

# 16. since --print-epoch: no matching mark -> prints nothing, exit 0.
out="$(cd "$work" && bash "$perflog" since --print-epoch --name=epochtest --mark-step=step-never-marked)"
rc=$?
if [[ "$rc" == "0" && -z "$out" ]]; then
  ok "since --print-epoch: no matching mark -> prints nothing, exit 0"
else
  bad "since --print-epoch: expected empty+exit0, got out='$out' rc=$rc"
fi

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
