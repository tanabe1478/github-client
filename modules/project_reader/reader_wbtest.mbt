///|
test "remote URLs give owner/name" {
  assert_eq(
    github_name_from_url("https://github.com/acme/storefront.git"),
    Some("acme/storefront"),
  )
  assert_eq(
    github_name_from_url("git@github.com:tanabe1478/github-client.git"),
    Some("tanabe1478/github-client"),
  )
  assert_eq(github_name_from_url("https://gitlab.com/a/b"), None)
  let config =
    #|[core]
    #|	bare = false
    #|[remote "upstream"]
    #|	url = https://github.com/other/repo.git
    #|[remote "origin"]
    #|	url = https://github.com/acme/web.git
  assert_eq(origin_name(config), Some("acme/web"))
}

///|
test "package.json gives tools, the package name, and dependencies" {
  let profile = parse_files("acme/web", [
    (
      "package.json",
      (
        #|{"name": "@acme/web", "packageManager": "pnpm@10.27.0+sha512.abc",
        #| "engines": {"node": ">=22.14.0", "npm": ">=10.0.0"},
        #| "dependencies": {"react": "^19.0.0", "lib": "workspace:*"},
        #| "devDependencies": {"vite": "5.2.0"}}
      ),
    ),
    (
      ".npmrc", "registry=https://registry.npmjs.org/\n//npm.pkg.github.com/:_authToken=secret\nauto-install-peers=true\n",
    ),
    (
      "pnpm-workspace.yaml", "packages:\n  - apps/*\nonlyBuiltDependencies:\n  - esbuild\n",
    ),
  ])
  assert_eq(profile.package_name, "@acme/web")
  assert_eq(profile.dependency_count, 3)
  let pnpm = profile.tools.filter(tool => tool.name == "pnpm")
  assert_eq(pnpm[0].version, "10.27.0")
  assert_true(pnpm[0].exact)
  assert_eq(pnpm[0].source, "package.json packageManager")
  assert_true(profile.tools.any(tool => tool.name == "vite" && tool.exact))
  assert_false(profile.tools.any(tool => tool.name == "lib"))
  assert_eq(profile.settings.map(setting => setting.key), [
    "registry", "auto-install-peers", "onlyBuiltDependencies",
  ])
  assert_eq(profile.problem, "")
}

///|
test "a repository without package.json is not a problem" {
  // A Java project, for example: readable, with nothing this version reads.
  let profile = parse_files("acme/service", [])
  assert_eq(profile.problem, "")
  assert_eq(profile.files, [])
  let broken = parse_files("acme/web", [("package.json", "{not json")])
  assert_eq(broken.problem, "Couldn't read package.json: it is not valid JSON.")
}

///|
test "base64 from the contents API decodes with line breaks" {
  assert_eq(decode_base64("eyJuYW1lIjoi\nd2ViIn0=\n"), "{\"name\":\"web\"}")
}

///|
test "repository_input reads a pasted GitHub URL as owner/name" {
  assert_eq(repository_input(" https://github.com/acme/web "), "acme/web")
  assert_eq(repository_input("https://github.com/acme/web.git"), "acme/web")
  assert_eq(repository_input("acme/web"), "acme/web")
  assert_eq(repository_input("~/work"), "~/work")
}

///|
test "a Gradle version catalog gives its plugins and libraries" {
  let catalog =
    #|[versions]
    #|spring-boot = "3.4.2"
    #|guava = { strictly = "33.0.0-jre" }
    #|
    #|[libraries]
    #|boot-web = { module = "org.springframework.boot:spring-boot-starter-web", version.ref = "spring-boot" }
    #|guava = { group = "com.google.guava", name = "guava", version.ref = "guava" }
    #|widget = "com.acme:widget:1.2.0"
    #|session = { module = "org.springframework.session:spring-session-data-redis" }
    #|dynamic = { module = "com.acme:dynamic", version = "2.+" }
    #|
    #|[plugins]
    #|spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
    #|lint = "com.acme.lint:0.9.0"
  let wrapper = "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.12.1-bin.zip\n"
  let profile = parse_files("acme/service", [
    ("gradle/libs.versions.toml", catalog),
    ("gradle/wrapper/gradle-wrapper.properties", wrapper),
    ("gradle.properties", "org.gradle.caching=true\nsecret.token=abc\n"),
  ])
  let found = profile.tools.map(tool => {
    "\{tool.name} \{tool.version} \{tool.exact}"
  })
  assert_eq(found, [
    "org.springframework.boot:spring-boot-starter-web 3.4.2 true", "com.google.guava:guava 33.0.0-jre true",
    "com.acme:widget 1.2.0 true", "com.acme:dynamic 2.+ false", "org.springframework.boot 3.4.2 true",
    "com.acme.lint 0.9.0 true", "gradle 8.12.1 true",
  ])
  assert_eq(profile.dependency_count, 5)
  assert_eq(profile.settings.map(setting => setting.key), [
    "org.gradle.caching", "secret.token",
  ])
  assert_eq(profile.problem, "")
  assert_eq(@domain.headline_tools(profile), [
    "Spring Boot 3.4.2", "Gradle 8.12.1",
  ])
}

///|
test "a build script gives versioned plugins and dependency strings" {
  let script =
    #|plugins {
    #|    id("org.springframework.boot") version "3.4.2"
    #|    id 'io.spring.dependency-management' version '1.1.7'
    #|    alias(libs.plugins.lint)
    #|}
    #|dependencies {
    #|    implementation("com.acme:widget:1.2.0")
    #|    // implementation("com.acme:old:0.1.0")
    #|    implementation("org.springframework.boot:spring-boot-starter-web")
    #|}
  let profile = parse_files("acme/service", [("build.gradle.kts", script)])
  assert_eq(profile.tools.map(tool => "\{tool.name} \{tool.version}"), [
    "org.springframework.boot 3.4.2", "io.spring.dependency-management 1.1.7", "com.acme:widget 1.2.0",
  ])
  assert_eq(profile.dependency_count, 2)
  assert_eq(profile.managed, [
    "org.springframework.boot:spring-boot-starter-web",
  ])
}

///|
test "a pom gives its parent, java.version, and versioned dependencies" {
  let pom =
    #|<project>
    #|  <parent>
    #|    <groupId>org.springframework.boot</groupId>
    #|    <artifactId>spring-boot-starter-parent</artifactId>
    #|    <version>3.4.2</version>
    #|  </parent>
    #|  <properties>
    #|    <java.version>21</java.version>
    #|    <widget.version>1.2.0</widget.version>
    #|  </properties>
    #|  <dependencies>
    #|    <dependency>
    #|      <groupId>org.springframework.boot</groupId>
    #|      <artifactId>spring-boot-starter-web</artifactId>
    #|    </dependency>
    #|    <dependency>
    #|      <groupId>com.acme</groupId>
    #|      <artifactId>widget</artifactId>
    #|      <version>${widget.version}</version>
    #|    </dependency>
    #|    <!-- <dependency><groupId>com.acme</groupId><artifactId>old</artifactId><version>0.1.0</version></dependency> -->
    #|  </dependencies>
    #|</project>
  let profile = parse_files("acme/service", [("pom.xml", pom)])
  assert_eq(profile.tools.map(tool => "\{tool.name} \{tool.version}"), [
    "org.springframework.boot:spring-boot-starter-parent 3.4.2", "java 21", "com.acme:widget 1.2.0",
  ])
  assert_eq(profile.dependency_count, 2)
  assert_eq(@domain.headline_tools(profile), ["Spring Boot 3.4.2", "Java 21"])
}

///|
test "project paths keep build files at any depth, outside tests and builds" {
  let paths = project_paths([
    "README.md", "build.gradle.kts", "settings.gradle.kts", ".sdkmanrc", "gradle/libs.versions.toml",
    "gradle/wrapper/gradle-wrapper.properties", "buildSrc/build.gradle.kts", "buildSrc/src/main/kotlin/acme.java-base.gradle.kts",
    "service/build.gradle.kts", "service/src/main/resources/application.yml", "service/src/test/resources/application-it.yml",
    "service/build/tmp/pom.xml", "web/package.json", "web/node_modules/left-pad/package.json",
    "examples/demo/pom.xml", "service/gradle.properties",
  ])
  // Shallower first; the order within a depth does not matter.
  assert_eq(paths, [
    ".sdkmanrc", "build.gradle.kts", "settings.gradle.kts", "web/package.json", "service/build.gradle.kts",
    "buildSrc/build.gradle.kts", "gradle/libs.versions.toml", "gradle/wrapper/gradle-wrapper.properties",
    "service/src/main/resources/application.yml", "buildSrc/src/main/kotlin/acme.java-base.gradle.kts",
  ])
}

///|
test "the Java version comes from toolchains, sdkman, and poms" {
  let convention =
    #|java {
    #|    sourceCompatibility = JavaVersion.VERSION_21
    #|    toolchain {
    #|        languageVersion = JavaLanguageVersion.of(21)
    #|    }
    #|}
  let profile = parse_files("acme/service", [
    (".sdkmanrc", "# sdkman\njava=21.0.6-tem\n"),
    ("buildSrc/src/main/kotlin/acme.java-base.gradle.kts", convention),
  ])
  assert_eq(profile.tools.map(tool => "\{tool.version} \{tool.source}"), [
    "21.0.6 .sdkmanrc", "21 buildSrc/src/main/kotlin/acme.java-base.gradle.kts toolchain",
  ])
  assert_eq(@domain.headline_tools(profile), ["Java 21.0.6"])
  let pom = "<project><properties><maven.compiler.release>17</maven.compiler.release></properties></project>"
  let maven = parse_files("acme/legacy", [("pom.xml", pom)])
  assert_eq(maven.tools.map(tool => "\{tool.name} \{tool.version}"), ["java 17"])
}

///|
test "Spring settings are dotted keys, never values" {
  let yaml =
    #|spring:
    #|  jpa:
    #|    open-in-view: false
    #|  datasource:
    #|    url: jdbc:postgresql://localhost/acme
    #|    password: ${DB_PASSWORD}
    #|server:
    #|  port: 8080
    #|logging.level.root: info
    #|management:
    #|  endpoints:
    #|    web:
    #|      exposure:
    #|        include:
    #|          - health
    #|---
    #|spring:
    #|  config:
    #|    activate:
    #|      on-profile: local
  assert_eq(yaml_keys(yaml), [
    "spring.jpa.open-in-view", "spring.datasource.url", "spring.datasource.password",
    "server.port", "logging.level.root", "spring.config.activate.on-profile",
  ])
  let profile = parse_files("acme/service", [
    ("service/src/main/resources/application.yml", yaml),
    (
      "service/src/main/resources/application-local.properties", "spring.jpa.show-sql=true\n",
    ),
  ])
  assert_eq(profile.settings.length(), 7)
  assert_eq(profile.settings[6].key, "spring.jpa.show-sql")
  assert_false(
    profile.settings.any(setting => setting.key.contains("postgresql")),
  )
}

///|
test "a BOM decides the versions left to it and known packages" {
  let catalog =
    #|[versions]
    #|spring-boot = "3.4.2"
    #|[libraries]
    #|web = { module = "org.springframework.boot:spring-boot-starter-web" }
    #|session = { module = "org.springframework.session:spring-session-data-redis" }
    #|[plugins]
    #|spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
  let profile = parse_files("acme/service", [
    ("gradle/libs.versions.toml", catalog),
  ])
  assert_eq(bom_coordinates(profile), [
    ("org.springframework.boot", "spring-boot-dependencies", "3.4.2"),
  ])
  let bom =
    #|<project>
    #|  <properties>
    #|    <spring-framework.version>6.2.2</spring-framework.version>
    #|    <spring-session.version>3.4.1</spring-session.version>
    #|  </properties>
    #|  <dependencyManagement><dependencies>
    #|    <dependency>
    #|      <groupId>org.springframework.boot</groupId>
    #|      <artifactId>spring-boot-starter-web</artifactId>
    #|      <version>3.4.2</version>
    #|    </dependency>
    #|    <dependency>
    #|      <groupId>org.springframework</groupId>
    #|      <artifactId>spring-framework-bom</artifactId>
    #|      <version>${spring-framework.version}</version>
    #|      <type>pom</type>
    #|      <scope>import</scope>
    #|    </dependency>
    #|    <dependency>
    #|      <groupId>org.springframework.session</groupId>
    #|      <artifactId>spring-session-bom</artifactId>
    #|      <version>${spring-session.version}</version>
    #|      <type>pom</type>
    #|      <scope>import</scope>
    #|    </dependency>
    #|    <dependency>
    #|      <groupId>com.acme</groupId>
    #|      <artifactId>unused</artifactId>
    #|      <version>9.9.9</version>
    #|    </dependency>
    #|  </dependencies></dependencyManagement>
    #|</project>
  let resolved = apply_bom(profile, bom_coordinates(profile)[0], bom)
  let added = resolved.tools
    .filter(tool => tool.source == "Spring Boot 3.4.2 BOM")
    .map(tool => "\{tool.name} \{tool.version}")
  assert_eq(added, [
    "org.springframework.boot:spring-boot-starter-web 3.4.2", "org.springframework.session:spring-session-data-redis 3.4.1",
    "org.springframework:spring-framework-bom 6.2.2",
  ])
  let relations = @domain.release_relations(
    "spring-projects/spring-framework",
    "v6.2.3",
    "",
    [resolved],
  )
  assert_eq(relations[0].label, "Spring Framework 6.2.2 → 6.2.3")
  assert_eq(
    relations[0].evidence[0],
    "Spring Boot 3.4.2 BOM sets org.springframework:spring-framework-bom: 6.2.2",
  )
}
