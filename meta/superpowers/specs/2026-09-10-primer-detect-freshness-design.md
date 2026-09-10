# Design — Align `primer-detect` drift with `primer-freshness.sh` (#64)

**Issue:** #64  
**Amends:** `meta/superpowers/specs/2026-09-08-primer-detect-design.md` (drift half of `DO_REFRESH` only)

## Context

Plugin 0.36.0 (#62 / #63) shipped thin hard-template `SESSION_PRIMER.md` files
that no longer embed a `git log --oneline -5` block. Freshness is owned by
`hooks/lib/primer-freshness.sh` (`STALE=0|1|?`), already used by
`/session-continuity:end-session`, `/session-continuity:doctor`, and
`hooks/session-start.sh`.

`primer-detect.sh` / `.jq` still compute `LOG_DRIFT` by parsing an embedded
log block out of primer content. Missing block ⇒ `LOG_DRIFT=1`. Thin
dogfood primers therefore always dispatch `STEPS=…,refresh` (or
`STEPS=refresh`) even when `primer-freshness.sh` reports `STALE=0`.

Repro on this repo at design time: `STALE=0`, detect `LOG_DRIFT=1` /
`STEPS=refresh`.

## Problem

Detect's refresh trigger and the rest of the plugin disagree on what
"primer drifted" means. Check mode (`STEPS` empty) can never no-op for a
thin primer.

## Decisions (locked)

| Decision | Choice |
|---|---|
| `STALE=?` | Treat as refresh needed (`LOG_DRIFT=1`), same as `end-session` |
| stdout contract | Keep `LOG_DRIFT=0\|1` only. Map from freshness internally; never emit or forward `STALE=` (or raw freshness stdout) to detect callers |
| Wiring | Approach 1 — bash calls freshness, passes a drift bit into jq |
| `CODE_STAGED` | Unchanged; still independently forces `DO_REFRESH` |
| Embedded-log compare | Retired for detect. No dual-path for thick primers |
| `LOG_DRIFT` name | Keep under `CONTRACT_VERSION=1`. Semantic flip is intentional — document in `primer-detect.sh` header that the key is freshness-mapped, not embedded-log compare |

## Architecture

```
primer-detect.sh (I/O)                    primer-detect.jq (pure decision)
  - file-existence checks          -->      - detect inline-outstanding
  - git remote get-url                      - classify staged files (allowlist)
  - git diff --cached --name-only           - github.com origin check
  - primer file content (if any)            - migration trigger chain
  - bash "$SCRIPT_DIR/primer-freshness.sh" "$DIR"
      → parse STALE= only                   - DO_REFRESH = (log_drift==1) OR CODE_STAGED
      map: 0→0; 1|?|bad→1                   - emit KEY=value + STEPS=
      --argjson log_drift N                   (no STALE= line)
```

Dropped from detect I/O: `git log --oneline -5` gather.  
Dropped from jq: `log_drift()` content capture / string compare.

`primer-freshness.sh` remains the single policy for substantive-commit
staleness (path ignores, primer-tip base). Detect does not reimplement it.

## Mapping

| Probe result | detect `--argjson log_drift` / emitted `LOG_DRIFT` |
|---|---|
| helper readable, `CONTRACT_VERSION=1`, stdout `STALE=0` | `0` |
| helper readable, `CONTRACT_VERSION=1`, stdout `STALE=1` | `1` |
| helper readable, `CONTRACT_VERSION=1`, stdout `STALE=?` | `1` |
| helper missing / unreadable / header not `CONTRACT_VERSION=1` / nonzero exit / no `STALE=` line | `1` (conservative — same as `?`; do **not** `die`) |

**Contract check recipe:** before running the helper, require
`[[ -r "$SCRIPT_DIR/primer-freshness.sh" ]]` and
`grep -q '^# CONTRACT_VERSION=1$' "$SCRIPT_DIR/primer-freshness.sh"`.
Either check failing → set `log_drift=1` and skip the probe. On success,
run `bash "$SCRIPT_DIR/primer-freshness.sh" "$DIR"` (always pass `$DIR`,
never rely on cwd), take the first `STALE=` line, map per table above.

No primer file: freshness prints `STALE=?`, but detect already short-circuits
to `STEPS=init` when `PRIMER_EXISTS=0`. Mapping still runs; `LOG_DRIFT` is
emitted for contract completeness and ignored for dispatch.

## State machine (unchanged except drift source)

```
DO_REFRESH = (LOG_DRIFT == 1) OR (CODE_STAGED == 1)
```

`LOG_DRIFT` is no longer "embedded log ≠ actual log". It means "freshness
says not clean" under the mapping above. Name kept for contract stability
(`CONTRACT_VERSION=1` key set unchanged). Header comment on
`primer-detect.sh` must state the new meaning so callers/maintainers do
not reintroduce log-block compare.

Empty `STEPS` (check mode) when: primer exists, no migration triggers,
`LOG_DRIFT=0`, `CODE_STAGED=0`.

## Error handling

- Freshness probe degraded (missing helper, wrong `CONTRACT_VERSION`,
  bad/missing `STALE=`, nonzero exit): map to `log_drift=1`; do not
  hard-fail detect. Destructive migrations stay gated only by explicit
  migration facts.
- jq / detect operational failures unchanged (no `STEPS=` line, exit 1).

## Deliverables

1. Implement wiring + mapping in `hooks/lib/primer-detect.sh` / `.jq` per
   Architecture and Mapping.
2. Update `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`
   per Testing below.
3. Amend `meta/superpowers/specs/2026-09-08-primer-detect-design.md`
   architecture diagram and `LOG_DRIFT` prose so freshness is the drift
   source (no embedded-log compare).

## Testing

Update `meta/superpowers/validation/2026-09-08-primer-detect-smoke.zsh`:

1. **Retire case 4** (overwrite embedded log without committing). That
   no longer signals refresh.
2. **Replace with freshness-driven cases:**
   - **Dogfood / empty `STEPS`:** commit thin primer (no log block) as the
     latest primer tip; no later substantive commits; migration facts
     off — `PROJECT_CONTEXT.md` present, no inline Outstanding heading,
     no `OUTSTANDING_ITEMS.md`, no `BACKLOG.md` (so `gh` origin cannot
     fire `backlog_to_issues`). Expect `STALE=0` → `LOG_DRIFT=0` →
     `STEPS=` empty.
   - **`STALE=1`:** after that primer tip, commit a non-allowlisted path
     (e.g. `src/foo.sh`) → `STEPS=refresh`.
   - **`STALE=?`:** init a git repo; write thin primer + `PROJECT_CONTEXT.md`
     + other needed files on disk; **do not** `git add` /
     `git commit` the primer path (so `git log -1 -- <primer>` is empty).
     No migration triggers. Expect freshness `STALE=?` → `LOG_DRIFT=1` →
     `STEPS=refresh`.
3. Keep staged-code / allowlisted-docs / migration-order cases. Simplify
   `mk_repo` to a thin primer body (no embedded log block) — detect must
   not require one.

## Out of scope

- Changing `primer-freshness.sh` policy or `STALE` semantics
- Renaming `LOG_DRIFT` / bumping detect `CONTRACT_VERSION`
- Removing `CODE_STAGED` or changing its allowlist
- `/session-continuity:primer` Step 4 refresh *content* (still model prose)

## Success criteria

1. This repo's thin primer with `STALE=0` and clean index → detect
   `LOG_DRIFT=0` and no `refresh` in `STEPS`.
2. `STALE=1` or `STALE=?` → `LOG_DRIFT=1` → `refresh` when no migrations
   preempt (migrations still prepend).
3. Non-allowlisted staged file still → `refresh` even if `STALE=0`.
4. Existing migration-order smokes still pass.
5. `end-session` / `doctor` / `session-start` freshness behavior untouched.
