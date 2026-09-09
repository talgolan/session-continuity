#!/usr/bin/env zsh
# Smoke runner for hooks/session-start.sh's backlog surfacing.
# Hermetic: scratch fixture repo per case, mocked GH_BIN, synthetic
# SessionStart payload on stdin. No live session, no live GitHub API
# (SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1 short-circuits version-check.sh).
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
hook="$repo/hooks/session-start.sh"
templates="$repo/skills/session-continuity/templates"

export SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

assert() {
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "EMPTY" ]]; then
    [[ -z "$act" ]] && ok "$desc" || bad "$desc (expected empty, got: $act)"
  else
    [[ "$act" == *"$exp"* ]] && ok "$desc" || bad "$desc (expected '*$exp*', got: $act)"
  fi
}

assert_not() {
  local desc="$1" forbidden="$2" act="$3"
  [[ "$act" != *"$forbidden"* ]] && ok "$desc" || bad "$desc (found forbidden '*$forbidden*')"
}

assert_xfail() {
  local desc="$1" exp="$2" act="$3" reason="$4"
  if [[ "$act" == *"$exp"* ]]; then
    ok "$desc (xfail expected to fail, but currently passes — reason no longer applies? $reason)"
  else
    ok "$desc — EXPECTED RED, not counted as failure: $reason (expected '*$exp*', got: $act)"
  fi
}

payload() { printf '{"cwd":"%s"}' "$1"; }

# Workspace-local temp: system /tmp denied for nested git config in sandbox.
# macOS mktemp -d ignores TMPDIR unless the template path is under the repo.
tmpdir_root="$repo/.superpowers/sdd/tmp"
mkdir -p "$tmpdir_root"
export TMPDIR="$tmpdir_root"
work="$(mktemp -d "$tmpdir_root/session-start-smoke.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mock="$work/fake-gh"
cat > "$mock" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${GH_MOCK_OUT:-}" && -f "${GH_MOCK_OUT}" ]]; then
  cat "${GH_MOCK_OUT}"
  exit 0
fi
exit 0
EOF
chmod +x "$mock"
export GH_BIN="$mock"

# Peer mocks so backlog cases exercise the peers-ok path (Task 5 hard-stop
# otherwise replaces the normal reminder when engrim/graphify are absent).
mock_engrim="$work/mock-engrim-ok"
cat > "$mock_engrim" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$mock_engrim"
export ENGRIM_BIN="$mock_engrim"

ensure_peers() {
  local d="$1"
  mkdir -p "$d/graphify-out"
  print -r -- '{"nodes":[]}' > "$d/graphify-out/graph.json"
}

# Nested git so probes don't walk up into this plugin repo (fixtures live under it).
init_repo() {
  local d="$1"
  git -C "$d" -c init.templateDir= init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "Test"
}

mk_gh_proj() {
  local d="$1"
  mkdir -p "$d/.session-continuity"
  init_repo "$d"
  git -C "$d" remote add origin "https://github.com/example/repo.git"
}

# --- Case set 1: github origin + two mocked backlog issues -> shortlist ---
d1="$work/case1"
mkdir -p "$d1"
mk_gh_proj "$d1"
ensure_peers "$d1"
cat > "$d1/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
touch "$d1/.session-continuity/LEARNINGS.md"
printf '#12\tFirst item, single line.\n#15\tSecond item header text\n' > "$work/two.tsv"
export GH_MOCK_OUT="$work/two.tsv"

out1="$(payload "$d1" | bash "$hook")"
assert "1a reports a count of 2" $'- Backlog: 2\n' "$out1"
assert "1b lists item 1" '1. #12 First item, single line.' "$out1"
assert "1c lists item 2 as 2. #15" '2. #15 Second item header text' "$out1"
assert "1f includes numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out1"
assert_not "1g no migration nudge on a GitHub-backed project" "run /session-continuity:primer now" "$out1"

# --- Case set 2: no .session-continuity primer → missing-primer nudge ------
d2="$work/case2"
mkdir -p "$d2/docs"
cat > "$d2/docs/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

1. Only item on the legacy path.

## Workflow conventions
PRIMER
touch "$d2/docs/LEARNINGS.md"

out2="$(payload "$d2" | bash "$hook")"
assert "2a missing .session-continuity primer nudges init" \
  "No .session-continuity/SESSION_PRIMER.md. Run /session-continuity:primer to init. Required peers: engrim + graphify-out/graph.json." \
  "$out2"

# --- Case set 3: github origin, empty issue list -> clean 0, no shortlist --
d3="$work/case3"
mkdir -p "$d3"
mk_gh_proj "$d3"
ensure_peers "$d3"
cat > "$d3/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
touch "$d3/.session-continuity/LEARNINGS.md"
: > "$work/empty.tsv"
export GH_MOCK_OUT="$work/empty.tsv"

out3="$(payload "$d3" | bash "$hook")"
assert "3a reports a clean zero, not a malformed value" $'- Backlog: 0\n' "$out3"
assert_not "3b no Backlog: header block" $'\nBacklog:\n' "$out3"
assert_not "3c no numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out3"
assert_not "3d no migration nudge" "run /session-continuity:primer now" "$out3"

# --- Case set 4: no github origin -> count ?, no shortlist, no nudge -------
d4="$work/case4"
mkdir -p "$d4/.session-continuity"
init_repo "$d4"
ensure_peers "$d4"
cat > "$d4/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
touch "$d4/.session-continuity/LEARNINGS.md"

out4="$(payload "$d4" | bash "$hook")"
assert "4a reports ? when GitHub is unavailable" $'- Backlog: ?\n' "$out4"
assert_not "4b no Backlog: header block when GitHub unavailable" $'\nBacklog:\n' "$out4"
assert_not "4c no migration nudge (nothing to migrate)" "run /session-continuity:primer now" "$out4"

# --- Case set 5: old-format inline ## Outstanding items heading ------------
d5="$work/case5"
mkdir -p "$d5/.session-continuity"
init_repo "$d5"
ensure_peers "$d5"
cat > "$d5/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

1. Old-format item that must never be echoed.
2. Another old-format item.

## Workflow conventions
PRIMER
touch "$d5/.session-continuity/LEARNINGS.md"

out5="$(payload "$d5" | bash "$hook")"
assert "5a migration nudge fires" "run /session-continuity:primer now" "$out5"
assert_not "5b old item text never rendered" "Old-format item that must never be echoed" "$out5"
assert_not "5c no numbered-list-echo instruction (that's the current-format path)" 'Present these to the user as a numbered list' "$out5"

# --- Case set 6: empty inline heading still nudges -------------------------
d6="$work/case6"
mkdir -p "$d6/.session-continuity"
init_repo "$d6"
ensure_peers "$d6"
cat > "$d6/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

## Workflow conventions
PRIMER
touch "$d6/.session-continuity/LEARNINGS.md"

out6="$(payload "$d6" | bash "$hook")"
assert "6a migration nudge fires even for an empty inline heading" "run /session-continuity:primer now" "$out6"

# --- Case set 7: leftover OUTSTANDING_ITEMS.md presence-only trigger -------
d7="$work/case7"
mkdir -p "$d7/.session-continuity"
init_repo "$d7"
ensure_peers "$d7"
cat > "$d7/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cat > "$d7/.session-continuity/OUTSTANDING_ITEMS.md" <<'ITEMS'
# Outstanding Items (legacy filename)

### 1. Item that must never be echoed — content is irrelevant to this path.
ITEMS
touch "$d7/.session-continuity/LEARNINGS.md"

out7="$(payload "$d7" | bash "$hook")"
assert "7a migration nudge fires on legacy filename presence alone" "run /session-continuity:primer now" "$out7"
assert_not "7b legacy file's content is never echoed (presence-only trigger)" "Item that must never be echoed" "$out7"
assert_not "7c no numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out7"

# --- Case set 8: fresh LEARNINGS template still xfail on exemplar headings --
d8="$work/case8"
mkdir -p "$d8/.session-continuity"
init_repo "$d8"
ensure_peers "$d8"
cat > "$d8/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
cp "$templates/LEARNINGS.md" "$d8/.session-continuity/LEARNINGS.md"

out8="$(payload "$d8" | bash "$hook")"
assert "8a no github origin reports ?" $'- Backlog: ?\n' "$out8"
assert_not "8b no shortlist block" $'\nBacklog:\n' "$out8"
assert_not "8c no numbered-list-echo instruction" 'Present these to the user as a numbered list' "$out8"
assert_not "8d no migration nudge" "run /session-continuity:primer now" "$out8"
assert_xfail "8e fresh-install LEARNINGS.md template counts as zero real entries" $'- Learnings: 0\n' "$out8" \
  "EXPECTED RED pending Task 4 of meta/superpowers/plans/2026-09-02-fresh-install-count-defects.md: templates/LEARNINGS.md's '### 1. {{ENTRY_TITLE}}' and '### 2. {{ENTRY_TITLE}}' exemplar headings are NOT wrapped in an HTML comment, so count-entries.sh correctly counts them as 2 live headings."

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
