///|
test "no arguments and --help show help" {
  guard parse_invocation([]) is Ok(help) else { fail("expected help") }
  assert_eq(help.command, "help")
  guard parse_invocation(["inbox", "--help"]) is Ok(inbox_help) else {
    fail("expected help")
  }
  assert_eq(inbox_help.command, "help")
}

///|
test "options may come before or after the command" {
  guard parse_invocation([
      "--json", "inbox", "--kind", "pr", "--repo", "owner/app", "--all",
    ])
    is Ok(invocation) else {
    fail("expected inbox to parse")
  }
  assert_eq(invocation.command, "inbox")
  assert_true(invocation.json)
  assert_true(invocation.all)
  assert_eq(invocation.kind, "pr")
  assert_eq(invocation.repository, "owner/app")
  assert_true(invocation.filter().kind is PullRequestsOnly)
  assert_true(invocation.filter().show_done)
}

///|
test "reasons with spaces are accepted as one value" {
  guard parse_invocation(["for-you", "--reason", "Review requested"])
    is Ok(invocation) else {
    fail("expected for-you to parse")
  }
  assert_eq(invocation.reason, "Review requested")
}

///|
test "commands that act on items take several arguments" {
  guard parse_invocation([
      "done", "https://github.com/o/a/pull/1", "https://github.com/o/a/issues/2",
    ])
    is Ok(invocation) else {
    fail("expected done to parse")
  }
  assert_eq(invocation.arguments.length(), 2)
}

///|
test "usage errors are reported" {
  assert_true(parse_invocation(["bogus"]) is Err(_))
  assert_true(parse_invocation(["done"]) is Err(_))
  assert_true(parse_invocation(["inbox", "extra"]) is Err(_))
  assert_true(parse_invocation(["inbox", "--kind", "commit"]) is Err(_))
  assert_true(parse_invocation(["inbox", "--repo"]) is Err(_))
  assert_true(parse_invocation(["for-you", "--reason", "Starred"]) is Err(_))
  assert_true(parse_invocation(["inbox", "--unknown"]) is Err(_))
}
