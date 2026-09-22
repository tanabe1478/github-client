///|
test "owned repositories decode suggestion fields" {
  let json = @json.parse(
    "[{\"full_name\":\"octocat/hello-world\",\"private\":true,\"archived\":false}]",
  )
  guard decode_repositories(json) is Ok(repositories) else {
    fail("repository response should decode")
  }
  inspect(repositories.length(), content="1")
  inspect(repositories[0].full_name(), content="octocat/hello-world")
  assert_true(repositories[0].is_private())
  assert_false(repositories[0].is_archived())
}

///|
test "owned repositories reject malformed responses" {
  guard decode_repositories({ "message": "not an array" }) is Err(error) else {
    fail("object response should not decode as a repository list")
  }
  inspect(error, content="GitHub repository response could not be decoded")
}
