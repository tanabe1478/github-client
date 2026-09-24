# Screen inventory

Repository code is the source of truth for behavior, accessibility, security, platform constraints, and visual implementation. Native screenshots under `artifacts/` provide visual evidence.

| Stable ID | Screen/state | Primary purpose |
|---|---|---|
| `inbox` | Inbox | Watched repositories and relevant dependency impact |
| `for-you` | For you | Mentions, assignments, review requests, and subscriptions from Watched repositories, merged across every saved credential and deduplicated by activity URL |
| `saved` | Saved | Activities saved for later, kept independently of their done state |
| `repositories` | Repositories | Watch, filter, and remove repositories |
| `pull-requests` | Pull requests | Open pull requests from watched repositories |
| `issues` | Issues | Open issues from watched repositories |
| `settings` | Settings | Credential list (default and owner/organization scopes), auto-refresh toggle, and application configuration |
| `pat-dialog` | Personal access token dialog | Securely add or replace a GitHub PAT for the default or an owner/organization scope |

## Required states

Each screen should implement and test relevant loading, empty, error, populated, disabled, and destructive-action states. Important operations use explicit buttons; row click and double click are not primary actions.

Activity screens expose unread counts, a `Show done` toggle, an explicit `Refresh` action that refetches from GitHub, and explicit `Open` / `Done` / `Save` / `Unsubscribe` trailing actions on every row.

- `Done` marks the activity's current GitHub `updated_at` revision as done and hides the row by default. `Show done` reveals done rows with a `Move to inbox` restore action. A later GitHub update makes the item unread again.
- `Save` adds the activity to the Saved page and marks the row with a `Saved` label; the button toggles back to remove it.
- `Unsubscribe` mutes the activity locally: the row is hidden from every list, including Saved, and the item is excluded from macOS notification selection. There is currently no in-app way to unmute.
- `Open` opens the activity in the default browser.

Done state persists in the read-state store; saved and muted URLs persist in the triage store. Watching or unwatching a repository also refreshes repository activity and For you.

Repository API calls resolve their credential automatically: an exact owner scope first, then the credential whose accessible repository list contains the repository, then the credential whose accessible list contains the owner, and finally the default credential. Repository suggestions are fetched with every saved credential and merged by full name.

When the Settings auto-refresh toggle is on, watched and personal activity is refetched every five minutes. Activities that are new or updated since the last fetch post a macOS notification via `osascript` (individual items up to three, a summary beyond that). Items fetched through manual actions are marked seen and do not notify.

## Visual structure

The native shell uses the GitHub Primer light palette and takes structural inspiration from the [Rare UI Folder component](https://www.rareui.com/components/foldercomponent): a quiet navigation rail, one elevated rounded workspace, and layered folder/paper motifs that communicate grouped activity. The implementation is native Dear ImGui drawing rather than an embedded web component.

Folder hover and selected states are decorative feedback only. Navigation labels and all primary operations remain visible, explicit controls. The active destination uses a blue indicator, tinted surface, and label; unread totals use badges and are not communicated by color alone.

Screenshot evidence for this layout is stored under `artifacts/rareui-refactor/`, including Inbox, For you, Repositories, Settings, and the Settings interaction smoke.
