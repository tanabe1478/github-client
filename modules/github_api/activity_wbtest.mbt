///|
test "issue endpoint excludes pull request shaped entries" {
  let json = @json.parse(
    "[{\"number\":1,\"title\":\"Issue\",\"html_url\":\"https://example.test/issues/1\",\"user\":{\"login\":\"alice\"},\"updated_at\":\"2026-01-01T00:00:00Z\"},{\"number\":2,\"title\":\"PR in issues endpoint\",\"html_url\":\"https://example.test/pull/2\",\"user\":{\"login\":\"bob\"},\"updated_at\":\"2026-01-02T00:00:00Z\",\"pull_request\":{}}]",
  )
  guard decode_issues(json, "acme/app") is Ok(issues) else {
    fail("issue response should decode")
  }
  inspect(issues.length(), content="1")
  inspect(issues[0].repository(), content="acme/app")
  inspect(issues[0].title(), content="Issue")
}

///|
test "pull request response decodes display fields" {
  let json = @json.parse(
    "[{\"number\":7,\"title\":\"Improve startup\",\"html_url\":\"https://example.test/pull/7\",\"user\":{\"login\":\"octocat\"},\"updated_at\":\"2026-01-03T00:00:00Z\",\"draft\":true}]",
  )
  guard decode_pull_requests(json, "acme/app") is Ok(pulls) else {
    fail("pull request response should decode")
  }
  inspect(pulls.length(), content="1")
  inspect(pulls[0].number(), content="7")
  inspect(pulls[0].author(), content="octocat")
  assert_true(pulls[0].is_draft())
}
