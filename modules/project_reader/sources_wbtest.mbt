///|
test "a pom names its repository by url, scm, or issue tracker" {
  let by_url =
    #|<project>
    #|  <artifactId>widget</artifactId>
    #|  <url>https://github.com/acme/widget</url>
    #|  <licenses><license><url>https://example.com/license</url></license></licenses>
    #|</project>
  assert_eq(pom_source(by_url, "widget"), Some(Some("acme/widget")))
  // A homepage that is not a source host falls through to scm, whose url
  // is a property, as AWS SDK and Flyway write it.
  let by_scm =
    #|<project>
    #|  <url>https://widgets.example.com</url>
    #|  <properties>
    #|    <scm.github.url>https://github.com/acme/widget-sdk</scm.github.url>
    #|  </properties>
    #|  <scm>
    #|    <url>${scm.github.url}</url>
    #|    <connection>scm:git:git://github.com/acme/widget-sdk.git</connection>
    #|  </scm>
    #|</project>
  assert_eq(pom_source(by_scm, "widget-core"), Some(Some("acme/widget-sdk")))
  let by_issues =
    #|<project>
    #|  <issueManagement><url>https://github.com/acme/widget/issues</url></issueManagement>
    #|</project>
  assert_eq(pom_source(by_issues, "widget"), Some(Some("acme/widget")))
  // Bitbucket is a source, so it wins over a GitHub URL further down, but
  // it cannot be watched.
  let on_bitbucket =
    #|<project>
    #|  <url>https://bitbucket.org/acme/widget</url>
    #|  <scm><url>https://github.com/acme/widget</url></scm>
    #|</project>
  assert_eq(pom_source(on_bitbucket, "widget"), Some(None))
  assert_eq(
    pom_source(
      "<project><url>https://widgets.example.com</url></project>", "widget",
    ),
    None,
  )
}

///|
test "a GitHub URL elsewhere in a pom counts only when named like the artifact" {
  let pom =
    #|<project>
    #|  <description>See https://github.com/acme/widget-docs and
    #|  https://github.com/acme/widget#readme</description>
    #|</project>
  assert_eq(pom_source(pom, "widget"), Some(Some("acme/widget")))
  assert_eq(pom_source(pom, "gadget"), None)
}

///|
test "parents are read and accepted by group or name" {
  let pom =
    #|<project>
    #|  <parent>
    #|    <groupId>com.acme.widgets</groupId>
    #|    <artifactId>services</artifactId>
    #|    <version>2.5.0</version>
    #|  </parent>
    #|  <artifactId>widget-store</artifactId>
    #|</project>
  assert_eq(pom_parent(pom), Some(("com.acme.widgets", "services", "2.5.0")))
  assert_eq(pom_parent("<project></project>"), None)
  assert_true(
    ancestor_source_accepted(
      "com.acme.widgets", "widget-store", "com.acme.widgets", "acme/widget-sdk",
    ),
  )
  // Another group's parent, such as a company-wide parent pom, names some
  // other repository unless it is named like the artifact.
  assert_false(
    ancestor_source_accepted(
      "com.acme.widgets", "widget-store", "com.acme", "acme/parent-poms",
    ),
  )
  assert_true(
    ancestor_source_accepted(
      "com.acme.widgets", "widget-store", "com.acme", "acme/widget-store",
    ),
  )
}

///|
test "a plugin marker points at the plugin's library" {
  let marker =
    #|<project>
    #|  <groupId>com.acme.lint</groupId>
    #|  <artifactId>com.acme.lint.gradle.plugin</artifactId>
    #|  <dependencies>
    #|    <dependency>
    #|      <groupId>com.acme.lint</groupId>
    #|      <artifactId>lint-gradle-plugin</artifactId>
    #|      <version>8.1.0</version>
    #|    </dependency>
    #|  </dependencies>
    #|</project>
  assert_eq(
    plugin_marker_target(marker),
    Some(("com.acme.lint", "lint-gradle-plugin", "8.1.0")),
  )
}

///|
test "an npm entry names its repository by repository, homepage, or bugs" {
  assert_eq(
    npm_source(
      (
        #|{"repository":{"type":"git","url":"git+https://github.com/acme/widgets.git","directory":"packages/widget"}}
      ),
    ),
    Some(Some("acme/widgets")),
  )
  assert_eq(
    npm_source(
      (
        #|{"repository":"acme/widgets"}
      ),
    ),
    Some(Some("acme/widgets")),
  )
  assert_eq(
    npm_source(
      (
        #|{"repository":"github:acme/widgets"}
      ),
    ),
    Some(Some("acme/widgets")),
  )
  assert_eq(
    npm_source(
      (
        #|{"homepage":"https://github.com/acme/widgets#readme"}
      ),
    ),
    Some(Some("acme/widgets")),
  )
  assert_eq(
    npm_source(
      (
        #|{"repository":{"url":"git@github.com:acme/widgets.git"}}
      ),
    ),
    Some(Some("acme/widgets")),
  )
  assert_eq(
    npm_source(
      (
        #|{"homepage":"https://widgets.example.com","bugs":{"url":"https://gitlab.com/acme/widgets/issues"}}
      ),
    ),
    Some(None),
  )
  assert_eq(
    npm_source(
      (
        #|{"name":"widget"}
      ),
    ),
    None,
  )
}

///|
test "lookups leave out the project's own and privately served packages" {
  let profile = parse_files("acme/api", [
    (
      "build.gradle.kts",
      (
        #|group = "com.acme.api"
        #|plugins {
        #|  id("com.acme.lint") version "8.1.0"
        #|}
        #|dependencies {
        #|  implementation("com.acme.api.shared:shared-model:1.0.0")
        #|  implementation("org.example:widget:2.3.1")
        #|  implementation("org.example:ranged:[1.0,2.0)")
        #|}
      ),
    ),
    (
      "web/package.json",
      (
        #|{"dependencies":{"left-pad":"^1.3.0","@acme/ui":"^3.0.0","@types/widget":"^2.0.0"},
        #| "devDependencies":{"vite":"^5.2.0"}, "engines":{"node":">=22"},
        #| "packageManager":"pnpm@11.4.0"}
      ),
    ),
    (
      "web/.npmrc",
      (
        #|@acme:registry=https://npm.acme.example/
        #|//npm.acme.example/:_authToken=${NPM_TOKEN}
      ),
    ),
    (
      ".github/workflows/ci.yml",
      (
        #|jobs:
        #|  build:
        #|    steps:
        #|      - uses: actions/checkout@v4
      ),
    ),
  ])
  let lookups = package_lookups(profile, [
    ("build.gradle.kts", "group = \"com.acme.api\""),
    ("web/.npmrc", "@acme:registry=https://npm.acme.example/"),
  ])
  assert_eq(lookups.map(lookup => lookup.tool_name()), [
    "com.acme.lint", "org.example:widget", "left-pad", "@types/widget", "vite",
  ])
  assert_eq(lookups[0], GradlePlugin("com.acme.lint", "8.1.0"))
  assert_eq(lookups[1], Maven("org.example", "widget", "2.3.1"))
  // An .npmrc that sends every package elsewhere keeps all of them in.
  let behind_proxy = package_lookups(profile, [
    (".npmrc", "registry=https://npm.acme.example/"),
  ])
  assert_false(behind_proxy.any(lookup => lookup is Npm(_)))
}

///|
test "a registry set as an npm mirror lets its packages be looked up" {
  let files = [
    (
      ".npmrc", "registry=https://npm.acme.example/\n@acme:registry=https://npm.pkg.example/",
    ),
    (
      "package.json",
      (
        #|{"dependencies":{"left-pad":"^1.3.0","@acme/ui":"^3.0.0","@types/widget":"^2.0.0"}}
      ),
    ),
  ]
  let profile = parse_files("acme/web", files)
  assert_eq(profile.npm_registry, "https://npm.acme.example")
  assert_eq(package_lookups(profile, files), [])
  // The mirror covers the default registry; @acme still goes elsewhere.
  assert_eq(
    package_lookups(profile, files, npm_mirrors=["https://npm.acme.example/"]),
    [Npm("left-pad"), Npm("@types/widget")],
  )
  assert_eq(
    parse_files("acme/web", [(".npmrc", "registry=https://registry.npmjs.org/")]).npm_registry,
    "",
  )
}
