///|
fn sample_item(
  number : Int,
  repository? : String = "owner/app",
  author? : String = "octocat",
  updated_at? : String = "2026-09-29T01:00:00Z",
  kind? : InboxItemKind = PullRequest,
  title? : String = "Change",
  reasons? : Array[String] = [],
) -> ActivityItem {
  {
    url: "https://github.com/\{repository}/pull/\{number}",
    repository,
    number,
    title,
    author,
    updated_at,
    kind,
    draft: false,
    reasons,
  }
}

///|
fn row_labels(rows : Array[ActivityRow]) -> Array[String] {
  rows.map(row => {
    match row {
      GroupHeader(repository) => "group \{repository}"
      Item(item, nested~, ..) =>
        if nested {
          "  #\{item.number}"
        } else {
          "#\{item.number}"
        }
      Bundle(items~, expanded~, ..) => "bundle \{items.length()} \{expanded}"
    }
  })
}

///|
test "rows are grouped by repository, newest first" {
  let items = [
    sample_item(1, repository="owner/app", updated_at="2026-09-01T00:00:00Z"),
    sample_item(2, repository="owner/lib", updated_at="2026-09-03T00:00:00Z"),
    sample_item(3, repository="owner/app", updated_at="2026-09-02T00:00:00Z"),
  ]
  let rows = build_activity_rows(
    items,
    [],
    Map([]),
    ActivityFilter::default(),
    Map([]),
    ByRepository,
  )
  assert_eq(row_labels(rows), [
    "group owner/lib", "#2", "group owner/app", "#3", "#1",
  ])
}

///|
test "two or more bot updates in a repository collapse into a bundle" {
  let items = [
    sample_item(1, author="dependabot[bot]", updated_at="2026-09-02T00:00:00Z"),
    sample_item(2, author="octocat", updated_at="2026-09-03T00:00:00Z"),
    sample_item(3, author="dependabot[bot]", updated_at="2026-09-01T00:00:00Z"),
  ]
  let collapsed = build_activity_rows(
    items,
    [],
    Map([]),
    ActivityFilter::default(),
    Map([]),
    ByRepository,
  )
  assert_eq(row_labels(collapsed), ["group owner/app", "#2", "bundle 2 false"])
  let expanded = build_activity_rows(
    items,
    [],
    Map([]),
    ActivityFilter::default(),
    Map([(bundle_key("owner/app", "dependabot[bot]"), true)]),
    ByRepository,
  )
  assert_eq(row_labels(expanded), [
    "group owner/app", "#2", "bundle 2 true", "  #1", "  #3",
  ])
}

///|
test "a single bot update stays a normal row" {
  let rows = build_activity_rows(
    [sample_item(1, author="dependabot[bot]")],
    [],
    Map([]),
    ActivityFilter::default(),
    Map([]),
    ByRepository,
  )
  assert_eq(row_labels(rows), ["group owner/app", "#1"])
}

///|
test "done items are hidden unless show_done is set" {
  let item = sample_item(1)
  let markers = [ReadMarker::new(item.url, item.updated_at)]
  let hidden = build_activity_rows(
    [item],
    markers,
    Map([]),
    ActivityFilter::default(),
    Map([]),
    Flat,
  )
  assert_eq(hidden.length(), 0)
  let shown = build_activity_rows(
    [item],
    markers,
    Map([]),
    { ..ActivityFilter::default(), show_done: true, },
    Map([]),
    Flat,
  )
  guard shown is [Item(_, read~, ..)] else { fail("expected one item") }
  assert_true(read)
}

///|
test "filters by kind, repository, reason, and query" {
  let pr = sample_item(10, title="Fix login", reasons=["Assigned"])
  let issue = sample_item(
    11,
    repository="owner/lib",
    kind=Issue,
    author="hubot",
    title="Crash on start",
  )
  let base = ActivityFilter::default()
  assert_true(matches_filter(pr, { ..base, kind: PullRequestsOnly, }, false))
  assert_false(
    matches_filter(issue, { ..base, kind: PullRequestsOnly, }, false),
  )
  assert_true(
    matches_filter(issue, { ..base, repository: "OWNER/lib", }, false),
  )
  assert_false(matches_filter(pr, { ..base, repository: "owner/lib", }, false))
  assert_true(matches_filter(pr, { ..base, reason: "Assigned", }, false))
  assert_false(matches_filter(issue, { ..base, reason: "Assigned", }, false))
  assert_true(matches_filter(pr, { ..base, query: "login", }, false))
  assert_true(matches_filter(issue, { ..base, query: "#11", }, false))
  assert_false(matches_filter(pr, { ..base, query: "#11", }, false))
  assert_true(matches_filter(issue, { ..base, query: "@hub", }, false))
  assert_false(matches_filter(pr, { ..base, query: "@hub", }, false))
}

///|
test "dependency update summary keeps package and target version" {
  assert_eq(
    dependency_update_summary("chore(deps): bump sentry from 8.50.1 to 8.55.0"),
    "sentry 8.55.0",
  )
  assert_eq(
    dependency_update_summary(
      "chore(deps): bump com.microsoft.playwright:playwright from 1.61.0 to 1.62.0",
    ),
    "com.microsoft.playwright:playwright 1.62.0",
  )
  assert_eq(dependency_update_summary("Update README"), "Update README")
}

///|
test "short date formats an ISO timestamp" {
  assert_eq(short_date("2026-09-29T06:59:03Z"), "Sep 29")
  assert_eq(short_date("2026-01-05T00:00:00Z"), "Jan 5")
  assert_eq(short_date("unknown"), "unknown")
}

///|
test "unwatched repositories are counted once per item" {
  let watched = [RepositoryRef::new("owner", "app")]
  let items = [
    sample_item(1, repository="owner/app"),
    sample_item(2, repository="org/api"),
    sample_item(2, repository="org/api"),
    sample_item(3, repository="org/api"),
  ]
  assert_eq(unwatched_repositories(items, watched), [("org/api", 2)])
}
