///|
test "read state codec round trips" {
  let encoded = encode([
    @domain.ReadMarker::new(
      "https://github.com/acme/app/issues/1", "2026-01-01T10:00:00Z",
    ),
  ])
  inspect(
    encoded,
    content="v1\n2026-01-01T10:00:00Z\thttps://github.com/acme/app/issues/1\n",
  )
  guard decode(encoded) is Ok(markers) else { fail("read state should decode") }
  inspect(markers.length(), content="1")
  inspect(markers[0].url(), content="https://github.com/acme/app/issues/1")
}

///|
test "read state store rejects malformed entries" {
  guard decode("v1\nmissing-tab\n") is Err(malformed) else {
    fail("malformed marker should fail")
  }
  inspect(malformed, content="invalid read marker at line 2")
  guard decode("v2\n") is Err(version) else {
    fail("unsupported version should fail")
  }
  inspect(version, content="unsupported read state store format")
}
