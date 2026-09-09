---
description: Diagnose whether session-continuity is actually wired up in this project — hooks registered, four in-repo files present and not stale, GitHub backlog reachable, plugin root resolves and isn't a stale cache, gate scripts executable. Zero args, read-only.
---

# /session-continuity:doctor

You are responding to the `/session-continuity:doctor` slash command.

**Your job: answer "is this actually working?" directly, instead of the user finding out by hitting a gate denial cold or discovering a mechanism silently never fired.** This command is read-only — it never edits, stages, or commits anything. Every row either reports a fact or, if something's broken, prints the exact command to fix it; the user runs that themselves.

## Step 1 — Gather

Run everything in **one Bash call**, timed. Gate each new helper through `require_script` at `CONTRACT_VERSION=1` before relying on its output (same pattern as `primer-status.sh` in `/session-continuity:primer`):

```bash
_PERF_START=$(date +%s.%N 2>/dev/null || echo "$SECONDS")

echo "--- plugin root ---"
echo "RESOLVED_ROOT=${CLAUDE_PLUGIN_ROOT:-}"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then
  echo "ROOT_EXISTS=1"
  [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] && grep -m1 '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
  [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json" ] && echo "HOOKS_JSON_EXISTS=1" || echo "HOOKS_JSON_EXISTS=0"
  CACHE_PARENT="$(dirname "${CLAUDE_PLUGIN_ROOT}")"
  [ -d "$CACHE_PARENT" ] && ls "$CACHE_PARENT" 2>/dev/null
  echo "--- gate script exec bits ---"
  if [ -d "${CLAUDE_PLUGIN_ROOT}/hooks" ]; then
    for s in session-start.sh pre-commit-check.sh learnings-surface.sh smoke-gate.sh proven-gate.sh occurrence-gate.sh evidence-gate.sh flaky-gate.sh backend-parity-gate.sh version-check.sh; do
      p="${CLAUDE_PLUGIN_ROOT}/hooks/$s"
      if [ -f "$p" ]; then
        [ -x "$p" ] && echo "$s=EXEC" || echo "$s=NOEXEC:$p"
      fi
    done
  fi
else
  echo "ROOT_EXISTS=0"
fi

echo "--- vendored-mode check (only matters if ROOT_EXISTS=0 above) ---"
[ -f .claude/settings.json ] && cat .claude/settings.json || echo "NO_PROJECT_SETTINGS"

echo "--- .session-continuity/ files ---"
for f in SESSION_PRIMER.md ROADMAP.md PROJECT_CONTEXT.md LEARNINGS.md; do
  [ -f ".session-continuity/$f" ] && echo "$f=EXISTS" || echo "$f=MISSING"
done
[ -f .session-continuity/BACKLOG.md ] && echo "BACKLOG.md=FOSSIL" || echo "BACKLOG.md=ABSENT"

echo "--- github backlog ---"
command -v gh >/dev/null && echo "GH=PRESENT" || echo "GH=MISSING"
gh auth status >/dev/null 2>&1 && echo "GH_AUTH=OK" || echo "GH_AUTH=FAIL"
git remote get-url origin 2>/dev/null || echo "NO_ORIGIN"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-issues.sh" ]; then
  echo -n "BACKLOG_COUNT="
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/backlog-issues.sh" --count .
fi

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  # shellcheck disable=SC1091
  source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/require-script.sh"
fi

echo "--- primer validate ---"
if [ -f .session-continuity/SESSION_PRIMER.md ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" 1; then
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-validate.sh" .session-continuity/SESSION_PRIMER.md \
      && echo "PRIMER_VALIDATE=ok" || echo "PRIMER_VALIDATE=fail"
  else
    echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
    echo "PRIMER_VALIDATE=fail"
  fi
fi

echo "--- peer probes ---"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/peer-probes.sh" 1; then
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/peer-probes.sh" .
  else
    echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
    echo "ENGRIM=?"
    echo "GRAPHIFY=?"
  fi
fi

echo "--- primer freshness ---"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  if require_script "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-freshness.sh" 1; then
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/primer-freshness.sh" .
  else
    echo "⚠️ $SC_REQUIRE_SCRIPT_MSG"
    echo "STALE=?"
  fi
fi

_PERF_END=$(date +%s.%N 2>/dev/null || echo "$SECONDS")
_PERF_DURATION=$(awk -v a="$_PERF_START" -v b="$_PERF_END" 'BEGIN{printf "%.3f", b-a}' 2>/dev/null || echo "$(( _PERF_END - _PERF_START ))")
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/perf-log.sh" record --source=command --name=doctor --step=step-1-gather --duration="$_PERF_DURATION"
fi
```

## Step 2 — Interpret and report

Work through the six rows below using the output above. Never invent a result for something the output above didn't actually show — if a probe was skipped (e.g. no cache-parent directory), report `?` for that row rather than guessing.

1. **Install mode.** `ROOT_EXISTS=1` → **plugin mode**: report the version parsed from `plugin.json` and the resolved path. `ROOT_EXISTS=0` → **vendored mode**: note that `CLAUDE_PLUGIN_ROOT` never resolved, which is expected for a manually-vendored install — proceed to row 2's vendored branch.

2. **Hooks registered.**
   - Plugin mode: ✓ if `HOOKS_JSON_EXISTS=1` (Claude Code auto-wires this when the plugin is enabled — this is a sanity check that the install isn't partial/corrupted, not proof the user configured anything). ⚠️ if `HOOKS_JSON_EXISTS=0` — the plugin directory is missing `hooks/hooks.json`; reinstalling the plugin is the fix.
   - Vendored mode: grep the `.claude/settings.json` content captured above for the hook script names (`session-start.sh`, `learnings-surface.sh`, etc.). ✓ if at least `session-start.sh` and `learnings-surface.sh` appear (the two hooks a vendored install needs most — the primer reminder and the retrieval hook). ⚠️ listing which expected hook names are absent, with a pointer to `SKILL.md`'s hooks section for the entries to copy in.

3. **Four `.session-continuity/` files; primer shape, peers, freshness.** ✓/⚠️/✗ from the gather lines — never invent a signal that wasn't printed.
   - Existence: ✓/⚠️ per file from the `EXISTS`/`MISSING` lines (`SESSION_PRIMER.md`, `PROJECT_CONTEXT.md`, `ROADMAP.md`, `LEARNINGS.md`). `BACKLOG.md=FOSSIL` is a leftover markdown queue — ⚠️ "fossil BACKLOG.md; run `/session-continuity:primer` to migrate to GitHub Issues if `gh` is authenticated for the origin's host."
   - Shape: if `SESSION_PRIMER.md` exists and `PRIMER_VALIDATE=fail` → ✗ hard fail (shape). Cite any `INVALID:` lines from the validate helper stderr that appeared in the gather output. Fix: rewrite Mid-flight/Confirm to the thin hard-template and re-run `/session-continuity:primer`, then re-doctor.
   - Peers: if `ENGRIM` or `GRAPHIFY` is present and ≠ `ok` → ✗ hard fail (peers). Notes must include the install order: primer → graphify (commit `graphify-out/graph.json`) → engrim → re-doctor. Also note: commit/rebuild `graphify-out/graph.json`, ensure `engrim` is on PATH. Do not treat missing `ENGRIM=`/`GRAPHIFY=` lines (probe skipped) as a peer failure — report `?` for that sub-check.
   - Freshness: `STALE=1` → ⚠️ only ("primer stale vs substantive commits — run `/session-continuity:primer` to refresh"). `STALE=0` is fine. `STALE=?` → report `?`, do not invent stale. Do **not** compare any embedded git-log block; freshness comes only from `primer-freshness.sh`.
   - Marker precedence for this row: any ✗ (shape or peers) wins over ⚠️; list every distinct problem (missing files, shape, peers, fossil, stale) — do not summarize to a single cause.

4. **`CLAUDE_PLUGIN_ROOT` resolves and isn't stale.** Skip this row entirely in vendored mode (nothing to check). In plugin mode: ✓ if `ROOT_EXISTS=1`. Then check staleness — from the `ls "$CACHE_PARENT"` output, if it lists sibling version directories, compare the resolved version (parsed from `plugin.json` above) against the highest version number listed. If a newer one exists: ⚠️ "resolved root is v`<old>`, but v`<new>` is already installed in the cache — this session started before the update landed; restart the session to pick it up." If they match, or the cache-parent listing wasn't available (different install layout), ✓ with a note that the check was skipped when applicable — don't fail the row over a probe that simply didn't apply.

5. **Gate scripts executable.** Skip in vendored mode (no resolved root to check against). In plugin mode, one sub-row per `EXEC`/`NOEXEC:<path>` line captured above. ✓ if all are `EXEC`. For each `NOEXEC:<path>`, ⚠️ with the exact fix: `chmod +x <path>`.

6. **GitHub backlog.** Warning-level, not a hard install break. ✓ if `GH=PRESENT`, `GH_AUTH=OK`, and `BACKLOG_COUNT` is an integer (including 0) — works against github.com or any GitHub Enterprise Server host, since the underlying check is "`gh` has auth for the origin's host," not a literal `github.com` string match. ⚠️ listing which of those failed, and "run `/session-continuity:doctor` after `gh auth login --hostname <host>`" or "queue inactive — `gh` has no auth for this origin's host." One sentence: backlog titles and bodies are sent to GitHub (or your GHE instance) when filed; public repo means public issues.

**List every missing file, every missing hook name, and every non-executable script — do not summarize, filter, or pick a "primary" one.** If two gate scripts are missing their exec bit, the row lists both `chmod +x` commands, not one.

Emit the report as a table, same convention as `/session-continuity:end-session`'s checklist:

| Row | Marker | Content |
|---|---|---|
| Install mode | ✓ | "Plugin vX.Y.Z at `<path>`" OR "Vendored (CLAUDE_PLUGIN_ROOT unresolved)" |
| Hooks registered | ✓ / ⚠️ | plugin: "hooks.json present" OR "⚠️ hooks/hooks.json missing — reinstall the plugin" · vendored: "session-start.sh + learnings-surface.sh found in .claude/settings.json" OR "⚠️ missing: `<names>` — see SKILL.md's hooks section" |
| .session-continuity/ files | ✓ / ⚠️ / ✗ | "All four present; primer shape ok; peers ok; freshness current" OR "✗ primer shape — `PRIMER_VALIDATE=fail`" OR "✗ peers — `ENGRIM`/`GRAPHIFY` not ok; install order: primer → graphify (commit `graphify-out/graph.json`) → engrim → re-doctor" OR "⚠️ missing: `<names>`" OR "⚠️ primer stale (`STALE=1`) — run /session-continuity:primer" OR "⚠️ fossil BACKLOG.md" |
| CLAUDE_PLUGIN_ROOT | ✓ / ⚠️ / (skipped) | "vX.Y.Z, matches latest cached" OR "⚠️ resolved to vX.Y.Z, but vX.Y.Z+1 is cached — restart the session" OR "skipped (vendored mode)" |
| Gate scripts executable | ✓ / ⚠️ / (skipped) | "All N gate scripts executable" OR "⚠️ not executable: `chmod +x <path>`, `chmod +x <path>`" OR "skipped (vendored mode)" |
| GitHub backlog | ✓ / ⚠️ | "N open issues labeled backlog" OR "⚠️ gh/auth/origin/helper — queue inactive. Filing an issue sends title+body to GitHub (public repo → public issues)." |

## Notes

- **Never mutates anything.** No file writes, no `git add`, no `chmod` run on the user's behalf — every fix is a command printed for the user to run themselves.
- **Fail soft on probes that don't apply**, not on the row as a whole. A probe that was skipped because it doesn't apply to this install mode is not the same as a probe that ran and found a problem — don't conflate a `?`/skip with a ⚠️ or ✗.
- **Never invent a version number, path, or file list.** Every value in the report must trace back to a literal line in Step 1's output.
- **Peer hard-fail install order.** When `ENGRIM` or `GRAPHIFY` ≠ ok: primer → graphify (commit `graphify-out/graph.json`) → engrim → re-doctor. Rebuild/commit the graph if missing; put `engrim` on PATH.
- **Freshness is `STALE=` only.** Do not treat an embedded git log in the primer as a staleness signal — that compare is retired.
