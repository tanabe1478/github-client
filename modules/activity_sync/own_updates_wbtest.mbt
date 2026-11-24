///|
fn entry(at : String, actor : String) -> @github_api.TimelineEntry {
  { at, actor, commit: "", }
}

///|
test "utc_seconds reads GitHub timestamps" {
  assert_eq(utc_seconds("1970-01-01T00:00:00Z"), Some(0L))
  assert_eq(utc_seconds("2026-11-24T02:41:44Z"), Some(1795488104L))
  assert_eq(utc_seconds("not a time"), None)
}

///|
test "the viewer's own approval is not news" {
  let entries = [
    entry("2026-11-24T01:29:47Z", "teammate"),
    entry("2026-11-24T02:41:44Z", "viewer"),
  ]
  assert_true(
    changed_only_by(
      entries,
      Some("2026-11-24T01:29:47Z"),
      "author",
      "2026-11-24T02:41:44Z",
      ["viewer"],
    ),
  )
}

///|
test "someone else's change after the last seen revision is news" {
  let entries = [
    entry("2026-11-24T02:41:44Z", "viewer"),
    entry("2026-11-24T04:59:33Z", "teammate"),
  ]
  assert_false(
    changed_only_by(
      entries,
      Some("2026-11-24T01:00:00Z"),
      "author",
      "2026-11-24T04:59:33Z",
      ["viewer"],
    ),
  )
}

///|
test "an update no timeline change explains is news" {
  let entries = [entry("2026-11-24T02:41:44Z", "viewer")]
  assert_false(
    changed_only_by(
      entries,
      Some("2026-11-24T01:00:00Z"),
      "author",
      "2026-11-24T03:00:00Z",
      ["viewer"],
    ),
  )
  assert_false(
    changed_only_by(
      [],
      Some("2026-11-24T01:00:00Z"),
      "author",
      "2026-11-24T03:00:00Z",
      ["viewer"],
    ),
  )
  // A few seconds of drift between the event and updated_at is allowed.
  assert_true(
    changed_only_by(
      entries,
      Some("2026-11-24T01:00:00Z"),
      "author",
      "2026-11-24T02:41:47Z",
      ["viewer"],
    ),
  )
}

///|
test "a commit with no linked account is news" {
  let entries : Array[@github_api.TimelineEntry] = [
    { at: "2026-11-24T02:00:00Z", actor: "", commit: "abc", },
  ]
  assert_false(
    changed_only_by(
      entries,
      Some("2026-11-24T01:00:00Z"),
      "viewer",
      "2026-11-24T02:00:00Z",
      ["viewer"],
    ),
  )
}

///|
test "a new item counts as the viewer's only when the viewer opened it" {
  assert_true(
    changed_only_by([], None, "viewer", "2026-11-24T02:00:00Z", ["viewer"]),
  )
  assert_false(
    changed_only_by([], None, "author", "2026-11-24T02:00:00Z", ["viewer"]),
  )
  assert_false(
    changed_only_by(
      [entry("2026-11-24T02:00:00Z", "teammate")],
      None,
      "viewer",
      "2026-11-24T02:00:00Z",
      ["viewer"],
    ),
  )
}
