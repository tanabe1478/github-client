# Command-line client

`ghclient` reads and changes the same data as the desktop app without opening a window, so scripts and AI agents can triage GitHub activity. It uses the tokens saved in the app and the files under the app's data directory.

Install it on macOS with `scripts/macos/install-cli.sh` (default destination `~/.local/bin/ghclient`). Run `ghclient --help` for the full usage text.

## Commands

| Command | What it does |
|---|---|
| `inbox [--kind all\|pr\|issue] [--repo OWNER/NAME] [--query TEXT] [--all]` | Open pull requests and issues in watched repositories |
| `for-you [--reason REASON] [--all]` | Review requests, assignments, mentions, and subscriptions in watched repositories that choose For you |
| `releases [--repo OWNER/NAME] [--query TEXT] [--all] [--related] [--project OWNER/NAME]` | Releases of watched repositories that choose Releases, with how each relates to the base projects. `--related` keeps releases related to at least one base project; `--project` keeps releases related to that one |
| `saved` | Saved items, done or not |
| `done <url>...` | Mark items done at their current GitHub revision |
| `undone <url>...` | Move items back to the inbox |
| `save <url>...` / `unsave <url>...` | Save or unsave items |
| `mute <url>...` / `unmute <url>...` | Hide items everywhere, or show them again |
| `repos` | Watched repositories and what each brings in |
| `watch <owner/name>... [--kinds KINDS] [--release-notify LEVEL]` / `unwatch <owner/name>...` | Change watched repositories. `--kinds` takes a comma-separated list of `pull-requests`, `issues`, `releases`, and `for-you`; `--release-notify` takes `all`, `major-minor`, `major`, or `off`. Without them, a new repository gets pull requests, issues, and For you, and a watched one keeps its options |
| `projects` | Base projects and what was read from each |
| `project-add <owner/name\|directory>...` / `project-remove <owner/name>...` | Change base projects. A GitHub URL is read as owner/name. A directory that exists adds every GitHub repository found in it (the `origin` of each `.git/config`, two levels down); the directory itself is not saved |
| `watch-candidates` | Repositories the base projects depend on and you do not watch: GitHub Actions, Terraform providers, known packages such as pnpm and Spring Boot, and npm and Maven libraries whose registry entry names a GitHub repository. Watch them with `watch <owner/name> --kinds releases` |
| `npm-mirror-add <url>...` / `npm-mirror-remove <url>...` | Treat an npm registry that a base project's `.npmrc` sets, such as a company proxy, as a mirror of the public one. Packages from it are then looked up on registry.npmjs.org for their repositories; packages from any other registry are never sent there |
| `accounts` | Saved token scopes and their logins; never the tokens |

Activity commands fetch from GitHub on every call and hide done items unless `--all` is given. `--query` matches the title, `#number`, or `@author`, as the app's filter does. Reasons are `Review requested`, `Assigned`, `Mentioned`, and `Subscribed`. A review request GitHub removed after a teammate reviewed for the team stays until you review or the pull request closes; it carries both `Review requested` and `Still needs your review`. `for-you` shares that list with the app (`review-requests.txt`). Item URLs are `https://github.com/OWNER/NAME/pull/N`, `.../issues/N`, or `.../releases/tag/TAG`.

## Settings

Settings live in `settings.txt` in the app's data directory (`~/.config/moonbit-github-client/settings.txt` on macOS). The Settings page in the app writes the same file, and the file is meant to be edited by hand or by AI agents: one `key = value` per line, `#` starts a comment, and a missing file or key means the default.

| Key | Values | Default | Effect |
|---|---|---|---|
| `mentions.include_merged` | `true`, `false` | `false` | `Mentioned` in For you also lists merged pull requests updated within `mentions.days`, labeled `Merged` |
| `mentions.include_closed` | `true`, `false` | `false` | `Mentioned` also lists issues and pull requests closed without merging and updated within `mentions.days`, labeled `Closed` |
| `mentions.days` | `1` to `365` | `30` | How many days back review comments are read for mentions, and how recently a merged or closed item must have been updated |
| `base.repository` | `owner/name`, one line each | none | A base project. Releases are matched against what its npm, pnpm, Gradle, Maven, GitHub Actions, and Terraform files use on the default branch, at any depth outside tests and build output, with the Java and Node.js versions and Spring `application*.yml` keys (ADR 0007). Versions left to a BOM, such as Spring Boot's, come from the BOM on Maven Central; only its public coordinates are sent. Reading needs a token with Contents: Read-only |

A running app picks up a change within a few seconds and refreshes For you; `ghclient` reads the file on every command. An unknown key or an invalid value is an error: the app keeps its previous settings and logs it, and `ghclient` reports it under `settings` and uses the defaults.

`done` fetches the item first, so a later update on GitHub makes it unread again, as in the app. The other triage commands only change local files.

## Output

`--json` prints one JSON object on stdout and nothing else. Diagnostics go to stderr, and only with `--verbose`.

Activity commands:

```json
{
  "items": [
    {
      "url": "https://github.com/acme/storefront/pull/2116",
      "repository": "acme/storefront",
      "number": 2116,
      "kind": "pull_request",
      "draft": false,
      "title": "Security scan results (2026-09-29)",
      "author": "release-bot[bot]",
      "updated_at": "2026-09-29T10:28:04Z",
      "read": false,
      "saved": false,
      "reasons": []
    }
  ],
  "errors": [{ "source": "owner/name or token:SCOPE", "message": "..." }],
  "warnings": ["acme/storefront issues hit the page limit; only the newest items are included"]
}
```

Items are sorted newest first. Lists are read to their last page (up to 2,000 open pull requests and 2,000 open issues per repository, 1,000 per For you source); a list that reaches its limit is named in `warnings`. `kind` is `pull_request`, `issue`, or `release`; release items also carry `tag`, `summary` (the first sentence of the notes), `prerelease`, and `relations`, and their `updated_at` is the publication date; `reasons` is filled for `for-you`. `draft` is always `false` for items fetched one by one (`saved`), because that endpoint does not report it.

Commands that change state:

```json
{ "results": [{ "target": "https://github.com/...", "ok": true, "state": "done" }] }
```

A failed target has `"ok": false` and an `"error"` message; the other targets are still applied.

Each entry of `relations` is one rule that matched one base project:

```json
{
  "project": "acme/web",
  "kind": "major",
  "label": "pnpm 11.4.0 → 12.12.0 · Major update",
  "related": true,
  "evidence": ["package.json packageManager sets pnpm: 11.4.0", "12.12.0 is in major line 12; the project is on 11"]
}
```

Labels use the tag's version, so a milestone reads `Spring Boot 4.1.1 → 4.2.0-M2`. `kind` is `major` (a newer major version than the project uses), `newer` (newer in the same major line than an exact version), `setting` (the notes name a setting in the project's `.npmrc` or `pnpm-workspace.yaml`), or `in-use` (the project already uses this version or a range that allows it). `in-use` has `"related": false` and does not count for `--related`.

`projects` prints `{"projects": [{"repository", "package_name", "tools": [{"name", "version", "exact", "source"}], "settings": [{"key", "file"}], "files", "dependency_count", "managed", "problem", "moved_to", "sources", "unreleased", "npm_registry"}]}`. `moved_to` is the new owner/name of a repository renamed on GitHub; replace it with `project-remove` and `project-add`. GitHub Actions and Terraform providers are tools named by their repository, such as `actions/checkout` and `hashicorp/terraform-provider-aws`. `managed` lists dependencies declared without a version; a tool whose `source` ends with `BOM` got its version from that BOM. `problem` is empty when the files could be read; a repository with nothing to read has no `problem` and no `tools`. `sources` lists the GitHub repository each dependency's registry entry names (`{"name", "repository"}`), and `unreleased` the repositories it depends on that publish no GitHub releases. `npm_registry` is the registry its `.npmrc` sends npm packages to when that is not the public one; its packages are looked up only after `npm-mirror-add`. Setting values in `.npmrc`, `gradle.properties`, and Spring settings are never read into the output.

Without `--related`, `--project` also keeps only releases related to that project, and shows only its relations.

`watch-candidates` prints `{"candidates": [{"repository", "projects", "uses", "released"}]}`: those with GitHub releases first, then the ones most base projects use. `uses` reads like `"acme/web: 4.4.0"`, or `"acme/api: org.zalando:logbook-core 4.1.0"` for a library found through its registry. `released` is false for a repository without GitHub releases, which brings nothing in when watched.

`repos` prints `{"repositories": ["owner/name", ...], "options": [{"repository", "kinds": [...], "release_notify"}]}` and `accounts` prints `{"accounts": [{"scope", "login"}], "errors": [...]}`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Failure, or at least one target of a changing command failed |
| 2 | Usage error |
| 3 | The list was printed, but some GitHub requests failed; see `errors` |

## Working alongside the app

The app checks its data files every two seconds and reloads any file changed outside it: done state, saved and muted items, and watched repositories. A newly watched repository is fetched in the background. If the app and `ghclient` change the same file within those two seconds, the later write wins.

## Tokens

`ghclient` uses the first matching token in this order: the owner's scope, then the default token. When a request fails with that token and more tokens are saved, it loads every token's repository list once, as the app does, and retries. Add and remove tokens in the app; `ghclient` never prints them.

## Example: an agent triage loop

```sh
# Review requests that are still open and not done
ghclient for-you --reason "Review requested" --json

# Mark every dependabot update in one repository as done
ghclient inbox --repo acme/storefront --query @dependabot --json \
  | jq -r '.items[].url' | xargs ghclient done --json
```
