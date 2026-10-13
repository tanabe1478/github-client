///|
test "repository store codec round trips" {
  let options : Map[String, @domain.WatchOptions] = Map([])
  options.set("pnpm/pnpm", {
    pull_requests: false,
    issues: false,
    releases: true,
    for_you: false,
    release_notify: MajorOnly,
  })
  let encoded = encode(
    [
      @domain.RepositoryRef::new("tanabe1478", "github-client"),
      @domain.RepositoryRef::new("pnpm", "pnpm"),
    ],
    options,
  )
  inspect(
    encoded,
    content="v2\ntanabe1478/github-client\tpull-requests,issues,for-you\treleases=major-minor\npnpm/pnpm\treleases\treleases=major\n",
  )
  guard decode_entries(encoded) is Ok((repositories, decoded)) else {
    fail("repository store should decode")
  }
  inspect(
    repositories.map(repository => repository.key()).join(","),
    content="tanabe1478/github-client,pnpm/pnpm",
  )
  assert_eq(decoded.get("pnpm/pnpm"), options.get("pnpm/pnpm"))
  assert_eq(
    decoded.get("tanabe1478/github-client"),
    Some(@domain.WatchOptions::default()),
  )
}

///|
test "version 1 files keep watching pull requests, issues, and For you" {
  guard decode_entries("v1\nocornut/imgui\n") is Ok((repositories, options)) else {
    fail("version 1 should decode")
  }
  assert_eq(repositories.length(), 1)
  assert_eq(options.get("ocornut/imgui"), Some(@domain.WatchOptions::default()))
}

///|
test "repository store rejects malformed entries" {
  guard decode("v1\nmissing-owner-separator\n") is Err(malformed) else {
    fail("malformed repository should fail")
  }
  inspect(malformed, content="invalid repository at line 2")
  guard decode("v3\nacme/repo\n") is Err(version) else {
    fail("unsupported version should fail")
  }
  inspect(version, content="unsupported repository store format")
  guard decode("v2\nacme/repo\tcommits\n") is Err(kind) else {
    fail("unknown kinds should fail")
  }
  inspect(
    kind,
    content="unknown kind commits; use pull-requests, issues, releases, for-you at line 2",
  )
}
