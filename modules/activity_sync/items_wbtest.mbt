///|
test "personal_items labels closed and merged mentions after their reasons" {
  let json : Json = [
    {
      "number": 3,
      "title": "Merged pull request",
      "html_url": "https://github.com/acme/app/pull/3",
      "repository_url": "https://api.github.com/repos/acme/app",
      "user": { "login": "alice" },
      "updated_at": "2026-10-01T00:00:00Z",
      "state": "closed",
      "pull_request": { "merged_at": "2026-10-01T00:00:00Z" },
    },
    {
      "number": 2,
      "title": "Closed issue",
      "html_url": "https://github.com/acme/app/issues/2",
      "repository_url": "https://api.github.com/repos/acme/app",
      "user": { "login": "alice" },
      "updated_at": "2026-10-01T00:00:00Z",
      "state": "closed",
    },
    {
      "number": 1,
      "title": "Open issue",
      "html_url": "https://github.com/acme/app/issues/1",
      "repository_url": "https://api.github.com/repos/acme/app",
      "user": { "login": "alice" },
      "updated_at": "2026-10-01T00:00:00Z",
      "state": "open",
    },
  ]
  guard @github_api.decode_subscribed_issues(json) is Ok(mentions) else {
    fail("mentions should decode")
  }
  let items = personal_items(
    [],
    [],
    mentions,
    [mentions[0]],
    [@domain.RepositoryRef::new("acme", "app")],
    Map([]),
    watched_only=true,
  )
  assert_eq(items.map(item => item.reasons), [
    ["Mentioned", "Subscribed", "Merged"],
    ["Mentioned", "Closed"],
    ["Mentioned"],
  ])
}
