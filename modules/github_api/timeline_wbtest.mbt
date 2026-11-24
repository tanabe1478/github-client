///|
test "decode_timeline reads actors, review times, commits, and grouped comments" {
  let json = @json.parse(
    (
      #|[
      #|  {"event":"review_requested","actor":{"login":"author"},"created_at":"2026-11-24T02:10:35Z"},
      #|  {"event":"reviewed","user":{"login":"viewer"},"submitted_at":"2026-11-24T02:41:44Z","state":"approved"},
      #|  {"event":"reviewed","user":{"login":"viewer"},"submitted_at":null,"state":"pending"},
      #|  {"event":"committed","sha":"abc","author":{"name":"A","date":"2026-11-24T01:00:00Z"},"committer":{"name":"A","date":"2026-11-24T01:54:03Z"}},
      #|  {"event":"line-commented","comments":[{"user":{"login":"other"},"created_at":"2026-11-24T03:00:00Z"}]}
      #|]
    ),
  )
  guard decode_timeline(json) is Ok(entries) else {
    fail("timeline should decode")
  }
  assert_eq(entries, [
    { at: "2026-11-24T02:10:35Z", actor: "author", commit: "", },
    { at: "2026-11-24T02:41:44Z", actor: "viewer", commit: "", },
    { at: "2026-11-24T01:54:03Z", actor: "", commit: "abc", },
    { at: "2026-11-24T03:00:00Z", actor: "other", commit: "", },
  ])
}

///|
test "decode_timeline rejects a non-array response" {
  assert_true(decode_timeline(@json.parse("{}")) is Err(_))
}

///|
test "decode_commit_authors maps SHAs to linked accounts only" {
  let json = @json.parse(
    (
      #|[{"sha":"abc","author":{"login":"viewer"}},{"sha":"def","author":null}]
    ),
  )
  guard decode_commit_authors(json) is Ok(authors) else {
    fail("commits should decode")
  }
  assert_eq(authors.get("abc"), Some("viewer"))
  assert_eq(authors.get("def"), None)
}
