///|
test "navigation preserves sign-in state" {
  let initial = Model::new()
  let signed_in = update(initial, Msg::RequestSignIn)
  let issues = update(signed_in, Msg::Navigate(Page::Issues))
  inspect(issues.page().name(), content="Issues")
  inspect(issues.sign_in_requests(), content="1")
}

///|
test "for-you navigation is distinct from inbox" {
  let for_you = update(Model::new(), Msg::Navigate(Page::ForYou))
  inspect(for_you.page().name(), content="ForYou")
  inspect(for_you.page().code(), content="5")
}

///|
test "settings navigation preserves application state" {
  let repository = RepositoryRef::new("tanabe1478", "github-client")
  let registered = update(Model::new(), Msg::RegisterRepository(repository))
  let settings = update(registered, Msg::Navigate(Page::Settings))
  inspect(settings.page().name(), content="Settings")
  inspect(settings.repositories().length(), content="1")
}

///|
test "sign-in requests are counted" {
  let initial = Model::new()
  let once = update(initial, Msg::RequestSignIn)
  let twice = update(once, Msg::RequestSignIn)
  inspect(twice.sign_in_requests(), content="2")
}

///|
test "watched repository can be removed" {
  let repository = RepositoryRef::new("tanabe1478", "github-client")
  let registered = update(Model::new(), Msg::RegisterRepository(repository))
  let removed = update(
    registered,
    Msg::RemoveRepository("tanabe1478/github-client"),
  )
  inspect(removed.repositories().length(), content="0")
}

///|
test "removing an unknown repository preserves watched repositories" {
  let repository = RepositoryRef::new("tanabe1478", "github-client")
  let registered = update(Model::new(), Msg::RegisterRepository(repository))
  let unchanged = update(registered, Msg::RemoveRepository("other/repository"))
  inspect(
    unchanged.repositories().map(item => item.key()).join(","),
    content="tanabe1478/github-client",
  )
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
