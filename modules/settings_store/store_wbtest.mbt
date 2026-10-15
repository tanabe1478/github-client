///|
test "settings encode/decode roundtrip" {
  let settings = {
    include_merged_mentions: true,
    include_closed_mentions: false,
    mention_days: 14,
    base_repositories: [],
    npm_mirrors: [],
  }
  guard decode(encode(settings)) is Ok(decoded) else {
    fail("encoded settings should decode")
  }
  assert_eq(decoded, settings)
}

///|
test "settings decode tolerates comments, spacing, and missing keys" {
  guard decode("# note\r\n\r\n  mentions.include_closed=true  \r\n")
    is Ok(settings) else {
    fail("settings should decode")
  }
  assert_eq(settings, { ..default_settings(), include_closed_mentions: true, })
  guard decode("") is Ok(empty) else { fail("empty settings should decode") }
  assert_eq(empty, default_settings())
  inspect(empty.mention_days, content="30")
}

///|
test "settings decode accepts the day range bounds" {
  guard decode("mentions.days = 1") is Ok(low) else { fail("1 is allowed") }
  inspect(low.mention_days, content="1")
  guard decode("mentions.days = 365") is Ok(high) else {
    fail("365 is allowed")
  }
  inspect(high.mention_days, content="365")
}

///|
test "settings decode rejects unknown keys and invalid values" {
  let errors = [
    "mentions.include_close = true", "# c\nmentions.include_merged = yes", "mentions.days = 0",
    "mentions.days = 366", "mentions.days = -3", "mentions.days = 7d", "mentions.days =",
    "mentions.include_closed",
  ].map(source => {
    match decode(source) {
      Ok(_) => "accepted"
      Err(error) => error
    }
  })
  inspect(
    errors.join("\n"),
    content=(
      #|unknown setting "mentions.include_close" at line 1
      #|mentions.include_merged at line 2 must be true or false
      #|mentions.days at line 1 must be a whole number from 1 to 365
      #|mentions.days at line 1 must be a whole number from 1 to 365
      #|mentions.days at line 1 must be a whole number from 1 to 365
      #|mentions.days at line 1 must be a whole number from 1 to 365
      #|mentions.days at line 1 must be a whole number from 1 to 365
      #|line 1 is not key = value
    ),
  )
}

///|
test "base repositories round-trip, one per line" {
  let settings = {
    ..default_settings(),
    base_repositories: ["acme/storefront", "tanabe1478/github-client"],
  }
  let encoded = encode(settings)
  assert_true(encoded.contains("base.repository = acme/storefront\n"))
  assert_eq(decode(encoded), Ok(settings))
  assert_true(decode("base.repository = not-a-repository") is Err(_))
}

///|
test "npm mirrors round-trip without a trailing slash" {
  let settings = {
    ..default_settings(),
    npm_mirrors: ["https://npm.acme.example"],
  }
  let encoded = encode(settings)
  assert_true(
    encoded.contains("npm.public_mirror = https://npm.acme.example\n"),
  )
  assert_eq(decode(encoded), Ok(settings))
  assert_eq(
    decode("npm.public_mirror = https://npm.acme.example/").map(settings => {
      settings.npm_mirrors
    }),
    Ok(["https://npm.acme.example"]),
  )
  assert_true(decode("npm.public_mirror = npm.acme.example") is Err(_))
}
