///|
test "review request URLs round-trip without duplicates" {
  let urls = [
    "https://github.com/acme/app/pull/1", "https://github.com/acme/app/pull/2",
  ]
  assert_eq(decode(encode(urls)), Ok(urls))
  assert_eq(
    decode(
      "v1\nhttps://github.com/acme/app/pull/1\nhttps://github.com/acme/app/pull/1\n",
    ),
    Ok(["https://github.com/acme/app/pull/1"]),
  )
  assert_eq(decode(""), Ok([]))
  assert_true(decode("v9\nx") is Err(_))
}
