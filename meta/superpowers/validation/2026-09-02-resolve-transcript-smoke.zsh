#!/usr/bin/env zsh
# resolve-transcript.sh smoke test. Hermetic: synthetic $HOME and cwd dirs;
# the real ~/.claude/projects is never touched.
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
lib="$repo/hooks/lib"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

fake_home="$(mktemp -d)"
proj_cwd_raw="$(mktemp -d)"
# Resolve symlinks (e.g. macOS /tmp -> /private/tmp) so the encoded path we
# assert against matches what the script itself computes via `pwd`.
proj_cwd="$(cd "$proj_cwd_raw" && pwd)"
encoded="$(print -r -- "$proj_cwd" | sed 's#/#-#g')"
sess_dir="$fake_home/.claude/projects/$encoded"

run_it() {
  ( export HOME="$fake_home"
    cd "$proj_cwd" || exit 1
    bash "$lib/resolve-transcript.sh" )
}

# --- no ~/.claude/projects dir at all ----------------------------------------
out="$(run_it)"
[[ -z "$out" ]] && ok "no ~/.claude/projects dir -> prints nothing" \
  || bad "expected empty, got: $out"

# --- projects dir exists, encoded subdir does not ----------------------------
mkdir -p "$fake_home/.claude/projects"
out="$(run_it)"
[[ -z "$out" ]] && ok "no matching encoded-cwd dir -> prints nothing" \
  || bad "expected empty, got: $out"

# --- encoded dir exists, no .jsonl files --------------------------------------
mkdir -p "$sess_dir"
: > "$sess_dir/notes.txt"
out="$(run_it)"
[[ -z "$out" ]] && ok "encoded dir with no .jsonl -> prints nothing" \
  || bad "expected empty, got: $out"

# --- one .jsonl file -----------------------------------------------------------
: > "$sess_dir/session-a.jsonl"
out="$(run_it)"
[[ "$out" == "$sess_dir/session-a.jsonl" ]] && ok "single .jsonl -> resolves it" \
  || bad "expected $sess_dir/session-a.jsonl, got: $out"

# --- newest of several .jsonl files wins --------------------------------------
: > "$sess_dir/session-b.jsonl"
touch -t 202001010000 "$sess_dir/session-a.jsonl" 2>/dev/null \
  || touch -mt 202001010000 "$sess_dir/session-a.jsonl"
touch -t 202601010000 "$sess_dir/session-b.jsonl" 2>/dev/null \
  || touch -mt 202601010000 "$sess_dir/session-b.jsonl"
out="$(run_it)"
[[ "$out" == "$sess_dir/session-b.jsonl" ]] && ok "picks newest-mtime .jsonl" \
  || bad "expected $sess_dir/session-b.jsonl, got: $out"

rm -rf "$fake_home" "$proj_cwd_raw"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
