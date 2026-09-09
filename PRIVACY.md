# Privacy policy

**Plugin:** `session-continuity`
**Maintainer:** Tal Golan ([github.com/talgolan](https://github.com/talgolan))
**Last updated:** 2026-09-09

## Short version

This plugin does not collect analytics or send data to the maintainer. Durable memory stays in your git repository. Session boot also expects local engrim memory and a committed `graphify-out/graph.json` as required peers (neither leaves your machine via this plugin). The work queue is GitHub Issues labeled `backlog` on that same repository: filing an issue sends its title and body to GitHub; SessionStart and `/session-continuity:backlog` read them back with authenticated `gh`. There is also one weekly unauthenticated version-check GET. Public repository means public issues.

## What data the plugin handles

- **File contents in your own repositories.** The slash commands `/session-continuity:primer`, `/session-continuity:learning`, and `/session-continuity:end-session` read and write `.session-continuity/SESSION_PRIMER.md`, `.session-continuity/PROJECT_CONTEXT.md`, `.session-continuity/ROADMAP.md`, and `.session-continuity/LEARNINGS.md` in the current git repository. These are ordinary files in your repo. `/session-continuity:spike-check`, `/session-continuity:doctor`, `/session-continuity:update`, and `/session-continuity:help` touch no files at all — they print a checklist/report/instructions and (for spike-check) ask questions in-conversation. `/session-continuity:backlog` lists GitHub Issues; it does not write a local backlog file.
- **GitHub Issues.** Filing a backlog item runs `gh issue create --label backlog` with the title and body you (or the agent) supplied. Listing and SessionStart injection run `gh issue list --label backlog`. Closing runs `gh issue close`. That traffic is authenticated as your `gh` login and is subject to that repository's GitHub visibility.
- **Git metadata.** The commands invoke `git log`, `git status`, `git diff --cached`, and similar read-only commands to populate the primer and checklist. This metadata is processed locally and written into the in-repo files; it is never transmitted except as issue text you chose to file.
- **Hook payloads.** Claude Code passes the hook scripts a JSON payload containing the current working directory and, depending on the hook, the Bash command about to run or the file path + content about to be written/edited. The scripts read these values locally to decide whether to emit a reminder or block the action. Nothing from the payload is persisted outside the running session. SessionStart does call `gh issue list` as described above.

**The plugin does not touch:** environment variables (other than `GH_BIN`, `BACKLOG_ISSUES_TIMEOUT`, and `SESSION_CONTINUITY_SKIP_UPDATE_CHECK`), shell history, editor state, other files in your repo, any file outside the current working directory, your clipboard, or anything on disk outside the documented files plus the update-check cache described below.

## External network calls

Two classes of call, both to GitHub.

**1. Weekly version check (unauthenticated).**

**What:** An unauthenticated `GET` request to `https://api.github.com/repos/talgolan/session-continuity/releases/latest` (or, if you've configured a different `repository` field in your local `plugin.json`, the equivalent URL for that repo).

**Why:** To compare the installed plugin version against the latest public GitHub Release and nudge you inside Claude Code if a newer version is available.

**When:** At most once every 7 days per machine. The last-check timestamp is stored at `${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity/last-check`.

**What data is sent:** Only what the GitHub API endpoint inherently sees — your IP address (as on any outbound HTTP request) and a standard `curl` user agent string. No account identifier, no plugin identifier, no repo contents, no query parameters, no cookies, no PII.

**Timeout and failure handling:** The call has a 3-second timeout. Network errors are swallowed silently — a failed check never blocks your session or surfaces an error.

**How to disable:** Set the environment variable `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`. The update check will be skipped entirely, no network call made, and no cache file written.

**2. Backlog (authenticated `gh`).**

**What:** `gh issue list`, `gh issue create`, `gh issue close`, and `gh label create` against the GitHub repository that `origin` points at, when that origin contains `github.com`.

**Why:** The plugin's work queue is open issues labeled `backlog`.

**When:** SessionStart and `/session-continuity:backlog` list (3-second timeout; failure skips injection / prints a warning). Filing and closing happen when you or the agent run those commands during primer / end-session.

**What data is sent:** Issue titles and bodies you supply; your GitHub credentials via `gh`; the repository identity inferred from `origin`.

**How to disable:** Do not install/auth `gh` for the origin's host. The queue surface no-ops and `doctor` warns. There is no markdown fallback.

## What the plugin does **not** do

- No analytics, telemetry, or usage reporting.
- No account identifiers, device fingerprints, or session identifiers are generated or stored by the plugin itself (`gh` uses your existing GitHub login).
- No data is sent to the maintainer or Anthropic. Network calls are to GitHub only.
- No third-party SDKs, trackers, or dependencies are bundled. The plugin is plain Markdown, bash, and JSON.
- No background processes, daemons, or persistent connections are created.

## Third-party services

Version check and the backlog both depend on GitHub. GitHub's privacy practices are covered by the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement).

## Data retention

The only persistent data the plugin creates outside your repo is the mtime of `${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity/last-check` (an empty file whose modification time gates the weekly update check). You can delete this file or directory at any time; the plugin will recreate it on the next session start. GitHub Issues follow GitHub's retention for that repository.

## Changes to this policy

This policy will be updated in the repo (`PRIVACY.md`) if the plugin ever adds a new external call, new data flow, or new file written outside the documented paths. Material changes will be mentioned in `CHANGELOG.md`. This file's canonical location is <https://github.com/talgolan/session-continuity/blob/main/PRIVACY.md>.

## Contact

Privacy questions, concerns, or reports of inadvertent data exposure: open an issue or a [Security Advisory](https://github.com/talgolan/session-continuity/security/advisories/new) on the repository.
