///|
test "personal search response identifies issue and repository" {
  let json = @json.parse(
    "{\"items\":[{\"number\":12,\"title\":\"Please investigate\",\"html_url\":\"https://github.com/acme/app/issues/12\",\"repository_url\":\"https://api.github.com/repos/acme/app\",\"user\":{\"login\":\"alice\"},\"updated_at\":\"2026-01-01T00:00:00Z\"}]}",
  )
  guard decode_personal_activity_search(json) is Ok(items) else {
    fail("search response should decode")
  }
  inspect(items.length(), content="1")
  inspect(items[0].repository(), content="acme/app")
  guard items[0].kind() is ActivityKind::Issue else {
    fail("item should be an issue")
  }
}

///|
test "personal search response identifies pull request" {
  let json = @json.parse(
    "{\"items\":[{\"number\":7,\"title\":\"Review this\",\"html_url\":\"https://github.com/acme/app/pull/7\",\"repository_url\":\"https://api.github.com/repos/acme/app\",\"user\":{\"login\":\"bob\"},\"updated_at\":\"2026-01-01T00:00:00Z\",\"pull_request\":{}}]}",
  )
  guard decode_personal_activity_search(json) is Ok(items) else {
    fail("search response should decode")
  }
  guard items[0].kind() is ActivityKind::PullRequest else {
    fail("item should be a pull request")
  }
}

///|
test "subscribed issue response decodes array payload" {
  let json = @json.parse(
    "[{\"number\":3,\"title\":\"Subscribed\",\"html_url\":\"https://github.com/acme/app/issues/3\",\"repository_url\":\"https://api.github.com/repos/acme/app\",\"user\":{\"login\":\"carol\"},\"updated_at\":\"2026-01-01T00:00:00Z\"}]",
  )
  guard decode_subscribed_issues(json) is Ok(items) else {
    fail("subscribed response should decode")
  }
  inspect(items[0].title(), content="Subscribed")
}
