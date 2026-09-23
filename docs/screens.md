# Screen inventory

Repository code is the source of truth for behavior, accessibility, security, platform constraints, and visual implementation. Native screenshots under `artifacts/` provide visual evidence.

| Stable ID | Screen/state | Primary purpose |
|---|---|---|
| `inbox` | Inbox | Watched repositories and relevant dependency impact |
| `for-you` | For you | Mentions, assignments, review requests, and subscriptions from Watched repositories |
| `repositories` | Repositories | Watch, filter, and remove repositories |
| `pull-requests` | Pull requests | Open pull requests from watched repositories |
| `issues` | Issues | Open issues from watched repositories |
| `settings` | Settings | Credential status and application configuration |
| `pat-dialog` | Personal access token dialog | Securely add or replace a GitHub PAT |

## Required states

Each screen should implement and test relevant loading, empty, error, populated, disabled, and destructive-action states. Important operations use explicit buttons; row click and double click are not primary actions.

Activity screens expose unread counts, an unread-only filter, and explicit `Open` / `Mark read` / `Mark unread` actions. Opening an activity marks its current GitHub `updated_at` revision as read. A later GitHub update makes it unread again.

## Visual structure

The native shell uses the GitHub Primer light palette and takes structural inspiration from the [Rare UI Folder component](https://www.rareui.com/components/foldercomponent): a quiet navigation rail, one elevated rounded workspace, and layered folder/paper motifs that communicate grouped activity. The implementation is native Dear ImGui drawing rather than an embedded web component.

Folder hover and selected states are decorative feedback only. Navigation labels and all primary operations remain visible, explicit controls. The active destination uses a blue indicator, tinted surface, and label; unread totals use badges and are not communicated by color alone.

Screenshot evidence for this layout is stored under `artifacts/rareui-refactor/`, including Inbox, For you, Repositories, Settings, and the Settings interaction smoke.
