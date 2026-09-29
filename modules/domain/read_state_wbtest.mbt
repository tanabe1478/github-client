///|
test "read marker becomes unread when GitHub activity is updated" {
  let url = "https://github.com/acme/app/issues/1"
  let markers = mark_activity_read([], url, "2026-01-01T10:00:00Z")
  assert_true(activity_is_read(markers, url, "2026-01-01T10:00:00Z"))
  assert_false(activity_is_read(markers, url, "2026-01-01T11:00:00Z"))
}

///|
test "activity can be explicitly marked unread" {
  let url = "https://github.com/acme/app/pull/2"
  let read = mark_activity_read([], url, "2026-01-01T10:00:00Z")
  let unread = mark_activity_unread(read, url)
  assert_false(activity_is_read(unread, url, "2026-01-01T10:00:00Z"))
}

///|
test "marking activity read replaces its previous marker" {
  let url = "https://github.com/acme/app/issues/3"
  let first = mark_activity_read([], url, "2026-01-01T10:00:00Z")
  let second = mark_activity_read(first, url, "2026-01-01T12:00:00Z")
  inspect(second.length(), content="1")
  inspect(second[0].read_at(), content="2026-01-01T12:00:00Z")
}

///|
test "watched repository matching is case insensitive" {
  let repositories = [RepositoryRef::new("Acme", "Desktop")]
  assert_true(repository_is_watched(repositories, "acme/desktop"))
  assert_false(repository_is_watched(repositories, "external/project"))
}

///|
test "prune_markers keeps only listed URLs" {
  let markers = [
    ReadMarker::new("https://github.com/o/a/pull/1", "2026-01-01T00:00:00Z"),
    ReadMarker::new("https://github.com/o/a/pull/2", "2026-01-01T00:00:00Z"),
  ]
  let kept = prune_markers(
    markers,
    Map([("https://github.com/o/a/pull/2", true)]),
  )
  assert_eq(kept.map(marker => marker.url()), ["https://github.com/o/a/pull/2"])
}

///|
test "read_index looks markers up by URL" {
  let index = read_index([
    ReadMarker::new("https://github.com/o/a/pull/1", "2026-02-01T00:00:00Z"),
  ])
  assert_true(
    is_read_in(index, "https://github.com/o/a/pull/1", "2026-01-01T00:00:00Z"),
  )
  assert_false(
    is_read_in(index, "https://github.com/o/a/pull/1", "2026-03-01T00:00:00Z"),
  )
  assert_false(
    is_read_in(index, "https://github.com/o/a/pull/9", "2026-01-01T00:00:00Z"),
  )
}
