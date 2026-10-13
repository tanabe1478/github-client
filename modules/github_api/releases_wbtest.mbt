///|
test "release summaries are the first sentence of prose" {
  assert_eq(
    release_summary(
      "This release adds OIDC authentication to `pnpm dist-tag` and the `tool:` protocol. `pnpm publish` now checks the registry.\n\n### Patch Changes",
    ),
    "This release adds OIDC authentication to `pnpm dist-tag` and the `tool:` protocol.",
  )
  assert_eq(
    release_summary(
      "### Patch Changes\n\n*   97f550c: Switching works.\n\nPlain line",
    ),
    "Plain line",
  )
  assert_eq(release_summary("## Only headings\n- and lists"), "")
}

///|
test "drafts and unpublished releases are skipped" {
  let json : Json = [
    {
      "tag_name": "v12.12.1",
      "name": "pnpm 12.12.1",
      "html_url": "https://github.com/pnpm/pnpm/releases/tag/v12.12.1",
      "published_at": "2026-10-11T11:30:09Z",
      "draft": false,
      "prerelease": false,
      "author": { "login": "zkochan" },
      "body": "This release fixes things. More text.",
    },
    {
      "tag_name": "v13.0.0-alpha.1",
      "name": "",
      "html_url": "https://github.com/pnpm/pnpm/releases/tag/v13.0.0-alpha.1",
      "published_at": "2026-10-12T00:00:00Z",
      "draft": false,
      "prerelease": true,
      "author": null,
      "body": null,
    },
    {
      "tag_name": "v14.0.0",
      "html_url": "https://github.com/pnpm/pnpm/releases/tag/untagged-1",
      "published_at": null,
      "draft": true,
    },
  ]
  guard decode_releases(json, "pnpm/pnpm") is Ok(releases) else {
    fail("expected releases to decode")
  }
  assert_eq(releases.length(), 2)
  assert_eq(releases[0].title(), "pnpm 12.12.1")
  assert_eq(releases[0].summary(), "This release fixes things.")
  assert_eq(releases[0].updated_at(), "2026-10-11T11:30:09Z")
  assert_true(releases[0].kind() is Release)
  assert_eq(releases[1].title(), "v13.0.0-alpha.1")
  assert_eq(releases[1].author(), "")
  assert_true(releases[1].is_prerelease())
}
