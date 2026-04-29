# Privacy policy

**Plugin:** `session-continuity`
**Maintainer:** Tal Golan ([github.com/talgolan](https://github.com/talgolan))
**Last updated:** 2026-04-28

## Short version

This plugin does not collect, transmit, or store personal data about you. All data the plugin handles stays on your local machine, inside your own git repositories, under your own control. There is one external network call — a weekly version check against a public GitHub API endpoint — which sends no identifying information and can be disabled with an environment variable.

## What data the plugin handles

- **File contents in your own repositories.** The slash commands (`/session-continuity:primer`, `/session-continuity:learning`, `/session-continuity:end-session`) read and write `docs/SESSION_PRIMER.md` and `docs/LEARNINGS.md` in the current git repository. These are ordinary files in your repo; the plugin stores nothing elsewhere.
- **Git metadata.** The commands invoke `git log`, `git status`, `git diff --cached`, and similar read-only commands to populate the primer and checklist. This metadata is processed locally and written into the same two files; it is never transmitted.
- **Hook payloads.** Claude Code passes the hook scripts a JSON payload containing the current working directory and the command being run. The scripts read these values locally to decide whether to emit a reminder. Nothing from the payload is transmitted or persisted outside the running session.

**The plugin does not touch:** environment variables, shell history, editor state, other files in your repo, any file outside the current working directory, your clipboard, or anything on disk outside the two documented files plus the update-check cache described below.

## External network calls

There is exactly one external call.

**What:** An unauthenticated `GET` request to `https://api.github.com/repos/talgolan/session-continuity/releases/latest` (or, if you've configured a different `repository` field in your local `plugin.json`, the equivalent URL for that repo).

**Why:** To compare the installed plugin version against the latest public GitHub Release and nudge you inside Claude Code if a newer version is available.

**When:** At most once every 7 days per machine. The last-check timestamp is stored at `${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity/last-check`.

**What data is sent:** Only what the GitHub API endpoint inherently sees — your IP address (as on any outbound HTTP request) and a standard `curl` user agent string. No account identifier, no plugin identifier, no repo contents, no query parameters, no cookies, no PII.

**Timeout and failure handling:** The call has a 3-second timeout. Network errors are swallowed silently — a failed check never blocks your session or surfaces an error.

**How to disable:** Set the environment variable `SESSION_CONTINUITY_SKIP_UPDATE_CHECK=1`. The update check will be skipped entirely, no network call made, and no cache file written.

## What the plugin does **not** do

- No analytics, telemetry, or usage reporting.
- No account identifiers, device fingerprints, or session identifiers are generated or stored.
- No data is sent to the maintainer, Anthropic, or any third party. The single network call is to the public GitHub API only.
- No third-party SDKs, trackers, or dependencies are bundled. The plugin is plain Markdown, bash, and JSON.
- No background processes, daemons, or persistent connections are created.

## Third-party services

The update check depends on GitHub's public API. GitHub's privacy practices are covered by the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement). The plugin has no relationship with GitHub beyond issuing this one unauthenticated request to a public endpoint.

## Data retention

The only persistent data the plugin creates outside your repo is the mtime of `${XDG_CACHE_HOME:-$HOME/.cache}/session-continuity/last-check` (an empty file whose modification time gates the weekly update check). You can delete this file or directory at any time; the plugin will recreate it on the next session start.

## Changes to this policy

This policy will be updated in the repo (`PRIVACY.md`) if the plugin ever adds a new external call, new data flow, or new file written outside the documented paths. Material changes will be mentioned in `CHANGELOG.md`. This file's canonical location is <https://github.com/talgolan/session-continuity/blob/main/PRIVACY.md>.

## Contact

Privacy questions, concerns, or reports of inadvertent data exposure: open an issue or a [Security Advisory](https://github.com/talgolan/session-continuity/security/advisories/new) on the repository.
