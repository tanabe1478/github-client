# Jasper feature gap analysis

This document compares this project with [jasperapp/jasper](https://github.com/jasperapp/jasper). The assessment uses Jasper `master` commit `a7cbefefaa79dd764099217a3946b8210423b0ed`, tagged `v2.0.0`.

Jasper is a mature, general-purpose GitHub issue reader centered on configurable streams. This project is a Windows-first native activity inbox deliberately scoped to explicitly Watched repositories and relevant dependency impact.

## Feature matrix

| Area | Jasper | MoonBit GitHub Client |
|---|---|---|
| Repository scope | GitHub Watching, organizations, teams, and custom queries | Explicitly registered Watched repositories |
| Personal activity | Me, Team, Watching, and Subscription streams | Mentions, assignments, review requests, and subscriptions from Watched repositories only |
| Issue and PR states | Open, closed, merged, draft, and conflict metadata | Open issues and pull requests; draft indication |
| Refresh | Background stream polling with adaptive rate-limit handling | Startup synchronization only |
| Local history | SQLite stores issues, metadata, streams, and state | Repository list and read markers are persisted; fetched activity remains in memory |
| Read state | Revision-aware read state, explicit unread, bulk read, unread navigation, GitHub notification sync | Revision-aware individual read/unread controls and unread-only filter |
| Filtering | Saved multi-query streams and extensive local query language | Unread filter and repository suggestion text filter |
| Sorting | Read/update/create/repository/author and other sort keys | GitHub API response order |
| Bookmark/archive | Supported | Not implemented |
| Detail reader | Embedded BrowserView with comment highlighting and body diffs | Explicitly opens the item in the external browser |
| Projects | GitHub Projects and Projects v2 | Not implemented |
| Desktop notifications | Per-stream notification settings, silent mode, badge, click navigation | Not implemented |
| Keyboard navigation | Next/previous item and unread item, jump navigation, state/filter shortcuts | Not implemented |
| GitHub Enterprise | Supported | GitHub.com only |
| Accounts/authentication | OAuth or PAT, multiple accounts | One fine-grained PAT |
| Window state | Restores window and pane geometry | Not implemented |
| UI stack | Electron, React, and BrowserView | GLFW, OpenGL 3, and Dear ImGui native rendering |
| Credential storage | Access token is serialized with user preferences | PAT is encrypted using Windows DPAPI |

## Major gaps

### Configurable streams and filters

Jasper's central feature is its stream system. It combines GitHub queries and local filters such as:

```text
repo:nodejs/node is:issue label:bug
assignee:me is:unread
review-requested:me is:pr
```

Its local filter implementation covers issue/PR type, open/closed, read/unread, bookmark/archive, merged/draft/private state, title, author, assignee, involvement, mentions, teams, reviews, labels, milestones, and Project fields.

A complete DSL would broaden this project's scope substantially. A smaller saved-view model based on repository, activity reason, issue/PR kind, read state, and update time better matches the Watched repository product focus.

### Background synchronization

Jasper schedules enabled streams in a polling queue and increases its interval when rate limits are exhausted. This project currently performs network synchronization before displaying the window. Moving refresh into background tasks is the most important practical gap.

### Local activity database

Jasper stores issue/PR bodies and metadata in SQLite. That enables offline lists, closed-item history, local filtering, body snapshots, and revision-aware presentation. This project currently persists only registered repositories and URL/read-revision markers.

### Read-state depth

Both applications use the same fundamental rule:

```text
read_at >= updated_at
```

Jasper additionally supports bulk read operations, next/previous unread navigation, intentional-unread timestamps, body snapshots, new-comment highlighting, self-update suppression, and synchronization with GitHub Notifications.

### Detail reading

Jasper embeds GitHub in a BrowserView and augments the DOM to highlight comments newer than the previous read time, show issue-body differences, and navigate review comments. This project intentionally does not use a WebView as its main UI. Comparable functionality should therefore be implemented as a native detail screen backed by REST timeline/comment data, while retaining an explicit external-browser action.

## Current advantages

- Native self-rendered UI without Electron or a primary WebView.
- Windows DPAPI-backed PAT encryption instead of preference-file token serialization.
- Fine-grained PAT and selected-repository access model.
- Explicit controls for primary and state-changing actions.
- Personal activity noise is constrained to Watched repositories.
- Product modules and domain behavior have automated native tests.
- Planned dependency-impact relevance is a differentiator not present in Jasper.

## Recommended implementation order

1. Background refresh, manual refresh, rate-limit state, and ETag support.
2. A local activity store retaining revisions and closed-item history.
3. Desktop notifications scoped to relevant unread Watched activity.
4. Bulk read, unread badges, and next-unread navigation.
5. A native issue/PR detail screen with labels, assignees, reviewers, comments, and timeline.
6. Lightweight saved views rather than Jasper's full stream query language.

GitHub Enterprise, multiple accounts, Projects integration, embedded browsing, and custom themes should remain lower priority unless product requirements change.

## Jasper implementation references

- [`StreamSetup.ts`](https://github.com/jasperapp/jasper/blob/master/src/Renderer/Repository/Setup/StreamSetup.ts)
- [`FilterSQLRepo.ts`](https://github.com/jasperapp/jasper/blob/master/src/Renderer/Repository/FilterSQLRepo.ts)
- [`StreamPolling.ts`](https://github.com/jasperapp/jasper/blob/master/src/Renderer/Repository/Polling/StreamPolling.ts)
- [`IssueRepo.ts`](https://github.com/jasperapp/jasper/blob/master/src/Renderer/Repository/IssueRepo.ts)
- [`GitHubNotificationPolling.ts`](https://github.com/jasperapp/jasper/blob/master/src/Renderer/Repository/GitHubNotificationPolling.ts)
- [`NotificationFragment.tsx`](https://github.com/jasperapp/jasper/blob/master/src/Renderer/Fragment/Other/NotificationFragment.tsx)
- [`MainWindowMenu.ts`](https://github.com/jasperapp/jasper/blob/master/src/Main/Window/MainWindow/MainWindowMenu.ts)
- [`UserPrefService.ts`](https://github.com/jasperapp/jasper/blob/master/src/Main/Service/UserPrefService.ts)
