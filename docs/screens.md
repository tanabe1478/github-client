# Screen inventory

Repository code is the source of truth for behavior, accessibility, security, platform constraints, and visual implementation. Native screenshots under `artifacts/` provide visual evidence.

| Stable ID | Screen/state | Primary purpose |
|---|---|---|
| `inbox` | Inbox | Open issues and pull requests from watched repositories, grouped by repository, with kind, repository, and text filters |
| `for-you` | For you | Review requests, assignments, mentions, and subscriptions from watched repositories, merged across every saved credential and deduplicated by activity URL, with a reason filter |
| `saved` | Saved | Activities saved for later, kept independently of their done state |
| `repositories` | Repositories | Watch by name, watch from account suggestions, and unwatch |
| `settings` | Settings | Personal access tokens (default and owner/organization scopes), auto refresh, and the local data location |
| `onboarding` | First launch | Shown on activity pages while no token is saved: connect GitHub, then watch repositories |
| `pat-dialog` | Personal access token dialog | Add or replace a token; verifies it with GitHub before saving |
| `credential-confirm` | Remove token dialog | Confirms removing a token, which cannot be undone |
| `row-menu` | More actions menu | Copy link, show only the row's repository, and Unsubscribe |
| `loading-dialog` | Loading dialog | Progress for fetches the user started |
| `alert` | Timeout dialog | A fetch that took too long, with Try again |

`nav pull-requests` and `nav issues` in the control file open Inbox with the matching kind filter; they are no longer separate pages.

## Activity rows

Each row has two lines: the title, and a meta line with `#number`, `@author`, `updated <date>`, and `Done` / `Draft` / `Saved` labels. Unread rows show a blue dot and a bold title; the icon shows pull request, draft pull request, or issue. For you and Saved rows also show the repository, and For you rows start the meta line with reason labels: `Review requested` (blue), `Assigned` (green), `Mentioned` (purple), and `Subscribed` (neutral). Labels carry their text, so color is never the only signal.

Every row has explicit trailing actions: `Open`, `Done` (or `Move to inbox` for done rows), a Save toggle, and a More actions button. The menu holds `Copy link`, `Show only this repository`, and, separated below them, `Unsubscribe`. Row click and double click are not actions.

In Inbox, two or more updates from `dependabot[bot]` or `renovate[bot]` in one repository collapse into one row with `Show N` / `Hide` and `Done all`.

- `Done` marks the activity's current GitHub `updated_at` revision as done and hides the row unless `Show done` is on. A later GitHub update makes the item unread again.
- `Save` adds the activity to Saved; the toggle removes it again.
- `Unsubscribe` mutes the activity locally: it is hidden from every list, including Saved, and excluded from notifications.
- `Open` opens the activity in the default browser.

Done, Move to inbox, Done all, Save, Unsubscribe, and Unwatch confirm the result in a snackbar with `Undo`. Other results use the same snackbar without Undo.

Done state persists in the read-state store; saved and muted URLs persist in the triage store.

Repository API calls resolve their credential automatically: an exact owner scope first, then the credential whose accessible repository list contains the repository, then the credential whose accessible list contains the owner, and finally the default credential. Repository suggestions are fetched with every saved credential and merged by full name. Suggestions with review requests for the viewer are listed first.

## Empty and error states

- Inbox with nothing unread: `You're all caught up` with `Show done`. For you and Saved have their own empty messages.
- Filters that match nothing: `No items match these filters` with `Clear filters` and `Show done`.
- No data and GitHub unreachable: a full-page `Can't reach GitHub` with `Try again`.
- Banners above the list, each dismissible: a rejected token (401) or a token the Keychain cannot read, with `Replace token`; a rate limit, with the time auto refresh resumes; denied requests; GitHub unreachable while older results are shown; and repositories that failed while the rest refreshed, with `Retry`.
- For you shows an info banner when review requests are hidden because their repository is not watched, with `Watch repository`.
- The token dialog shows errors under the field they concern: an invalid owner name or a token GitHub rejected. Settings rows show token problems with `Replace`.

## Loading state

GitHub fetches run as background tasks, one job at a time, so the window keeps rendering and never shows the OS busy cursor. Inside a job, tokens, For you sources, and watched repositories are fetched concurrently. Fetched data replaces the visible lists only when a fetch completes.

- First launch shows skeleton rows with a step count until watched activity loads; the rest of the startup load continues in the background.
- `Refresh`, Watch, and token changes show a modal loading dialog with a spinner, the current step, a determinate progress bar, and `Cancel`. The dialog appears only after 300 ms and then stays at least 500 ms.
- Auto refresh and token verification do not block the window; auto refresh shows a linear progress bar under the page header.
- `Refresh` is disabled while any fetch is running. Control-file commands wait until the fetch ends, except `quit`, `cancel`, and `undo`.
- A fetch that takes longer than 90 seconds is abandoned and reported in a timeout dialog. Cancel abandons it at once and keeps the previous results. An abandoned fetch that finishes later is ignored.

## Motion

- Page change: the workspace content fades in and rises 8 px over 150 ms.
- Snackbar: rises 16 px and fades in over 250 ms, stays 5 s, fades out over 150 ms.
- Loading dialog: the scrim and dialog fade in over 200 ms.
- New or updated rows after a refresh keep a blue tint for 1.5 s, then fade out over 0.6 s. The first load highlights nothing.

## Notifications

When auto refresh finds new or updated items, up to three post individual notifications: the repository (or the For you reason) as title, `#number title` as subtitle, and the author or repository as body. More than three post one summary grouped by repository. Manual refreshes and muted items never notify.

## Visual structure

The native shell uses the GitHub Primer light palette: a quiet navigation rail with unread badges, and one rounded workspace with a page header, a toolbar, and the list. The design canvas that this layout follows is kept as a Claude Design artifact outside the repository.

Screenshot evidence is stored under `artifacts/macos/redesign/`.
