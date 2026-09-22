///|
test "repository store codec round trips" {
  let encoded = encode([
    @domain.RepositoryRef::new("tanabe1478", "github-client"),
    @domain.RepositoryRef::new("ocornut", "imgui"),
  ])
  inspect(encoded, content="v1\ntanabe1478/github-client\nocornut/imgui\n")
  guard decode(encoded) is Ok(repositories) else {
    fail("repository store should decode")
  }
  inspect(
    repositories.map(repository => repository.key()).join(","),
    content="tanabe1478/github-client,ocornut/imgui",
  )
}

///|
test "repository store rejects malformed entries" {
  guard decode("v1\nmissing-owner-separator\n") is Err(malformed) else {
    fail("malformed repository should fail")
  }
  inspect(malformed, content="invalid repository at line 2")
  guard decode("v2\nacme/repo\n") is Err(version) else {
    fail("unsupported version should fail")
  }
  inspect(version, content="unsupported repository store format")
}
