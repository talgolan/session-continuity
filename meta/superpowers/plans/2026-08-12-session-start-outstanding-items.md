# SessionStart Outstanding-Items Surfacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `hooks/session-start.sh` lists the primer's outstanding items (first line each) in its `<system-reminder>` and instructs Claude to ask the user which one to tackle this session.

**Architecture:** One new awk pass in the existing bash script extracts the first line of each top-level numbered item under `## Outstanding items`, builds a pre-formatted text block (empty string if no items), and splices it into the existing heredoc immediately before the closing `</system-reminder>` tag — no items means no block, no extra blank line, identical output to today.

**Tech Stack:** bash (`set -euo pipefail`), awk, zsh (test runner, matching existing `meta/superpowers/validation/*-smoke.zsh` convention), shellcheck.

## Global Constraints

- No new files besides the test runner — same plain-stdout contract, no JSON, no `hooks.json` change (per spec `## Implementation notes`).
- First line only per item — no multi-line/sub-bullet capture (per spec `## Decision`).
- Silent omission when zero outstanding items — no "Outstanding items: 0" noise, and no stray blank line in that case (per spec `## Decision` + review finding rolled into `## Testing`).
- Both `.session-continuity/` and legacy `docs/` primer paths must get the feature; Task 1's smoke test covers both paths (per spec `## Implementation notes` + `## Testing`).
- No trimming/reformatting of items whose first line ends mid-sentence (e.g. trailing colon) — accepted tradeoff, do not add heuristics (per spec `## Decision`).
- Spec: `meta/superpowers/specs/2026-08-12-session-start-outstanding-items-design.md`.

---

### Task 1: Extract and surface outstanding items in `hooks/session-start.sh`

**Files:**
- Modify: `hooks/session-start.sh` (insert new awk pass + `outstanding_block` construction after the existing status computations at L86, splice into the heredoc at L91-100)
- Create: `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh`
- Modify: `.claude-plugin/plugin.json`, `CHANGELOG.md` (version bump — see Step 6)

**Interfaces:**
- Consumes: nothing new from other tasks — this is the only task.
- Produces: nothing consumed by later tasks — this is the only task.

- [ ] **Step 1: Write the failing smoke test**

Create `meta/superpowers/validation/2026-08-12-session-start-smoke.zsh`:

```zsh
#!/usr/bin/env zsh
# Smoke runner for hooks/session-start.sh's outstanding-items surfacing.
# Hermetic: builds a scratch fixture repo per case, feeds a synthetic
# SessionStart payload on stdin, asserts on stdout. No live session, no
# network (SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1 short-circuits
# version-check.sh's GitHub call).
set -uo pipefail

here="${0:A:h}"
repo="${here:h:h:h}"   # validation -> superpowers -> meta -> repo root
hook="$repo/hooks/session-start.sh"

export SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1

pass=0; fail=0
ok()  { print -P "%F{green}✓%f $1"; (( pass++ )); return 0; }
bad() { print -P "%F{red}✗%f $1"; (( fail++ )); return 0; }

# assert <desc> <expected-substr-or-EMPTY> <actual>
assert() {
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "EMPTY" ]]; then
    [[ -z "$act" ]] && ok "$desc" || bad "$desc (expected empty, got: $act)"
  else
    [[ "$act" == *"$exp"* ]] && ok "$desc" || bad "$desc (expected '*$exp*', got: $act)"
  fi
}

# assert_not <desc> <forbidden-substr> <actual>
assert_not() {
  local desc="$1" forbidden="$2" act="$3"
  [[ "$act" != *"$forbidden"* ]] && ok "$desc" || bad "$desc (found forbidden '*$forbidden*')"
}

# payload <cwd> -> a SessionStart JSON payload naming that cwd
payload() { printf '{"cwd":"%s"}' "$1"; }

# --- Case set 1: canonical .session-continuity/ path, multi-line item ---
d1="$(mktemp -d)"
mkdir -p "$d1/.session-continuity"
cat > "$d1/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

1. First item, single line.
2. Second item header text: (rejected — details below)
   - sub-bullet A
   - sub-bullet B
3. Third item, single line.

## Workflow conventions
PRIMER
touch "$d1/.session-continuity/LEARNINGS.md"

out1="$(payload "$d1" | bash "$hook")"
assert "1a lists item 1 first line" '1. First item, single line.' "$out1"
assert "1b lists item 2 first line only" '2. Second item header text: (rejected — details below)' "$out1"
assert_not "1c drops item 2 sub-bullets" 'sub-bullet A' "$out1"
assert "1d lists item 3 first line" '3. Third item, single line.' "$out1"
assert "1e includes ask-the-user instruction" 'Ask the user which of these' "$out1"
rm -rf "$d1"

# --- Case set 2: legacy docs/ path gets the same treatment ---
d2="$(mktemp -d)"
mkdir -p "$d2/docs"
cat > "$d2/docs/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

1. Only item on the legacy path.

## Workflow conventions
PRIMER
touch "$d2/docs/LEARNINGS.md"

out2="$(payload "$d2" | bash "$hook")"
assert "2a legacy docs/ path also lists items" '1. Only item on the legacy path.' "$out2"
assert "2b legacy docs/ path also gets instruction" 'Ask the user which of these' "$out2"
rm -rf "$d2"

# --- Case set 3: empty Outstanding items section -> no block, no noise ---
d3="$(mktemp -d)"
mkdir -p "$d3/.session-continuity"
cat > "$d3/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Outstanding items

## Workflow conventions
PRIMER
touch "$d3/.session-continuity/LEARNINGS.md"

out3="$(payload "$d3" | bash "$hook")"
assert_not "3a no Outstanding items: header block" 'Outstanding items:' "$out3"
assert_not "3b no ask-the-user instruction" 'Ask the user which of these' "$out3"
assert "3c closing tag immediately follows Learnings line (no stray blank line)" $'- Learnings: 0\n</system-reminder>' "$out3"
rm -rf "$d3"

# --- Case set 4: missing Outstanding items section entirely -> no block ---
d4="$(mktemp -d)"
mkdir -p "$d4/.session-continuity"
cat > "$d4/.session-continuity/SESSION_PRIMER.md" <<'PRIMER'
# Session Primer

## Workflow conventions
PRIMER
touch "$d4/.session-continuity/LEARNINGS.md"

out4="$(payload "$d4" | bash "$hook")"
assert_not "4a no Outstanding items: header block when section absent" 'Outstanding items:' "$out4"
rm -rf "$d4"

print ""
print -P "Result: %F{green}$pass passed%f, %F{red}$fail failed%f"
(( fail == 0 ))
```

Make it executable:

```bash
chmod +x meta/superpowers/validation/2026-08-12-session-start-smoke.zsh
```

- [ ] **Step 2: Run the test to check it fails as expected**

Run: `zsh meta/superpowers/validation/2026-08-12-session-start-smoke.zsh`
Expected: cases 1a, 1b, 1d, 1e, 2a, 2b FAIL (current script has no `Outstanding items:` section or instruction line at all). Cases 1c, 3a, 3b, 3c, 4a currently pass by accident (nothing to find/nothing to break yet) — Step 4 re-checks all of them together once the implementation lands.

- [ ] **Step 3: Implement the awk pass and heredoc splice**

Open `hooks/session-start.sh`. Locate the existing status computation block (currently lines 77-86, ending at `status_learnings=...`) and insert a new block immediately after it, before the `# Inject the reminder...` comment:

```bash
# Outstanding items: extract the first line only of each top-level numbered
# item (sub-bullets and continuation lines are intentionally dropped — see
# spec's Decision section for why no truncation heuristics are added).
# Empty when the section is missing or has no numbered items, which keeps
# the reminder identical to today's output in that case.
outstanding_items="$(awk '
  /^## Outstanding items/ { inside=1; next }
  inside && /^## / { exit }
  inside && /^[0-9]+\. / { print }
' "$cwd/$primer_path" 2>/dev/null || true)"

if [ -n "$outstanding_items" ]; then
  outstanding_block=$'\nOutstanding items:\n'"$outstanding_items"$'\n\nAsk the user which of these (if any) they want to tackle this session.\n'
else
  outstanding_block=""
fi
```

Then change the existing heredoc (currently ending):

```bash
cat <<EOF
<system-reminder>
This project has $primer_path. Read it before any work — it's the fastest path to context. Also check $learnings_path if anything surprises you.

Primer status (auto):
- HEAD: $status_sha
- Last primer change: $status_mtime
- Outstanding items: $status_outstanding
- Learnings: $status_learnings
</system-reminder>
EOF
```

to:

```bash
cat <<EOF
<system-reminder>
This project has $primer_path. Read it before any work — it's the fastest path to context. Also check $learnings_path if anything surprises you.

Primer status (auto):
- HEAD: $status_sha
- Last primer change: $status_mtime
- Outstanding items: $status_outstanding
- Learnings: $status_learnings
${outstanding_block}</system-reminder>
EOF
```

(Note: `${outstanding_block}` sits directly adjacent to `</system-reminder>` in the template, with no line break between them. When `outstanding_block` is empty this collapses to exactly today's output. When non-empty, the block's own leading/trailing `\n` supply the blank-line spacing and the newline before the closing tag.)

- [ ] **Step 4: Run the test and confirm all cases pass**

Run: `zsh meta/superpowers/validation/2026-08-12-session-start-smoke.zsh`
Expected: `Result: 12 passed, 0 failed` (all of 1a-1e, 2a-2b, 3a-3c, 4a).

- [ ] **Step 5: shellcheck**

Run: `shellcheck hooks/session-start.sh`
Expected: no warnings. If shellcheck flags the `$'...'` ANSI-C quoting or the `${outstanding_block}` splice, fix the reported line directly — do not add a `# shellcheck disable` without first trying a straightforward fix.

- [ ] **Step 6: Bump version and update the primer**

Every prior hook-script change (v0.9.0 through v0.12.2) bumped `plugin.json` + added a `CHANGELOG.md` entry, including behavior-only tweaks like v0.12.1's smoke-gate scoping fix — no ambiguity here, this change follows the same precedent:

1. In `.claude-plugin/plugin.json`, bump `"version"` from `"0.12.2"` to `"0.12.3"`.
2. In `CHANGELOG.md`, add a `[0.12.3]` entry describing the SessionStart outstanding-items surfacing (mirror the format of the existing `[0.12.2]`/`[0.12.1]` entries).
3. In `.session-continuity/SESSION_PRIMER.md`'s `## Outstanding items` section, remove item #5 ("SessionStart should restate outstanding items and ask which to work on") — it's done, and this repo's "Primer maintenance" convention requires removing finished items in the same commit as the change that finished them.
4. Regenerate the `git log --oneline -5` block in the primer's `## Current state` section, and add a new `## Current state` bullet describing what shipped (mirror the style of the existing v0.12.x bullets), naming the `0.12.3` version bump.

- [ ] **Step 7: Commit**

```bash
git add hooks/session-start.sh meta/superpowers/validation/2026-08-12-session-start-smoke.zsh .claude-plugin/plugin.json CHANGELOG.md .session-continuity/SESSION_PRIMER.md
git commit -m "feat(hooks): surface outstanding items in SessionStart reminder (v0.12.3)"
```
