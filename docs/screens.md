# Screen inventory

This inventory mirrors the top-level frames planned on the Figma `Screens` page. Figma is the visual source of truth after a surface has a non-empty `figmaNodeId` in `design/figma.json`. Repository code remains the source of truth for behavior, accessibility, security, and platform constraints.

| Stable ID | Screen/state | Primary purpose | Figma status |
|---|---|---|---|
| `inbox` | Inbox | Watched repositories and relevant dependency impact | Pending node |
| `for-you` | For you | Mentions, assignments, review requests, subscriptions | Pending node |
| `repositories` | Repositories | Watch, filter, and remove repositories | Pending node |
| `pull-requests` | Pull requests | Open pull requests from watched repositories | Pending node |
| `issues` | Issues | Open issues from watched repositories | Pending node |
| `settings` | Settings | Credential status and application configuration | Pending node |
| `pat-dialog` | Personal access token dialog | Securely add or replace a GitHub PAT | Pending node |

## Required states

Each screen frame must document relevant loading, empty, error, populated, disabled, and destructive-action states. Important operations use explicit buttons; row click and double click are not primary actions.

## Synchronization rule

- Never infer a Figma node ID from a frame name.
- A screen is synchronized only when `design/figma.json` contains its node ID and current native screenshot evidence.
- `status: "partial"` means the file is bound but one or more screen nodes remain unsynchronized.
- `status: "active"` requires every listed surface to have a node ID.
