///|
test "navigation preserves sign-in state" {
  let initial = Model::new()
  let signed_in = update(initial, Msg::RequestSignIn)
  let issues = update(signed_in, Msg::Navigate(Page::Issues))
  inspect(issues.page().name(), content="Issues")
  inspect(issues.sign_in_requests(), content="1")
}

///|
test "sign-in requests are counted" {
  let initial = Model::new()
  let once = update(initial, Msg::RequestSignIn)
  let twice = update(once, Msg::RequestSignIn)
  inspect(twice.sign_in_requests(), content="2")
}

///|
test "repository registration is idempotent" {
  let repository = RepositoryRef::new("tanabe1478", "github-client")
  let once = update(Model::new(), Msg::RegisterRepository(repository))
  let twice = update(once, Msg::RegisterRepository(repository))
  inspect(
    twice.repositories().map(item => item.key()).join(","),
    content="tanabe1478/github-client",
  )
}
