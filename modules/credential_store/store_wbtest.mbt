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
