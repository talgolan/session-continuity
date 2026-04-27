---
description: Append a new entry to docs/LEARNINGS.md interactively. Takes next N+1 number, inserts at top of chosen section.
---

# /session-continuity:learning $ARGUMENTS

You are responding to the `/session-continuity:learning` slash command.

**Your job: help the user append a properly-formatted entry to `docs/LEARNINGS.md`.**

If `$ARGUMENTS` is non-empty, use it as the pre-filled title.

## Step 1 — Preflight

If `docs/LEARNINGS.md` does not exist, tell the user:

> "No `docs/LEARNINGS.md` found. Run `/session-continuity:primer` first to initialize session-continuity in this project."

Exit.

## Step 2 — Gather the recipe

Prompt the user for each field. Show examples inline.

1. **Title** (pre-filled with `$ARGUMENTS` if provided): short noun phrase. E.g. "resource_dir() returns `_up_/` paths".
2. **The trap** (what seemed reasonable but was wrong): 1-3 sentences.
3. **Symptom** (what was observed, including misleading errors): 1-3 sentences.
4. **Fix** (what actually works): 1-3 sentences + optional code block.
5. **Diagnostic signal** (optional — how to recognize this next time): one sentence. Skip if user has nothing.

## Step 3 — Choose section

Read `docs/LEARNINGS.md`. List existing section headings (lines starting with `## ` but not `### `, excluding `## Security incidents`, `## Anti-patterns we were tempted by (and rejected)`, `## Checklist for a fresh dev-env setup` which are structural).

Ask the user:

> "Which section does this belong to?
> 1. <existing section 1>
> 2. <existing section 2>
> …
> N. Security incidents
> N+1. Anti-patterns we were tempted by (and rejected)
> N+2. New section (you'll name it)"

If they pick "new section", prompt for the heading and insert it above the existing sections (not above Security/Anti-patterns/Checklist, which stay at the bottom).

## Step 4 — Compute next number

Scan `docs/LEARNINGS.md` for all `### N.` headings (regex: `^### (\d+)\.`). Take the max, add 1. New entry gets that number.

## Step 5 — Insert at top of chosen section

Compose the entry:

```markdown
### <N>. <Title>

**The trap.** <trap text>

**Symptom.** <symptom text>

**Fix.** <fix text>

[optional code block]

**Diagnostic signal** *(optional)*. <diagnostic text if supplied>

---
```

Insert immediately after the section heading (and any HTML comments that follow it). Keep a blank line between the heading and the new entry.

## Step 6 — Stage

Run: `git add docs/LEARNINGS.md`

Tell the user: "Learning #<N> appended and staged. Commit when ready — typically alongside the fix or in its own commit if the fix already landed."

**Do not commit automatically.**

## Notes

- **Numbering is stable.** Never renumber existing entries. Old entries keep their numbers even when new entries arrive at the top.
- **Never invent details.** If the user says "I don't know" for a field, leave it blank or omit it (except trap/symptom/fix, which are required — push back gently if the user skips them).
- **Redact secrets.** Never put actual credential values in the file. Use `<redacted>` or a description.
