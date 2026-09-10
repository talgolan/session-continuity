#!/usr/bin/env zsh
# Scratch-project primer init + split smoke (#37).
# Hermetic: throwaway git repos outside the plugin's own .session-continuity/.
# Covers the deferred Testing items from the v0.13 split spec + init-derive
# enrichment against a real fresh repo (detect STEPS=init / STEPS=split,
# template copy, primer-init-derive substitution).
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"
detect="$repo/hooks/lib/primer-detect.sh"
derive="$repo/hooks/lib/primer-init-derive.sh"
templates="$repo/skills/session-continuity/templates"
validate="$repo/hooks/lib/primer-validate.sh"

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

steps_of() {
  bash "$detect" "$1" 2>/dev/null | awk -F= '/^STEPS=/{print $2; exit}'
}

mk_git() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name Test
  git -C "$d" remote add origin https://github.com/example/scratch-fixture.git
  print -r -- '{"name":"scratch-fixture","version":"0.0.1"}' > "$d/package.json"
  : > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" commit -qm init
}

# --- 1: fresh project → STEPS=init -----------------------------------------
d="$work/fresh"
mk_git "$d"
mkdir -p "$d/.session-continuity"
[[ "$(steps_of "$d")" == "init" ]] \
  && ok "1: fresh (no primer) -> STEPS=init" \
  || bad "1: got '$(steps_of "$d")'"

# --- 2: init path — copy templates + derive, no leftover {{ for derived keys
cp "$templates/SESSION_PRIMER.md" "$d/.session-continuity/"
cp "$templates/PROJECT_CONTEXT.md" "$d/.session-continuity/"
cp "$templates/ROADMAP.md" "$d/.session-continuity/"
cp "$templates/LEARNINGS.md" "$d/.session-continuity/"
# Fake test command output as primer.md would capture before calling derive
export TEST_CMD='echo "3 pass / 0 fail"'
export TEST_OUTPUT='3 pass / 0 fail'
deriv="$(bash "$derive" "$d" 2>&1)"; drc=$?
[[ "$drc" -eq 0 && "$deriv" == *"PROJECT_NAME="* ]] \
  && ok "2a: primer-init-derive exits 0 with PROJECT_NAME" \
  || bad "2a: derive rc=$drc out='$deriv'"
# Substitute every KEY=value from derive into the four files (same job Init
# mode's model is told to do for the auto-derived set).
while IFS= read -r line; do
  [[ "$line" == *=* ]] || continue
  key="${line%%=*}"
  val="${line#*=}"
  # Escape sed replacement metacharacters lightly
  esc="$(printf '%s' "$val" | sed -e 's/[&|]/\\&/g')"
  for f in SESSION_PRIMER.md PROJECT_CONTEXT.md ROADMAP.md LEARNINGS.md; do
    sed -i '' -e "s|{{${key}}}|${esc}|g" "$d/.session-continuity/$f" 2>/dev/null \
      || sed -i -e "s|{{${key}}}|${esc}|g" "$d/.session-continuity/$f"
  done
done <<<"$deriv"
# Fill Mid-flight / Confirm so thin primer validates (Init still asks human)
cat > "$d/.session-continuity/SESSION_PRIMER.md" <<EOF
# Session Primer — scratch-fixture

## Boot order
1. \`.session-continuity/PROJECT_CONTEXT.md\`

## Mid-flight
- scratch init smoke

## Confirm
\`\`\`bash
true
\`\`\`

## Peers
- engrim: required
- graphify: required
EOF
bash "$validate" "$d/.session-continuity/SESSION_PRIMER.md" >/dev/null 2>&1 \
  && ok "2b: post-init thin primer validates" \
  || bad "2b: primer-validate failed"
print -r -- "$(cat "$d/.session-continuity/PROJECT_CONTEXT.md")" | grep -q '3 pass' \
  && ok "2c: TEST_COMMAND_SUMMARY derived into PROJECT_CONTEXT" \
  || bad "2c: no derived test count in PROJECT_CONTEXT"
# Derived keys must not remain as placeholders in PROJECT_CONTEXT
leftover="$(grep -oE '\{\{(PROJECT_NAME|WORKING_DIRECTORY_ABSOLUTE_PATH|TEST_COMMAND_SUMMARY)\}\}' \
  "$d/.session-continuity/PROJECT_CONTEXT.md" || true)"
[[ -z "$leftover" ]] \
  && ok "2d: no leftover derived placeholders in PROJECT_CONTEXT" \
  || bad "2d: leftover: $leftover"

# --- 3: unsplit primer (volatile+stable in one file) → STEPS=split ---------
d="$work/unsplit"
mk_git "$d"
mkdir -p "$d/.session-continuity"
# Pre-v0.13 shape: one primer holding both volatile and stable material,
# no PROJECT_CONTEXT.md yet.
cat > "$d/.session-continuity/SESSION_PRIMER.md" <<'EOF'
# Session Primer — unsplit-fixture

## Current state
Working on the split.

## Outstanding
- [ ] something

## Project context
Bun is the runtime.
Layout: hooks/, commands/, skills/.

## Test expectations
`bun test` — 0 pass

## Recent commits
```
abc1234 demo
```

## Confirm
```bash
true
```
EOF
: > "$d/.session-continuity/LEARNINGS.md"
git -C "$d" add -A
git -C "$d" commit -qm 'unsplit primer'
[[ "$(steps_of "$d")" == "split" ]] \
  && ok "3: unsplit primer, no PROJECT_CONTEXT -> STEPS=split" \
  || bad "3: got '$(steps_of "$d")'"

# --- 4: after mechanical split (PROJECT_CONTEXT appears) detect clears ----
# Simulate Split mode's durable outcome: stable material lives in
# PROJECT_CONTEXT; primer is thin hard-template.
cat > "$d/.session-continuity/PROJECT_CONTEXT.md" <<'EOF'
# Project Context — unsplit-fixture

## Ground rules
1. Don't assume.

## Test expectations — these must stay green
`bun test` — 0 pass
EOF
cat > "$d/.session-continuity/SESSION_PRIMER.md" <<'EOF'
# Session Primer — unsplit-fixture

## Boot order
1. `.session-continuity/PROJECT_CONTEXT.md`

## Mid-flight
- post-split

## Confirm
```bash
true
```

## Peers
- engrim: required
- graphify: required
EOF
: > "$d/.session-continuity/ROADMAP.md"
git -C "$d" add -A
git -C "$d" commit -qm 'split complete'
steps="$(steps_of "$d")"
# split should be gone; may be empty or refresh depending on freshness
[[ "$steps" != *split* ]] \
  && ok "4: after split, STEPS no longer contains split (got '$steps')" \
  || bad "4: still wants split: '$steps'"
bash "$validate" "$d/.session-continuity/SESSION_PRIMER.md" >/dev/null 2>&1 \
  && ok "4b: post-split thin primer validates" \
  || bad "4b: validate failed"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
