///|
/// One issue or pull request as the activity lists show it.
pub(all) struct ActivityItem {
  url : String
  repository : String
  number : Int
  title : String
  author : String
  updated_at : String
  kind : InboxItemKind
  draft : Bool
  reasons : Array[String]
}

///|
pub(all) enum KindFilter {
  AllKinds
  PullRequestsOnly
  IssuesOnly
}

///|
/// View filters chosen in the toolbar. Empty strings mean "no filter".
pub(all) struct ActivityFilter {
  kind : KindFilter
  repository : String
  query : String
  reason : String
  show_done : Bool
}

///|
pub fn ActivityFilter::default() -> ActivityFilter {
  { kind: AllKinds, repository: "", query: "", reason: "", show_done: false, }
}

///|
pub(all) enum ActivityRow {
  /// Repository section header.
  GroupHeader(String)
  /// An activity row. `nested` rows belong to the bundle above them.
  Item(ActivityItem, read~ : Bool, saved~ : Bool, nested~ : Bool)
  /// Several updates from one dependency bot in one repository.
  Bundle(
    key~ : String,
    repository~ : String,
    author~ : String,
    items~ : Array[ActivityItem],
    expanded~ : Bool,
    unread~ : Int
  )
}

///|
pub(all) enum RowLayout {
  /// Section headers per repository; bot updates are bundled.
  ByRepository
  /// One flat list, newest first.
  Flat
}

///|
pub fn is_dependency_bot(author : String) -> Bool {
  author == "dependabot[bot]" || author == "renovate[bot]"
}

///|
fn contains_ignore_case(haystack : String, needle : String) -> Bool {
  needle == "" || haystack.to_lower().contains(needle.to_lower())
}

///|
/// Matches `#123`, `@author`, or text in the title.
fn matches_query(item : ActivityItem, query : String) -> Bool {
  let trimmed = query.trim().to_owned()
  if trimmed == "" {
    return true
  }
  if trimmed.has_prefix("#") {
    return "#\{item.number}".has_prefix(trimmed)
  }
  if trimmed.has_prefix("@") {
    return contains_ignore_case("@" + item.author, trimmed)
  }
  contains_ignore_case(item.title, trimmed) ||
  contains_ignore_case("#\{item.number}", trimmed)
}

///|
pub fn matches_filter(
  item : ActivityItem,
  filter : ActivityFilter,
  read : Bool,
) -> Bool {
  if read && !filter.show_done {
    return false
  }
  let kind_matches = match filter.kind {
    AllKinds => true
    PullRequestsOnly => item.kind is PullRequest
    IssuesOnly => item.kind is Issue
  }
  kind_matches &&
  (
    filter.repository == "" ||
    item.repository.to_lower() == filter.repository.to_lower()
  ) &&
  (filter.reason == "" || item.reasons.contains(filter.reason)) &&
  matches_query(item, filter.query)
}

///|
pub fn bundle_key(repository : String, author : String) -> String {
  "\{repository}|\{author}"
}

///|
/// Builds the rows a list shows: filtered, newest first, and for
/// `ByRepository` grouped under repository headers with bot updates bundled.
pub fn build_activity_rows(
  items : Array[ActivityItem],
  markers : Array[ReadMarker],
  saved : Map[String, Bool],
  filter : ActivityFilter,
  expanded : Map[String, Bool],
  layout : RowLayout,
) -> Array[ActivityRow] {
  let visible = items
    .filter(item => {
      matches_filter(
        item,
        filter,
        activity_is_read(markers, item.url, item.updated_at),
      )
    })
    .copy()
  // Newest first; the sort is stable so equal timestamps keep API order.
  visible.sort_by((a, b) => b.updated_at.compare(a.updated_at))
  let row_of = (item : ActivityItem, nested : Bool) => {
    Item(
      item,
      read=activity_is_read(markers, item.url, item.updated_at),
      saved=saved.contains(item.url),
      nested~,
    )
  }
  let rows : Array[ActivityRow] = []
  match layout {
    Flat =>
      for item in visible {
        rows.push(row_of(item, false))
      }
    ByRepository => {
      let repositories : Array[String] = []
      for item in visible {
        if !repositories.contains(item.repository) {
          repositories.push(item.repository)
        }
      }
      for repository in repositories {
        rows.push(GroupHeader(repository))
        let repo_items = visible.filter(item => item.repository == repository)
        let bot_counts : Map[String, Int] = Map([])
        for item in repo_items {
          if is_dependency_bot(item.author) {
            bot_counts.set(
              item.author,
              bot_counts.get(item.author).unwrap_or(0) + 1,
            )
          }
        }
        let emitted : Map[String, Bool] = Map([])
        for item in repo_items {
          let bundled = is_dependency_bot(item.author) &&
            bot_counts.get(item.author).unwrap_or(0) >= 2
          if !bundled {
            rows.push(row_of(item, false))
            continue
          }
          if emitted.contains(item.author) {
            continue
          }
          emitted.set(item.author, true)
          let bundle_items = repo_items.filter(entry => {
            entry.author == item.author
          })
          let key = bundle_key(repository, item.author)
          let is_expanded = expanded.contains(key)
          let unread = bundle_items
            .filter(entry => {
              !activity_is_read(markers, entry.url, entry.updated_at)
            })
            .length()
          rows.push(
            Bundle(
              key~,
              repository~,
              author=item.author,
              items=bundle_items,
              expanded=is_expanded,
              unread~,
            ),
          )
          if is_expanded {
            for entry in bundle_items {
              rows.push(row_of(entry, true))
            }
          }
        }
      }
    }
  }
  rows
}

///|
/// "chore(deps): bump sentry from 8.50.1 to 8.55.0" becomes "sentry 8.55.0".
pub fn dependency_update_summary(title : String) -> String {
  guard title.find("bump ") is Some(start) else { return title }
  let rest = title[start + 5:].to_owned()
  guard rest.find(" from ") is Some(from_index) else { return title }
  let dependency = rest[:from_index].to_owned()
  guard rest.rev_find(" to ") is Some(to_index) else { return dependency }
  let version = rest[to_index + 4:].trim().to_owned()
  "\{dependency} \{version}"
}

///|
let month_names : Array[String] = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

///|
fn two_digits(view : StringView) -> Int? {
  let chars = view.to_owned().to_array()
  guard chars.length() == 2 else { return None }
  let mut value = 0
  for character in chars {
    guard character >= '0' && character <= '9' else { return None }
    value = value * 10 + (character.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
/// "2026-09-29T06:59:03Z" becomes "Sep 29".
pub fn short_date(timestamp : String) -> String {
  guard timestamp.length() >= 10 else { return timestamp }
  guard two_digits(timestamp[5:7]) is Some(month) &&
    two_digits(timestamp[8:10]) is Some(day) &&
    month >= 1 &&
    month <= 12 else {
    return timestamp
  }
  "\{month_names[month - 1]} \{day}"
}

///|
/// Repositories outside the watched set that still hold items for the
/// viewer, with how many, in first-seen order.
pub fn unwatched_repositories(
  items : Array[ActivityItem],
  watched : Array[RepositoryRef],
) -> Array[(String, Int)] {
  let order : Array[String] = []
  let counts : Map[String, Int] = Map([])
  let seen : Map[String, Bool] = Map([])
  for item in items {
    if seen.contains(item.url) ||
      repository_is_watched(watched, item.repository) {
      continue
    }
    seen.set(item.url, true)
    if !counts.contains(item.repository) {
      order.push(item.repository)
    }
    counts.set(item.repository, counts.get(item.repository).unwrap_or(0) + 1)
  }
  order.map(repository => (repository, counts.get(repository).unwrap_or(0)))
}
