# Screen inventory

Repository code is the source of truth for behavior, accessibility, security, platform constraints, and visual implementation. Native screenshots under `artifacts/` provide visual evidence.

| Stable ID | Screen/state | Primary purpose |
|---|---|---|
| `inbox` | Inbox | Watched repositories and relevant dependency impact |
| `for-you` | For you | Mentions, assignments, review requests, subscriptions |
| `repositories` | Repositories | Watch, filter, and remove repositories |
| `pull-requests` | Pull requests | Open pull requests from watched repositories |
| `issues` | Issues | Open issues from watched repositories |
| `settings` | Settings | Credential status and application configuration |
| `pat-dialog` | Personal access token dialog | Securely add or replace a GitHub PAT |

## Required states

Each screen should implement and test relevant loading, empty, error, populated, disabled, and destructive-action states. Important operations use explicit buttons; row click and double click are not primary actions.
