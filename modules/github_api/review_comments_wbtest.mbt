///|
test "mentions_login matches a standalone mention in any case" {
  inspect(
    mentions_login("@Tanabe1478 @other\nplease look", "tanabe1478"),
    content="true",
  )
  inspect(
    mentions_login("確認お願いします@tanabe1478。", "tanabe1478"),
    content="true",
  )
  inspect(mentions_login("cc (@tanabe1478)", "tanabe1478"), content="true")
}

///|
test "mentions_login ignores longer logins, addresses, and teams" {
  inspect(mentions_login("@tanabe1478x", "tanabe1478"), content="false")
  inspect(mentions_login("@tanabe1478-bot", "tanabe1478"), content="false")
  inspect(
    mentions_login("mail me at me@tanabe1478.dev", "tanabe1478"),
    content="false",
  )
  inspect(
    mentions_login("@tanabe1478/reviewers", "tanabe1478"),
    content="false",
  )
  inspect(mentions_login("tanabe1478", "tanabe1478"), content="false")
  inspect(mentions_login("@tanabe1478", ""), content="false")
}

///|
test "review comment mentions yield pull request numbers once" {
  let json = @json.parse(
    "[{\"body\":\"@tanabe1478 see here\",\"pull_request_url\":\"https://api.github.com/repos/acme/app/pulls/2124\",\"user\":{\"login\":\"katagiri\"}},{\"body\":\"and @tanabe1478 again\",\"pull_request_url\":\"https://api.github.com/repos/acme/app/pulls/2124\",\"user\":{\"login\":\"katagiri\"}},{\"body\":\"no mention\",\"pull_request_url\":\"https://api.github.com/repos/acme/app/pulls/7\",\"user\":{\"login\":\"katagiri\"}},{\"body\":\"replying to @tanabe1478\",\"pull_request_url\":\"https://api.github.com/repos/acme/app/pulls/8\",\"user\":{\"login\":\"Tanabe1478\"}},{\"body\":\"@tanabe1478 from a deleted user\",\"pull_request_url\":\"https://api.github.com/repos/acme/app/pulls/9\",\"user\":null}]",
  )
  guard decode_review_comment_mentions(json, ["tanabe1478"]) is Ok(numbers) else {
    fail("review comments should decode")
  }
  inspect(numbers, content="[2124, 9]")
}

///|
test "review comment response must be an array" {
  let json = @json.parse("{\"message\":\"Not Found\"}")
  guard decode_review_comment_mentions(json, ["tanabe1478"]) is Err(_) else {
    fail("an object should not decode")
  }
}

///|
test "review comment route reads recent comments newest first" {
  inspect(
    repository_review_comments_path("acme", "app", "2026-09-06T00:00:00Z", 2),
    content="/repos/acme/app/pulls/comments?sort=updated&direction=desc&since=2026-09-06T00:00:00Z&per_page=100&page=2",
  )
}
