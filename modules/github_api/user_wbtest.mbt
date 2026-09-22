///|
test "authenticated user response decodes the minimal fields" {
  let json = @json.parse(
    "{\"login\":\"octocat\",\"name\":\"The Octocat\",\"avatar_url\":\"https://example.test/avatar.png\"}",
  )
  guard decode_authenticated_user(json) is Ok(user) else {
    fail("user response should decode")
  }
  inspect(user.login(), content="octocat")
  guard user.name() is Some(name) else { fail("user name should be present") }
  inspect(name, content="The Octocat")
  inspect(user.avatar_url(), content="https://example.test/avatar.png")
}

///|
test "authenticated user response requires login" {
  let json = @json.parse("{\"avatar_url\":\"https://example.test/avatar.png\"}")
  guard decode_authenticated_user(json) is Err(error) else {
    fail("missing login should fail")
  }
  inspect(error, content="GitHub response is missing login")
}
