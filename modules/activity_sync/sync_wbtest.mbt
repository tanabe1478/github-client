///|
test "parse_activity_url accepts pull request and issue URLs" {
  guard parse_activity_url("https://github.com/owner/app/pull/12")
    is Ok((repository, number)) else {
    fail("expected a pull request URL to parse")
  }
  assert_eq(repository.key(), "owner/app")
  assert_eq(number, 12)
  guard parse_activity_url(
      "https://github.com/owner/app/issues/34#issuecomment-1",
    )
    is Ok((_, issue_number)) else {
    fail("expected an issue URL to parse")
  }
  assert_eq(issue_number, 34)
}

///|
test "parse_activity_url rejects other URLs" {
  assert_true(
    parse_activity_url("https://example.com/owner/app/pull/1") is Err(_),
  )
  assert_true(
    parse_activity_url("https://github.com/owner/app/commit/abc") is Err(_),
  )
  assert_true(
    parse_activity_url("https://github.com/owner/app/pull/x") is Err(_),
  )
}

///|
test "resolve_token prefers the owner scope, then the default token" {
  let tokens = Map([("default", "d"), ("acme", "a")])
  assert_eq(resolve_token(tokens, Map([]), Map([]), "Acme", "app"), Some("a"))
  assert_eq(resolve_token(tokens, Map([]), Map([]), "other", "app"), Some("d"))
  assert_eq(
    resolve_token(tokens, Map([("other/app", "acme")]), Map([]), "other", "app"),
    Some("a"),
  )
}

///|
test "a review request is kept until the viewer reviews or it closes" {
  let logins = ["tanabe1478"]
  assert_true(keeps_review_request(true, ["teammate"], logins))
  assert_false(keeps_review_request(true, ["teammate", "tanabe1478"], logins))
  assert_false(keeps_review_request(false, [], logins))
}

///|
test "utc_days_ago formats midnight UTC days before now" {
  // 2026-10-06T05:30:00Z
  inspect(utc_days_ago(1791264600000L, 30), content="2026-09-06T00:00:00Z")
  inspect(utc_days_ago(1791264600000L, 0), content="2026-10-06T00:00:00Z")
  // 2024-03-01T00:00:00Z crosses a leap day.
  inspect(utc_days_ago(1709251200000L, 1), content="2024-02-29T00:00:00Z")
  inspect(utc_days_ago(0L, 0), content="1970-01-01T00:00:00Z")
}

///|
test "closed_mentions keeps open items and only the chosen closed states" {
  inspect(
    closed_mentions("2026-09-06T00:00:00Z", merged=false, closed=false) is None,
    content="true",
  )
  guard closed_mentions("2026-09-06T00:00:00Z", merged=true, closed=false)
    is Some(merged_only) else {
    fail("merged should enable closed mentions")
  }
  assert_eq(
    [@github_api.Open, Merged, Closed].map(state => merged_only.keeps(state)),
    [true, true, false],
  )
  guard closed_mentions("2026-09-06T00:00:00Z", merged=false, closed=true)
    is Some(closed_only) else {
    fail("closed should enable closed mentions")
  }
  assert_eq(
    [@github_api.Open, Merged, Closed].map(state => closed_only.keeps(state)),
    [true, false, true],
  )
}
