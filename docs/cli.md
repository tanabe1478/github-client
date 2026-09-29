# Command-line client

`ghclient` reads and changes the same data as the desktop app without opening a window, so scripts and AI agents can triage GitHub activity. It uses the tokens saved in the app and the files under the app's data directory.

Install it on macOS with `scripts/macos/install-cli.sh` (default destination `~/.local/bin/ghclient`). Run `ghclient --help` for the full usage text.

## Commands

| Command | What it does |
|---|---|
| `inbox [--kind all\|pr\|issue] [--repo OWNER/NAME] [--query TEXT] [--all]` | Open pull requests and issues in watched repositories |
| `for-you [--reason REASON] [--all]` | Review requests, assignments, mentions, and subscriptions in watched repositories |
| `saved` | Saved items, done or not |
| `done <url>...` | Mark items done at their current GitHub revision |
| `undone <url>...` | Move items back to the inbox |
| `save <url>...` / `unsave <url>...` | Save or unsave items |
| `mute <url>...` / `unmute <url>...` | Hide items everywhere, or show them again |
| `repos` | Watched repositories |
| `watch <owner/name>...` / `unwatch <owner/name>...` | Change watched repositories |
| `accounts` | Saved token scopes and their logins; never the tokens |

Activity commands fetch from GitHub on every call and hide done items unless `--all` is given. `--query` matches the title, `#number`, or `@author`, as the app's filter does. Reasons are `Review requested`, `Assigned`, `Mentioned`, and `Subscribed`. A review request GitHub removed after a teammate reviewed for the team stays until you review or the pull request closes; it carries both `Review requested` and `Still needs your review`. `for-you` shares that list with the app (`review-requests.txt`). Item URLs are `https://github.com/OWNER/NAME/pull/N` or `.../issues/N`.

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

Items are sorted newest first. Lists are read to their last page (up to 2,000 open pull requests and 2,000 open issues per repository, 1,000 per For you source); a list that reaches its limit is named in `warnings`. `kind` is `pull_request` or `issue`; `reasons` is filled for `for-you`. `draft` is always `false` for items fetched one by one (`saved`), because that endpoint does not report it.

Commands that change state:

```json
{ "results": [{ "target": "https://github.com/...", "ok": true, "state": "done" }] }
```

A failed target has `"ok": false` and an `"error"` message; the other targets are still applied.

`repos` prints `{"repositories": ["owner/name", ...]}` and `accounts` prints `{"accounts": [{"scope", "login"}], "errors": [...]}`.

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
