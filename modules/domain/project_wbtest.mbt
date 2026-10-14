///|
fn web_profile() -> ProjectProfile {
  {
    name: "acme/web",
    package_name: "@acme/web",
    tools: [
      {
        name: "pnpm",
        version: "11.4.0",
        exact: true,
        source: "package.json packageManager",
      },
      {
        name: "vite",
        version: "^5.2.0",
        exact: false,
        source: "package.json devDependencies",
      },
    ],
    settings: [{ key: "workspace-concurrency", file: ".npmrc", }],
    files: ["package.json", ".npmrc"],
    dependency_count: 2,
    managed: [],
    moved_to: "",
    problem: "",
  }
}

///|
test "versions are read from tags and ranges" {
  assert_eq(
    parse_version("v12.12.0"),
    Some({ major: 12, minor: 12, patch: 0, }),
  )
  assert_eq(
    parse_version("pnpm@11.4.0+sha512.abc"),
    Some({ major: 11, minor: 4, patch: 0, }),
  )
  assert_eq(parse_version("^5.2"), Some({ major: 5, minor: 2, patch: 0, }))
  assert_eq(parse_version(">=10"), Some({ major: 10, minor: 0, patch: 0, }))
  assert_eq(
    parse_version("13.0.0-alpha.1"),
    Some({ major: 13, minor: 0, patch: 0, }),
  )
  assert_eq(parse_version("workspace:*"), None)
}

///|
test "release packages come from tags, known repositories, or names" {
  assert_eq(release_package("pnpm/pnpm", "v12.12.0"), "pnpm")
  assert_eq(release_package("pnpm/pnpm", "pnpr@0.1.0-alpha.15"), "pnpr")
  assert_eq(release_package("npm/cli", "v11.6.2"), "npm")
  assert_eq(release_package("vitejs/vite", "v6.0.0"), "vite")
}

///|
test "a newer major release is a major update" {
  let relations = release_relations("pnpm/pnpm", "v12.12.0", "", [web_profile()])
  assert_eq(relations.length(), 1)
  assert_eq(relations[0].kind, MajorUpdate)
  assert_eq(relations[0].label, "pnpm 11.4.0 → 12.12.0 · Major update")
  assert_true(relations[0].counts())
}

///|
test "exact versions in the same line are newer; ranges cover them" {
  let pnpm = release_relations("pnpm/pnpm", "v11.5.1", "", [web_profile()])
  assert_eq(pnpm[0].kind, NewerThanInUse)
  let vite = release_relations("vitejs/vite", "v5.4.0", "", [web_profile()])
  assert_eq(vite[0].kind, InUse)
  assert_eq(vite[0].label, "^5.2.0 allows 5.4.0")
  assert_false(vite[0].counts())
  let older = release_relations("pnpm/pnpm", "v11.4.0", "", [web_profile()])
  assert_eq(older[0].label, "11.4.0 in use")
}

///|
test "settings named in code spans relate a newer release" {
  let relations = release_relations(
    "pnpm/pnpm",
    "v11.5.0",
    "This release fixes `--workspace-concurrency=Infinity` and `registry.npmjs.com`.",
    [web_profile()],
  )
  assert_eq(relations.length(), 2)
  assert_eq(relations[1].kind, UsesSetting)
  assert_eq(relations[1].label, "uses workspace-concurrency in .npmrc")
  // A release the project already uses is not affected by its settings.
  let adopted = release_relations(
    "pnpm/pnpm",
    "v11.4.0",
    "This release fixes `--workspace-concurrency=Infinity`.",
    [web_profile()],
  )
  assert_eq(adopted.length(), 1)
  assert_eq(adopted[0].kind, InUse)
}

///|
test "only spans that name one setting count" {
  let words = code_words(
    "`registry.npmjs.com`, `pnpm add --config`, `addMissingPeerTypes`, `minimumReleaseAge: 1440`",
  )
  assert_true(words.contains("addmissingpeertypes"))
  assert_true(words.contains("minimumreleaseage"))
  assert_false(words.contains("registry"))
  assert_true(words.contains("registry.npmjs.com"))
  assert_eq(words.length(), 3)
}

///|
test "projects that do not use the package get nothing" {
  assert_eq(release_relations("npm/cli", "v11.6.2", "", [web_profile()]), [])
  assert_eq(release_relations("pnpm/pnpm", "nightly", "", [web_profile()]), [])
}

///|
test "a directory of packages is judged by the oldest one" {
  let profile = {
    ..web_profile(),
    tools: [
      {
        name: "pnpm",
        version: "11.1.2",
        exact: true,
        source: "load-test/package.json packageManager",
      },
      {
        name: "pnpm",
        version: "10.27.0",
        exact: true,
        source: "openapi/package.json packageManager",
      },
      {
        name: "pnpm",
        version: ">=9.0.0",
        exact: false,
        source: "frontend/package.json engines",
      },
    ],
  }
  let relations = release_relations("pnpm/pnpm", "v12.12.0", "", [profile])
  assert_eq(relations[0].label, "pnpm 10.27.0 → 12.12.0 · Major update")
  assert_eq(
    relations[0].evidence[0],
    "openapi/package.json packageManager sets pnpm: 10.27.0",
  )
}

///|
test "open ranges allow newer majors; caret and tilde do not" {
  let lower = { major: 10, minor: 0, patch: 0, }
  assert_true(
    range_allows(">=10.0.0", lower, { major: 11, minor: 6, patch: 2, }),
  )
  assert_false(
    range_allows("^10.0.0", lower, { major: 11, minor: 0, patch: 0, }),
  )
  assert_true(
    range_allows("^10.0.0", lower, { major: 10, minor: 9, patch: 2, }),
  )
  assert_false(
    range_allows("~10.0.0", lower, { major: 10, minor: 1, patch: 0, }),
  )
  assert_false(
    range_allows(">=10.0.0", lower, { major: 9, minor: 0, patch: 0, }),
  )
  let npm = release_relations("npm/cli", "v11.6.2", "", [
    {
      ..web_profile(),
      tools: [
        {
          name: "npm",
          version: ">=10.0.0",
          exact: false,
          source: "package.json engines",
        },
      ],
    },
  ])
  assert_eq(npm[0].kind, InUse)
  assert_eq(npm[0].label, ">=10.0.0 allows 11.6.2")
}

///|
fn service_profile() -> ProjectProfile {
  {
    name: "acme/service",
    package_name: "",
    tools: [
      {
        name: "org.springframework.boot",
        version: "3.4.2",
        exact: true,
        source: "gradle/libs.versions.toml plugins",
      },
      {
        name: "org.springframework.boot:spring-boot-starter-web",
        version: "3.4.2",
        exact: true,
        source: "gradle/libs.versions.toml libraries",
      },
      {
        name: "com.acme:widget",
        version: "1.2.0",
        exact: true,
        source: "gradle/libs.versions.toml libraries",
      },
      {
        name: "gradle",
        version: "8.12.1",
        exact: true,
        source: "gradle/wrapper/gradle-wrapper.properties",
      },
    ],
    settings: [{ key: "org.gradle.caching", file: "gradle.properties", }],
    files: ["gradle/libs.versions.toml"],
    dependency_count: 2,
    managed: [],
    moved_to: "",
    problem: "",
  }
}

///|
test "Spring Boot releases match the plugin and the group's libraries" {
  let relations = release_relations(
    "spring-projects/spring-boot",
    "v4.0.0",
    "",
    [service_profile()],
  )
  assert_eq(relations.length(), 1)
  assert_eq(relations[0].label, "Spring Boot 3.4.2 → 4.0.0 · Major update")
  let patch = release_relations("spring-projects/spring-boot", "v3.4.3", "", [
    service_profile(),
  ])
  assert_eq(patch[0].kind, NewerThanInUse)
  assert_eq(patch[0].label, "Spring Boot 3.4.2 → 3.4.3")
}

///|
test "Gradle releases and libraries named after the repository match" {
  let gradle = release_relations(
    "gradle/gradle",
    "v9.0.0",
    "Turn on `org.gradle.caching=true`.",
    [service_profile()],
  )
  assert_eq(gradle.map(relation => relation.kind), [MajorUpdate, UsesSetting])
  assert_eq(gradle[1].label, "uses org.gradle.caching in gradle.properties")
  let widget = release_relations("acme/widget", "v1.3.0", "", [
    service_profile(),
  ])
  assert_eq(widget[0].label, "widget 1.2.0 → 1.3.0")
  // A group is matched whole: org.springframework is not org.springframework.boot.
  assert_eq(
    release_relations("spring-projects/spring-framework", "v7.0.0", "", [
      service_profile(),
    ]),
    [],
  )
}

///|
test "headline tools lead with the framework and the build tool" {
  assert_eq(headline_tools(service_profile()), [
    "Spring Boot 3.4.2", "Gradle 8.12.1",
  ])
  assert_eq(headline_tools(web_profile()), ["pnpm 11.4.0"])
}

///|
test "labels keep a pre-release suffix from the tag" {
  let relations = release_relations(
    "spring-projects/spring-boot",
    "v4.2.0-M2",
    "",
    [service_profile()],
  )
  assert_eq(
    relations[0].label,
    "Spring Boot 3.4.2 → 4.2.0-M2 · Major update",
  )
}

///|
test "on a tie the evidence names the tool spelled like the package" {
  let profile = service_profile()
  // The library first, as a version catalog lists [libraries] before [plugins].
  let reordered = {
    ..profile,
    tools: [
      profile.tools[1],
      profile.tools[0],
      profile.tools[2],
      profile.tools[3],
    ],
  }
  let relations = release_relations(
    "spring-projects/spring-boot",
    "v3.4.3",
    "",
    [reordered],
  )
  assert_eq(
    relations[0].evidence[0],
    "gradle/libs.versions.toml plugins sets org.springframework.boot: 3.4.2",
  )
}

///|
test "a setting set in several files is one relation" {
  let profile = {
    ..service_profile(),
    settings: [
      {
        key: "spring.jpa.open-in-view",
        file: "api/src/main/resources/application.yml",
      },
      {
        key: "spring.jpa.open-in-view",
        file: "batch/src/main/resources/application.yml",
      },
    ],
  }
  let relations = release_relations(
    "spring-projects/spring-boot",
    "v3.4.3",
    "Warn when `spring.jpa.open-in-view` is not set.",
    [profile],
  )
  assert_eq(relations.map(relation => relation.label), [
    "Spring Boot 3.4.2 → 3.4.3", "uses spring.jpa.open-in-view in 2 files",
  ])
  assert_eq(relations[1].evidence.length(), 2)
}

///|
test "Spring properties written as prose relate, with the keys under them" {
  let profile = {
    ..service_profile(),
    settings: [
      {
        key: "spring.threads.virtual.enabled",
        file: "api/src/main/resources/application.yml",
      },
      {
        key: "spring.security.oauth2.resourceserver.jwt.issuer-uri",
        file: "api/src/main/resources/application.yml",
      },
      { key: "server.port", file: "api/src/main/resources/application.yml", },
    ],
  }
  let notes =
    #|- RedisMessageListenerContainer does not use virtual threads when spring.threads.virtual.enabled is true
    #|- Inconsistent handling of empty values of spring.security.oauth2.resourceserver.jwt issuer-uri
    #|- See docs.spring.io for details.
  let relations = release_relations(
    "spring-projects/spring-boot",
    "v3.4.3",
    notes,
    [profile],
  )
  assert_eq(relations.map(relation => relation.label), [
    "Spring Boot 3.4.2 → 3.4.3", "uses spring.threads.virtual.enabled in api/src/main/resources/application.yml",
    "uses spring.security.oauth2.resourceserver.jwt.* in api/src/main/resources/application.yml",
  ])
}

///|
test "a newer release outside a range in the same major line is newer" {
  let profile = {
    ..service_profile(),
    tools: [
      {
        name: "hashicorp/terraform",
        version: "~> 1.10.0",
        exact: false,
        source: "terraform.tf required_version",
      },
    ],
  }
  let relations = release_relations("hashicorp/terraform", "v1.16.5", "", [
    profile,
  ])
  assert_eq(relations[0].kind, NewerThanInUse)
  assert_eq(relations[0].label, "Terraform ~> 1.10.0 → 1.16.5")
  assert_eq(relations[0].evidence[1], "~> 1.10.0 does not allow 1.16.5")
  let allowed = release_relations("hashicorp/terraform", "v1.10.4", "", [
    profile,
  ])
  assert_eq(allowed[0].kind, InUse)
}

///|
test "watch candidates are repositories known without a registry" {
  let infra = {
    ..service_profile(),
    name: "acme/infra",
    tools: [
      {
        name: "actions/checkout",
        version: "4",
        exact: false,
        source: ".github/workflows/ci.yml uses",
      },
      {
        name: "hashicorp/terraform-provider-aws",
        version: "~> 5.0",
        exact: false,
        source: "terraform.tf required_providers",
      },
      {
        name: "@acme/ui",
        version: "^1.0.0",
        exact: false,
        source: "package.json dependencies",
      },
    ],
  }
  let candidates = watch_candidates([service_profile(), web_profile(), infra], [
    "Gradle/Gradle",
  ])
  assert_eq(candidates.map(entry => entry.repository), [
    "actions/checkout", "hashicorp/terraform-provider-aws", "pnpm/pnpm", "spring-projects/spring-boot",
  ])
  assert_eq(candidates[3].projects, ["acme/service"])
  assert_eq(candidates[3].uses, ["acme/service: 3.4.2"])
}
