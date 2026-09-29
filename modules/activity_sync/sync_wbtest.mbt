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
