---
description: Append a new entry to .session-continuity/LEARNINGS.md interactively. Takes next N+1 number, inserts at top of chosen section.
---

# /session-continuity:learning $ARGUMENTS

You are responding to the `/session-continuity:learning` slash command.

**Your job: help the user append a properly-formatted entry to `.session-continuity/LEARNINGS.md`.**

If `$ARGUMENTS` is non-empty, use it as the pre-filled title.

## Step 1 — Preflight

Check both the canonical path and the legacy path:

- If `.session-continuity/LEARNINGS.md` exists, use that path for the rest of this command.
- Else if `docs/LEARNINGS.md` exists (pre-v0.5.0 layout), tell the user:

  > "Found `docs/LEARNINGS.md` at the pre-v0.5.0 location. Run `/session-continuity:primer` first — it will migrate the files to `.session-continuity/`. Then re-run `/session-continuity:learning`."

  Exit.
- Else tell the user:

  > "No `.session-continuity/LEARNINGS.md` (or legacy `docs/LEARNINGS.md`) found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

  Exit.

## Step 2 — Gather the recipe

Prompt the user for each field. Show examples inline.

1. **Title** (pre-filled with `$ARGUMENTS` if provided): short noun phrase. E.g. "resource_dir() returns `_up_/` paths".
2. **The trap** (what seemed reasonable but was wrong): 1-3 sentences.
3. **Symptom** (what was observed, including misleading errors): 1-3 sentences.
4. **Fix** (what actually works): 1-3 sentences + optional code block.
5. **Diagnostic signal** (optional — how to recognize this next time): one sentence. Skip if user has nothing.
6. **Trigger** (optional — how this entry resurfaces *before* the action): a tool + regex that the `learnings-surface` hook matches against the imminent command or file. Form: `<tool> /<regex>/` where `<tool>` is `Bash`, `Write`, `Edit`, or `*`. E.g. `Bash /smoke|run\.zsh/` to resurface a smoke-runner trap before a smoke run. Skip if no mechanical trigger fits.

## Step 3 — Choose section

Read `.session-continuity/LEARNINGS.md`. List existing section headings (lines starting with `## ` but not `### `, excluding `## Security incidents`, `## Anti-patterns we were tempted by (and rejected)`, `## Checklist for a fresh dev-env setup` which are structural).

Ask the user:

> "Which section does this belong to?
> 1. <existing section 1>
> 2. <existing section 2>
> …
> N. Security incidents
> N+1. Anti-patterns we were tempted by (and rejected)
> N+2. New section (you'll name it)"

If they pick "new section", prompt for the heading and insert it above the existing sections (not above Security/Anti-patterns/Checklist, which stay at the bottom).

## Step 4 — Compute next number (with uniqueness guard)

Scan `.session-continuity/LEARNINGS.md` for **every** `### N.` heading (regex: `^### (\d+)\.`). Two operations:

1. **Detect duplicates first.** Count occurrences of each number. If any number appears more than once, refuse to write and report:

   > "LEARNINGS.md has duplicate entry numbers: #X (line A, line B), #Y (line C, line D). Fix the file before appending — pick which entry keeps the number and renumber the other (or merge them). Re-run `/session-continuity:learning` after."

   Exit. Do not append on top of a corrupt file.

2. **Compute next number across all entries.** Take the **true maximum** of the parsed numbers (not "next after the most recent" — that fails when an old entry was edited last). New entry gets `max + 1`.

After computing, validate: the chosen number must not already appear in the file. If it does (race condition with manual edit during this command), bump again and re-validate.

## Step 5 — Insert at top of chosen section

Compose the entry:

```markdown
### <N>. <Title>
Trigger: <tool> /<regex>/      ← include ONLY if the user supplied a trigger; omit the whole line otherwise

**The trap.** <trap text>

**Symptom.** <symptom text>

**Fix.** <fix text>

[optional code block]

**Diagnostic signal** *(optional)*. <diagnostic text if supplied>

---
```

The `Trigger:` line, when present, must sit on the line directly below the `### N.` heading (no blank line between) so the `learnings-surface` hook's parser associates it with the entry.

Insert immediately after the section heading (and any HTML comments that follow it). Keep a blank line between the heading and the new entry.

## Step 6 — Bump the footer

If the file has a footer line of the form `*Last reviewed: <date>...` or `*Last entry: <date> (#<N>)...`, update it in place:

- Replace with `*Last entry: <today's-date> (#<N>). Add new entries at the top of each section`
- Today's date: ISO format (`YYYY-MM-DD`) — derive from the system clock, not from session context.
- `<N>` is the number assigned in Step 4.

The rename from "Last reviewed" to "Last entry" reflects what the field actually tracks (the timestamp of the last *change*, not a manual review pass). If the footer doesn't exist, skip — don't synthesize one.

## Step 7 — Stage

Run: `git add .session-continuity/LEARNINGS.md`

Tell the user: "Learning #<N> appended and staged. Commit when ready — typically alongside the fix or in its own commit if the fix already landed."

**Do not commit automatically.**

## Notes

- **Numbering is stable.** Never renumber existing entries. Old entries keep their numbers even when new entries arrive at the top.
- **Never invent details.** If the user says "I don't know" for a field, leave it blank or omit it (except trap/symptom/fix, which are required — push back gently if the user skips them).
- **Redact secrets.** Never put actual credential values in the file. Use `<redacted>` or a description.
