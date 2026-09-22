///|
test "navigation preserves sign-in state" {
  let initial = @app.Model::new()
  let signed_in = @app.update(initial, @app.Msg::RequestSignIn)
  let issues = @app.update(signed_in, @app.Msg::Navigate(@app.Page::Issues))
  inspect(issues.page().name(), content="Issues")
  inspect(issues.sign_in_requests(), content="1")
}

///|
test "sign-in requests are counted" {
  let initial = @app.Model::new()
  let once = @app.update(initial, @app.Msg::RequestSignIn)
  let twice = @app.update(once, @app.Msg::RequestSignIn)
  inspect(twice.sign_in_requests(), content="2")
}
