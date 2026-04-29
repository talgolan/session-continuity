# Learnings — session-continuity

This is a graveyard of subtle, painful bugs we've hit while building
session-continuity. Each entry is a recipe for a future engineer (or
future Claude) to avoid re-discovering what was expensive to discover
the first time. Entries are grouped by layer, most-painful-first
within each group.

---

## Claude Code plugin mechanics

### 2. awk CHANGELOG range collapses on single-version files

**The trap.** In the release workflow, extracting one version's CHANGELOG section with `awk "/^## \[${version}\]/,/^## \[/"` looks right — "print from the version header to the next version header." It works fine on multi-version files, so it's easy to ship.

**Symptom.** The first v0.2.0 release fired the workflow, created the GitHub Release, but the release body was "No CHANGELOG section for 0.2.0." The extraction had produced exactly one line (the header) which `sed '$d'` then stripped. CI logs looked green.

**Fix.** Use a state-machine awk that skips the header, copies lines until the next `## [` heading, then exits. Portable across gawk and BSD awk:

```bash
awk -v ver="$version" '
  $0 ~ "^## \\[" ver "\\]" { in_section=1; next }
  in_section && /^## \[/   { exit }
  in_section                { print }
' CHANGELOG.md
```

The original awk range fails because the same pattern matches both the start and end of the range when only one versioned section exists — the range collapses to a single line (the header), which `sed '$d'` then deletes.

**Diagnostic signal.** If your release body says "No CHANGELOG section for X.Y.Z" but the CHANGELOG clearly has that section, suspect the extraction before the CHANGELOG. Test locally by running the exact awk command against the real file before tagging.

---

<!-- Add entries here as they surface -->

---

## Slash command skill authoring

### 4. Init-mode commits can leak `{{PLACEHOLDER}}` tokens when the user skips ahead

**The trap.** The primer command's init mode copies templates, fills in derivable fields, and "asks the user for the blanks." Reads fine. But the command prose doesn't say what Claude should do if the user *never answers* — pastes a `git commit` command or says "commit it" before filling in the blanks. Claude's default is to stage and proceed with the placeholders still present, so the committed file ends up containing literal `{{PACKAGE_1}}`, `{{ITEM_1_BODY}}`, etc.

**Symptom.** Clean-machine acceptance test for v0.4.0. `/session-continuity:primer` ran init mode cleanly, asked for the seven blanks, the user said `git commit -m "docs: init session continuity"` without answering. The commit landed (`a37b00c` in `/tmp/sc-accept`) with a primer full of `{{PLACEHOLDER}}` tokens — visible to anyone who later reads the file. No error, no warning, just a fresh user's first commit looking broken.

**Fix.** Tighten `commands/primer.md` Step 4/5 with an explicit fallback rule: *"For any `{{PLACEHOLDER}}` the user declines to fill in or hasn't answered, replace the token with `TBD` before staging. Never leave `{{...}}` syntax in a staged file."* The general lesson: any command that asks the user to supply values must define the fallback when the user skips — silence is a valid user response and the command needs to specify the resulting file state.

**Diagnostic signal.** After init mode runs to completion, `grep -n '{{' docs/SESSION_PRIMER.md docs/LEARNINGS.md` should return nothing. If it does, the init-mode prose missed a fallback path.

---

### 3. Checklist-style prose needs an explicit "enumerate, don't summarize" rule

**The trap.** A slash command that instructs Claude to "emit a ✓ / ⚠️ checklist of the staged files from `git diff --cached --name-only`" reads like a complete instruction. It isn't. Claude's default is to *summarize* tool output when embedding it in a response — so if `git diff --cached` returns two files, the checklist row might still list only the "most relevant" one.

**Symptom.** The `/session-continuity:end-session` smoke test had two staged files (primer + `src/foo.js`). The bash probe output clearly showed both. The checklist row said `✓ Staged: docs/SESSION_PRIMER.md` — one file missing. No error, no warning, just silently elided.

**Fix.** Add an explicit anti-summarization directive at the start of the section that emits the structured output:

> "**List every file enumerated by the git commands — do not summarize, filter, or pick a 'primary' one.** If `git diff --cached --name-only` returns three files, the row lists all three."

Applies generally: any time command prose tells Claude to produce an inventory from tool output, the prose must say "every item" explicitly. Claude's implicit move is to pick a representative and move on.

**Diagnostic signal.** If your structured output has rows that look "summary-like" when the underlying data has multiple items, the instruction needs tightening. Stage more than one file during smoke tests to flush these out.

---

<!-- Add entries here as they surface -->

---

## Hook scripting (SessionStart / PreToolUse)

### 1. PreToolUse hooks must emit JSON to reach Claude's context

**The trap.** `SessionStart` hooks inject plain stdout into Claude's context — that's documented, straightforward, and works on the first try. When writing a `PreToolUse` hook, it's natural to reach for the same pattern: print a `<system-reminder>` block to stdout, exit 0. Bash-level smoke tests show the reminder firing. Looks done.

**Symptom.** In a live Claude session, the hook runs (verified via debug logs) but Claude never sees the reminder. `git commit` proceeds silently without Claude surfacing the nudge at all. No error, no skipped-hook warning — the output just goes to `/dev/null` from Claude's perspective.

**Fix.** `PreToolUse` (unlike `SessionStart`) does NOT treat plain stdout as additional context. You must emit a JSON object with `hookSpecificOutput.additionalContext`, with exit code 0, and `permissionDecision: "allow"` to remain non-blocking:

```bash
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"⚠️ ..."}}
EOF
exit 0
```

Plain stdout from `PreToolUse` is written only to debug logs, never injected. Source: https://code.claude.com/docs/en/hooks.md (sections "stdout Context Injection" and "Decision Control with JSON Output").

**Diagnostic signal.** If a hook's bash smoke tests emit text correctly but Claude ignores it in a live session, the hook's event type probably has a different contract than `SessionStart`. Check the hooks.md matrix before assuming plain stdout works.

---

<!-- Add entries here as they surface -->

---

## Security incidents

<!-- Log security-adjacent events here: leaked credentials (names only,
NEVER values), access control mistakes. Never record actual secret values. -->

---

## Anti-patterns we were tempted by (and rejected)

<!-- This section is for "we thought X would work, we tried X, here is
why X is wrong." Each entry names the anti-pattern, explains the appeal,
and explains why it loses. -->

---

## Checklist for a fresh dev-env setup

1. `claude plugins install github:talgolan/session-continuity`
2. Open a scratch project and run `/session-continuity:primer` to verify init mode.
3. Make a small change and run `/session-continuity:end-session` to verify close-out.

---

*Last reviewed: 2026-04-28. Add new entries at the top of each section
as they surface. Rule of thumb: if a bug takes more than 15 minutes to
diagnose, it goes here.*

*Numbering note: new entries take the next available number (N+1) and
are placed at the top of their section. Old entries keep their numbers
so historical references ("see #7 above") stay valid even when the
visual order no longer matches numeric order.*
