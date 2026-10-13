///|
test "release levels come from the tag's version" {
  assert_eq(release_level("v12.0.0"), Major)
  assert_eq(release_level("v12.12.0"), Minor)
  assert_eq(release_level("v12.12.1"), Patch)
  assert_eq(release_level("pnpm@10.34.7"), Patch)
  assert_eq(release_level("2.0"), Major)
  assert_eq(release_level("v3.1.0-rc.1"), Minor)
  assert_eq(release_level("nightly"), Minor)
}

///|
test "release notifications follow the chosen level" {
  assert_true(MajorAndMinor.notifies(Minor, prerelease=false))
  assert_false(MajorAndMinor.notifies(Patch, prerelease=false))
  assert_false(MajorOnly.notifies(Minor, prerelease=false))
  assert_true(MajorOnly.notifies(Major, prerelease=false))
  assert_false(MajorAndMinor.notifies(Major, prerelease=true))
  assert_true(AllReleases.notifies(Patch, prerelease=true))
  assert_false(NoReleases.notifies(Major, prerelease=false))
}

///|
test "kinds round-trip through their text form" {
  let options = WatchOptions::default()
  assert_eq(options.kinds_text(), "pull-requests,issues,for-you")
  guard options.with_kinds("releases") is Ok(releases_only) else {
    fail("expected releases to parse")
  }
  assert_eq(releases_only.kinds_text(), "releases")
  assert_eq(releases_only.release_notify, MajorAndMinor)
  assert_true(options.with_kinds("commits") is Err(_))
  assert_eq(options.toggle("issues").kinds_text(), "pull-requests,for-you")
}

///|
test "For you covers only repositories that choose it" {
  let pnpm = RepositoryRef::new("pnpm", "pnpm")
  let app = RepositoryRef::new("owner", "app")
  let options : Map[String, WatchOptions] = Map([])
  options.set("pnpm/pnpm", { ..WatchOptions::default(), for_you: false, })
  let keys = for_you_repositories([pnpm, app], options).map(r => r.key())
  assert_eq(keys, ["owner/app"])
}

///|
test "only a newly chosen kind needs a fetch" {
  let options = WatchOptions::default()
  assert_true(options.gains(options.toggle("releases")))
  assert_false(options.gains(options.toggle("issues")))
  assert_false(options.gains({ ..options, release_notify: MajorOnly, }))
}
