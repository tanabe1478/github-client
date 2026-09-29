///|
test "classify_failure recognizes each message, even with a prefix" {
  assert_eq(
    classify_failure("default: GitHub rejected the saved token"),
    Unauthorized,
  )
  assert_eq(
    classify_failure(
      "owner/app: pull requests: GitHub API rate limit was reached (resets at 1790000000)",
    ),
    RateLimited(1790000000L),
  )
  assert_eq(
    classify_failure(
      "GitHub denied the request or the API rate limit was reached",
    ),
    Forbidden,
  )
  assert_eq(
    classify_failure("GitHub repository was not found or is not accessible"),
    NotFound,
  )
  assert_eq(
    classify_failure("GitHub request failed before a response was received"),
    Network,
  )
  assert_eq(classify_failure("GitHub request failed with status 500"), Other)
}
