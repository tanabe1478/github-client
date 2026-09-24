///|
test "triage encode/decode roundtrip" {
  let state = TriageState::new(["https://github.com/acme/app/pull/7"], [
    "https://github.com/acme/app/issues/9",
  ])
  let decoded = decode(encode(state))
  match decoded {
    Ok(state) => {
      inspect(state.saved, content="[https://github.com/acme/app/pull/7]")
      inspect(state.muted, content="[https://github.com/acme/app/issues/9]")
    }
    Err(error) => fail("decode failed: \{error}")
  }
}

///|
test "triage decode rejects bad version" {
  match decode("v2\nsaved\tx\n") {
    Ok(_) => fail("expected error")
    Err(error) => inspect(error, content="unsupported triage store format")
  }
}
