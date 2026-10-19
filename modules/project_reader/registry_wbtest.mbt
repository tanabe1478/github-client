///|
test "Maven metadata lists versions and when the newest was published" {
  let xml =
    #|<metadata>
    #|  <groupId>com.acme</groupId>
    #|  <artifactId>widget</artifactId>
    #|  <versioning>
    #|    <latest>10.10</latest>
    #|    <release>10.10</release>
    #|    <versions>
    #|      <version>10.9.1</version>
    #|      <version>10.10</version>
    #|      <version>11.0-beta1</version>
    #|    </versions>
    #|    <lastUpdated>20260917101500</lastUpdated>
    #|  </versioning>
    #|</metadata>
  assert_eq(
    maven_metadata_versions(xml),
    (["10.9.1", "10.10", "11.0-beta1"], "2026-09-17T10:15:00Z"),
  )
}

///|
test "an npm document gives each version's publication time" {
  let document =
    #|{"name":"widget","time":{"created":"2025-01-01T00:00:00.000Z","1.0.0":"2025-01-01T00:00:00.000Z","1.1.0":"2026-09-17T10:15:00.000Z"},
    #| "versions":{"1.0.0":{},"1.1.0":{}}}
  assert_eq(npm_document_versions(document), [
    ("1.0.0", "2025-01-01T00:00:00.000Z"),
    ("1.1.0", "2026-09-17T10:15:00.000Z"),
  ])
}

///|
test "the changelog is found by Dependabot's names" {
  assert_eq(
    changelog_file(["README.md", "HISTORY.md", "CHANGELOG.txt", "src"]),
    Some("CHANGELOG.txt"),
  )
  assert_eq(changelog_file(["README.md", "changes"]), Some("changes"))
  assert_eq(changelog_file(["README.md", "changelog-generator.js"]), None)
}

///|
test "an oldest-first changelog gives the versions after the one in use" {
  let text =
    #|version 10.9
    #|* Adds a cache.
    #|
    #|10.9.1 (2026-05-31)
    #|* Fixes health status reporting.
    #|
    #|10.10 (2026-09-17)
    #|* Adds a decompression limit.
    #|
    #|10.10.1 (2026-10-01)
    #|* Not released yet.
  assert_eq(
    changelog_section(text, "10.10", "10.9"),
    (
      #|10.9.1 (2026-05-31)
      #|* Fixes health status reporting.
      #|
      #|10.10 (2026-09-17)
      #|* Adds a decompression limit.
    ),
  )
}

///|
test "a newest-first changelog gives the sections down to the one in use" {
  let text =
    #|# Changelog
    #|
    #|## [2.1.0] - 2026-09-17
    #|### Added
    #|- `widget.retry`
    #|
    #|## [2.0.1] - 2026-08-01
    #|- Fixes a leak.
    #|
    #|## [2.0.0] - 2026-07-01
    #|- First release.
  assert_eq(
    changelog_section(text, "2.1.0", "2.0.0"),
    (
      #|## [2.1.0] - 2026-09-17
      #|### Added
      #|- `widget.retry`
      #|
      #|## [2.0.1] - 2026-08-01
      #|- Fixes a leak.
    ),
  )
  // Without the version in use, only the newest section; 2.1.0 is not
  // the heading of 2.1.0.1.
  assert_eq(
    changelog_section(text, "2.1.0", "1.9.0"),
    (
      #|## [2.1.0] - 2026-09-17
      #|### Added
      #|- `widget.retry`
    ),
  )
  assert_eq(changelog_section(text, "3.0.0", "2.0.0"), "")
}

///|
test "a summary is the newest section's first entry" {
  let text =
    #|10.9.1 (2026-05-31)
    #|    * Fixes health status reporting.
    #|
    #|10.10 (2026-09-17)
    #|    * Adds a limit for the length of
    #|      decompressed text. Set to 1 mio bytes.
    #|    * Adds explicit checks.
  assert_eq(
    changelog_summary(text, "10.10"),
    "Adds a limit for the length of decompressed text.",
  )
  let keep_a_changelog =
    #|## [18.0.8] - 2026-10-14
    #|### Changed
    #|- Quiets the startup log
    #|
    #|## [18.0.7] - 2026-10-01
  assert_eq(
    changelog_summary(keep_a_changelog, "18.0.8"),
    "Quiets the startup log",
  )
  assert_eq(changelog_summary(text, "11.0"), "")
  assert_eq(
    changelog_file(["README.md", "RELEASE-NOTES.txt"]),
    Some("RELEASE-NOTES.txt"),
  )
}
