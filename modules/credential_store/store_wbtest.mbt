///|
test "scope normalization defaults blanks and rejects unsafe names" {
  guard normalize_scope("   ") is Ok(scope) else {
    fail("blank scope must fall back to default")
  }
  inspect(scope, content="default")
  guard normalize_scope("My-Org") is Ok(lowered) else {
    fail("owner names must be accepted")
  }
  inspect(lowered, content="my-org")
  guard normalize_scope("bad_scope!") is Err(error) else {
    fail("unsafe scope must be rejected")
  }
  inspect(error, content="scope may only contain letters, digits, and hyphens")
}

///|
test "empty tokens are rejected before storage" {
  guard save_token("   ") is Err(error) else {
    fail("empty token must be rejected")
  }
  inspect(error, content="token must not be empty")
}

///|
test "OS-backed encryption round trips without writing plaintext" {
  if !@safe_storage.is_available() {
    return
  }
  guard @safe_storage.encrypt_string("synthetic-test-token") is Ok(encrypted) else {
    fail("safe storage encryption should succeed")
  }
  assert_false(encrypted.contains("synthetic-test-token"))
  guard @safe_storage.decrypt_string(encrypted) is Ok(decrypted) else {
    fail("safe storage decryption should succeed")
  }
  inspect(decrypted, content="synthetic-test-token")
}
