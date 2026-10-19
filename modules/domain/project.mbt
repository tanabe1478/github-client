///|
/// A tool or package a base project uses, and the version it asks for.
pub(all) struct ProjectTool {
  /// Package name, for example "pnpm" or "vite".
  name : String
  /// "11.4.0" when `exact`, otherwise a range such as "^11.0.0" or ">=10".
  version : String
  exact : Bool
  /// Where it was read, for example "package.json packageManager".
  source : String
} derive(Eq, Debug)

///|
/// A setting key found in a base project's configuration files.
pub(all) struct ProjectSetting {
  key : String
  /// The file that sets it, for example ".npmrc".
  file : String
} derive(Eq, Debug)

///|
/// What a base project uses, read from its files.
pub(all) struct ProjectProfile {
  /// The repository, as owner/name; also the name shown in labels.
  name : String
  /// `name` in package.json, or "".
  package_name : String
  tools : Array[ProjectTool]
  settings : Array[ProjectSetting]
  /// Files that were read.
  files : Array[String]
  dependency_count : Int
  /// Dependencies declared without a version, which a BOM such as Spring
  /// Boot's decides, as group:artifact.
  managed : Array[String]
  /// Why something could not be read; "" when everything was read.
  problem : String
  /// owner/name the repository was renamed or moved to, or "".
  moved_to : String
  /// The GitHub repository of each dependency whose registry entry names
  /// one, such as zalando/logbook for org.zalando:logbook-spring-boot-starter.
  sources : Array[PackageSource]
  /// Repositories it depends on that publish no GitHub releases.
  unreleased : Array[String]
  /// The registry an .npmrc sends npm packages to, when it is not the public
  /// one, such as a company proxy; "" otherwise. Its packages are looked up
  /// on registry.npmjs.org only when it is set as a public mirror.
  npm_registry : String
  /// Dependencies whose new versions come from their registry, since no
  /// GitHub releases can be watched for them (ADR 0008).
  followed : Array[FollowedPackage]
} derive(Eq, Debug)

///|
/// A dependency followed through its registry's versions: one whose source
/// is not on GitHub (nimbus-jose-jwt is on Bitbucket), whose GitHub
/// repository publishes no releases, or whose source is unknown.
pub(all) struct FollowedPackage {
  /// The tool name, such as "com.nimbusds:nimbus-jose-jwt" or "dotenv".
  name : String
  /// "maven" or "npm".
  ecosystem : String
  /// The Maven repository its pom came from; "" for npm.
  registry : String
  /// Where its source lives, such as "bitbucket.org"; "" when unknown.
  source_host : String
  /// owner/name on `source_host`.
  source_repository : String
} derive(Eq, Debug)

///|
/// Where a dependency's code lives, as its registry entry says: the pom's
/// url or scm on Maven Central, or `repository` on npm.
pub(all) struct PackageSource {
  /// The tool name, such as "org.zalando:logbook-spring-boot-starter".
  name : String
  /// owner/name.
  repository : String
  /// "github.com", or another source host such as "bitbucket.org", which
  /// cannot be watched.
  host : String
} derive(Eq, Debug)

///|
/// The GitHub repository a profile's registry lookups found for a tool.
pub fn source_repository(profile : ProjectProfile, name : String) -> String? {
  for source in profile.sources {
    if source.name == name && source.host == "github.com" {
      return Some(source.repository)
    }
  }
  None
}

///|
pub(all) enum RelationKind {
  /// The project uses an older major version than the release.
  MajorUpdate
  /// The project uses an exact older version in the same major line.
  NewerThanInUse
  /// The project already uses this version, a newer one, or a range that
  /// covers it. Shown, but not counted as related.
  InUse
  /// The notes name a setting found in the project's configuration.
  UsesSetting
} derive(Eq, Debug)

///|
pub fn RelationKind::name(self : RelationKind) -> String {
  match self {
    MajorUpdate => "major"
    NewerThanInUse => "newer"
    InUse => "in-use"
    UsesSetting => "setting"
  }
}

///|
/// How one release relates to one base project, with the evidence a rule
/// found. `label` excludes the project name, which is shown first.
pub(all) struct Relation {
  project : String
  kind : RelationKind
  label : String
  evidence : Array[String]
} derive(Eq, Debug)

///|
pub fn Relation::counts(self : Relation) -> Bool {
  !(self.kind is InUse)
}

///|
/// Releases of these repositories belong to a package of another name, and
/// how labels name it. A Maven group, such as "org.springframework.boot",
/// stands for its Gradle plugin and every library in the group.
let known_packages : Map[String, (String, String)] = Map([
  ("pnpm/pnpm", ("pnpm", "pnpm")),
  ("npm/cli", ("npm", "npm")),
  ("nodejs/node", ("node", "Node.js")),
  ("yarnpkg/berry", ("yarn", "yarn")),
  ("spring-projects/spring-boot", ("org.springframework.boot", "Spring Boot")),
  (
    "spring-projects/spring-framework",
    ("org.springframework", "Spring Framework"),
  ),
  ("gradle/gradle", ("gradle", "Gradle")),
  ("hashicorp/terraform", ("hashicorp/terraform", "Terraform")),
])

///|
/// The package a release belongs to: the prefix of a tag such as
/// "pnpr@0.1.0", a known repository, or the repository's name.
pub fn release_package(repository : String, tag : String) -> String {
  // A version found on a registry is named by its package, such as
  // "@types/widget" or "com.acme:widget" (ADR 0008).
  if repository.has_prefix("@") || repository.contains(":") {
    return repository
  }
  match tag.find("@") {
    Some(index) if index > 0 => return tag[:index].to_owned()
    _ => ()
  }
  match known_packages.get(repository.to_lower()) {
    Some((name, _)) => name
    None =>
      match repository.find("/") {
        Some(index) => repository[index + 1:].to_owned()
        None => repository
      }
  }
}

///|
/// How labels name a package: "Spring Boot" for org.springframework.boot,
/// otherwise the package itself.
pub fn package_label(package : String) -> String {
  for _, entry in known_packages {
    if entry.0 == package {
      return entry.1
    }
  }
  package
}

///|
/// Whether a Maven group or package is in the known table, such as
/// org.springframework for Spring Framework.
pub fn known_package(name : String) -> Bool {
  known_packages.iter().any(entry => entry.1.0 == name)
}

///|
/// Whether a tool is the package: the same name, a library in the package's
/// Maven group ("org.springframework.boot:spring-boot-starter-web"), or a
/// library whose artifact is named like the package ("com.acme:widget" for
/// a repository acme/widget).
fn tool_matches(tool : String, package : String) -> Bool {
  if tool == package || tool.has_prefix(package + ":") {
    return true
  }
  match tool.rev_find(":") {
    Some(index) => tool[index + 1:] == package
    None => false
  }
}

///|
/// What a profile's labels lead with: the package manager, engines, the
/// build tool, and the known frameworks, as "Spring Boot 4.1.1", once each.
pub fn headline_tools(profile : ProjectProfile) -> Array[String] {
  let shown : Array[String] = []
  let seen : Array[String] = []
  for tool in profile.tools {
    // A known package names the tool, its plugin, and its group's
    // libraries, such as spring-boot-starter-parent.
    let mut known : String? = None
    for _, entry in known_packages {
      if tool.name == entry.0 || tool.name.has_prefix(entry.0 + ":") {
        known = Some(entry.1)
        break
      }
    }
    let headline = known is Some(_) ||
      tool.name == "java" ||
      tool.name == "node" ||
      tool.source.has_suffix("packageManager") ||
      tool.source.has_suffix("engines") ||
      tool.source.has_suffix("parent") ||
      tool.source.has_suffix("java.version")
    let name = match tool.name {
      "java" => "Java"
      "node" => "Node.js"
      _ => known.unwrap_or(tool.name)
    }
    guard headline && !seen.contains(name) else { continue }
    seen.push(name)
    shown.push("\{name} \{tool.version}")
  }
  shown
}

///|
/// Whether a registry version is a pre-release: npm's "2.0.0-beta.1", or
/// Maven's "4.0.0-M2", "1.0-RC1", "2.0.0.Beta1", and snapshots.
pub fn prerelease_version(version : String) -> Bool {
  let lower = version.to_lower()
  if lower.contains("snapshot") {
    return true
  }
  for
    marker in [
      "alpha", "beta", "rc", "cr", "-m", ".m", "preview", "ea", "dev", "pre",
    ] {
    let mut rest = lower
    while rest.find(marker) is Some(index) {
      // A marker counts when a separator or a digit precedes it and a
      // digit, separator, or the end follows: "1.0-rc1" but not "search".
      let before = if index == 0 {
        '.'
      } else {
        rest.get_char(index - 1).unwrap_or('.')
      }
      let after = rest.get_char(index + marker.length()).unwrap_or('.')
      let separated = before == '.' ||
        before == '-' ||
        before == '_' ||
        (before >= '0' && before <= '9') ||
        marker.has_prefix("-") ||
        marker.has_prefix(".")
      let ends = after == '.' ||
        after == '-' ||
        after == '_' ||
        (after >= '0' && after <= '9')
      if separated && ends {
        return true
      }
      rest = rest[index + marker.length():].to_owned()
    }
  }
  false
}

///|
/// The newest stable version in `versions` that is newer than `used`, or
/// None. A pre-release counts only when `used` is one.
pub fn newest_version(versions : Array[String], used : String) -> String? {
  guard parse_version(used) is Some(current) else { return None }
  let stable_only = !prerelease_version(used)
  let mut best : (String, Version)? = None
  for version in versions {
    guard !stable_only || !prerelease_version(version) else { continue }
    guard parse_version(version) is Some(parsed) else { continue }
    guard parsed.compare_to(current) > 0 else { continue }
    match best {
      Some((_, kept)) if parsed.compare_to(kept) <= 0 => ()
      _ => best = Some((version, parsed))
    }
  }
  best.map(entry => entry.0)
}

///|
/// A version as numbers, ignoring a prefix such as "v", "^", or ">=" and
/// any pre-release or build suffix. Missing parts count as zero.
pub(all) struct Version {
  major : Int
  minor : Int
  patch : Int
} derive(Eq, Debug)

///|
pub fn Version::compare_to(self : Version, other : Version) -> Int {
  if self.major != other.major {
    self.major - other.major
  } else if self.minor != other.minor {
    self.minor - other.minor
  } else {
    self.patch - other.patch
  }
}

///|
pub fn Version::text(self : Version) -> String {
  "\{self.major}.\{self.minor}.\{self.patch}"
}

///|
/// The first version in `value`, for example 12.12.0 in "v12.12.0",
/// "pnpm@12.12.0", or "^12.12.0"; None when it has no number.
pub fn parse_version(value : String) -> Version? {
  let text = match value.find("@") {
    Some(index) if index > 0 => value[index + 1:].to_owned()
    _ => value
  }
  let numbers : Array[Int] = []
  let mut current = -1
  let mut started = false
  for character in text {
    if character >= '0' && character <= '9' {
      started = true
      let digit = character.to_int() - '0'.to_int()
      current = if current < 0 { digit } else { current * 10 + digit }
    } else if started {
      if current >= 0 {
        numbers.push(current)
        current = -1
      }
      if character != '.' || numbers.length() == 3 {
        break
      }
    }
  }
  if current >= 0 && numbers.length() < 3 {
    numbers.push(current)
  }
  guard numbers.length() > 0 else { return None }
  Some({
    major: numbers[0],
    minor: if numbers.length() > 1 {
      numbers[1]
    } else {
      0
    },
    patch: if numbers.length() > 2 {
      numbers[2]
    } else {
      0
    },
  })
}

///|
/// Lowercase without "-" and "_", so `workspace-concurrency` in .npmrc and
/// `workspaceConcurrency` in pnpm-workspace.yaml compare equal.
fn setting_form(value : String) -> String {
  let builder = StringBuilder()
  for character in value.to_lower() {
    if character != '-' && character != '_' {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
/// Code spans (`...`) of release notes that name a single setting, in
/// setting form: `registry`, `--workspace-concurrency=Infinity`,
/// `addMissingPeerTypes: true`, or `org.gradle.caching=true`. A span such as
/// `pnpm add --config` names no setting, and `registry.npmjs.com` matches
/// only a key spelled the same, never `registry`.
pub fn code_words(notes : String) -> Map[String, String] {
  let words : Map[String, String] = Map([])
  let parts = notes.split("`").to_array()
  // Odd parts are inside code spans.
  for index = 1; index < parts.length(); index = index + 2 {
    let span = parts[index].trim().trim_start(chars="-").to_owned()
    let word = match span.find("=") {
      Some(at) => span[:at].trim().to_owned()
      None =>
        match span.find(":") {
          Some(at) => span[:at].trim().to_owned()
          None => span
        }
    }
    let plain = word.length() >= 4 &&
      word
      .iter()
      .all(character => {
        (character >= 'a' && character <= 'z') ||
        (character >= 'A' && character <= 'Z') ||
        (character >= '0' && character <= '9') ||
        character == '-' ||
        character == '_' ||
        character == '.'
      })
    if plain && !words.contains(setting_form(word)) {
      words.set(setting_form(word), word)
    }
  }
  words
}

///|
/// Words of release notes that can name a setting: code spans
/// (`code_words`), and dotted property names written as prose, such as
/// spring.threads.virtual.enabled, with at least two dots.
pub fn setting_words(notes : String) -> Map[String, String] {
  let words = code_words(notes)
  let current = StringBuilder()
  let flush = fn() {
    let word = current.to_string().trim(chars=".").to_owned()
    current.reset()
    let dots = word.iter().filter(character => character == '.').count()
    let starts = match word.get_char(0) {
      Some(character) => character >= 'a' && character <= 'z'
      None => false
    }
    if dots >= 2 && starts && !words.contains(setting_form(word)) {
      words.set(setting_form(word), word)
    }
  }
  for character in notes {
    let part = (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '.' ||
      character == '-' ||
      character == '_'
    if part {
      current.write_char(character)
    } else {
      flush()
    }
  }
  flush()
  words
}

///|
/// The tool entry the rules use for a package: the oldest exact version,
/// else the oldest range. A directory holding several packages is judged by
/// the one furthest behind.
fn tool_for(
  profile : ProjectProfile,
  repository : String,
  package : String,
) -> ProjectTool? {
  let mut exact : (ProjectTool, Version)? = None
  let mut range : (ProjectTool, Version)? = None
  for tool in profile.tools {
    // A GitHub Action or a Terraform provider is named by its repository,
    // and a library's registry entry can name it: io.sentry:sentry-logback
    // comes from getsentry/sentry-java.
    guard tool_matches(tool.name, package) ||
      tool.name.to_lower() == repository.to_lower() ||
      (
        source_repository(profile, tool.name) is Some(found) &&
        found.to_lower() == repository.to_lower()
      ) else {
      continue
    }
    guard parse_version(tool.version) is Some(version) else { continue }
    let slot = if tool.exact { exact } else { range }
    // On a tie the tool named exactly like the package wins, so evidence
    // names the Spring Boot plugin rather than one of its libraries.
    let keep = match slot {
      Some((current_tool, current)) => {
        let order = version.compare_to(current)
        order < 0 ||
        (order == 0 && tool.name == package && current_tool.name != package)
      }
      None => true
    }
    if keep {
      if tool.exact {
        exact = Some((tool, version))
      } else {
        range = Some((tool, version))
      }
    }
  }
  match exact {
    Some((tool, _)) => Some(tool)
    None => range.map(entry => entry.0)
  }
}

///|
/// How many version numbers `text` writes: 1 for "v4" or "22", 2 for
/// "~> 5.0", 3 for "11.4.0".
fn written_parts(text : String) -> Int {
  let mut parts = 0
  let mut in_number = false
  for character in text {
    if character >= '0' && character <= '9' {
      if !in_number {
        parts += 1
        in_number = true
      }
    } else if character == '.' && in_number {
      in_number = false
    } else if in_number {
      break
    }
  }
  parts
}

///|
/// Whether a range such as "^11.0.0", "~11.4.0", ">=10", Terraform's
/// "~> 5.0", or a version line such as "v4" or "22" allows `version`. A
/// range with no upper bound allows every newer version.
pub fn range_allows(range : String, lower : Version, version : Version) -> Bool {
  let text = range.trim().to_owned()
  let same_major = version.major == lower.major
  let same_minor = same_major && version.minor == lower.minor
  if version.compare_to(lower) < 0 {
    false
  } else if text.has_prefix("~>") {
    // Terraform: "~> 5.0" stays in 5, "~> 1.8.0" stays in 1.8.
    if written_parts(text) >= 3 {
      same_minor
    } else {
      same_major
    }
  } else if text.has_prefix("^") {
    same_major
  } else if text.has_prefix("~") {
    same_minor
  } else if text.has_prefix(">") || text.contains("*") {
    true
  } else if text.contains("x") || written_parts(text) < 3 {
    // A line: "22", "v4", or "4.x" is the newest 22 or 4; "4.1" or
    // "4.1.x" the newest 4.1.
    if written_parts(text) >= 2 {
      same_minor
    } else {
      same_major
    }
  } else {
    // An exact version written as a range allows only itself.
    version.compare_to(lower) == 0
  }
}

///|
/// The version as the tag writes it, with a pre-release suffix such as
/// "4.2.0-M2": "v4.2.0-M2" and "pnpr@0.1.0-alpha.15" give the part after
/// the "v" or "@". None when that part does not start with a digit.
fn tag_version(tag : String) -> String? {
  let rest = match tag.find("@") {
    Some(index) if index > 0 => tag[index + 1:].to_owned()
    _ => if tag.has_prefix("v") { tag[1:].to_owned() } else { tag }
  }
  if exact_digit(rest) {
    Some(rest)
  } else {
    None
  }
}

///|
fn exact_digit(text : String) -> Bool {
  match text.get_char(0) {
    Some(character) => character >= '0' && character <= '9'
    None => false
  }
}

///|
/// How a release relates to each base project. Projects that do not use the
/// release's package get no relation.
pub fn release_relations(
  repository : String,
  tag : String,
  notes : String,
  profiles : Array[ProjectProfile],
) -> Array[Relation] {
  let relations : Array[Relation] = []
  let package = release_package(repository, tag)
  guard parse_version(tag) is Some(released) else { return relations }
  let words = setting_words(notes)
  let label = package_label(package)
  let shown = tag_version(tag).unwrap_or(released.text())
  for profile in profiles {
    guard tool_for(profile, repository, package) is Some(tool) else { continue }
    let label = if tool.name.to_lower() == repository.to_lower() &&
      !known_package(tool.name) {
      repository
    } else {
      label
    }
    guard parse_version(tool.version) is Some(used) else { continue }
    let used_text = if tool.exact { used.text() } else { tool.version }
    let from = "\{tool.source} sets \{tool.name}: \{tool.version}"
    let order = released.compare_to(used)
    if !tool.exact && range_allows(tool.version, used, released) {
      relations.push({
        project: profile.name,
        kind: InUse,
        label: "\{used_text} allows \{shown}",
        evidence: [from],
      })
      continue
    }
    if released.major > used.major {
      relations.push({
        project: profile.name,
        kind: MajorUpdate,
        label: "\{label} \{used_text} → \{shown} · Major update",
        evidence: [
          from,
          "\{shown} is in major line \{released.major}; the project is on \{used.major}",
        ],
      })
    } else if order > 0 {
      // Newer in the same major line: an exact version, or a range such as
      // Terraform's "~> 1.10.0" that has to change to allow it.
      relations.push({
        project: profile.name,
        kind: NewerThanInUse,
        label: "\{label} \{used_text} → \{shown}",
        evidence: [
          from,
          if tool.exact {
            "\{shown} is newer than \{used.text()}"
          } else {
            "\{used_text} does not allow \{shown}"
          },
        ],
      })
    } else {
      let label = if tool.exact {
        "\{used_text} in use"
      } else {
        "\{used_text} does not allow \{shown}"
      }
      relations.push({
        project: profile.name,
        kind: InUse,
        label,
        evidence: [from],
      })
    }
    // A setting matters only for a release the project has not adopted.
    guard order > 0 else { continue }
    // One relation per word the notes name, however many keys and files it
    // covers, such as application.yml in every module. A dotted word also
    // covers the keys under it: spring.security.oauth2 covers
    // spring.security.oauth2.resourceserver.jwt.issuer-uri.
    let matched : Array[(String, String, Array[ProjectSetting])] = []
    for setting in profile.settings {
      let key = setting_form(setting.key)
      for form, word in words {
        let covers = key == form ||
          (form.contains(".") && key.has_prefix(form + "."))
        guard covers else { continue }
        match matched.search_by(entry => entry.0 == form) {
          Some(index) => matched[index].2.push(setting)
          None => matched.push((form, word, [setting]))
        }
      }
    }
    for entry in matched {
      let (form, word, settings) = entry
      let first = settings[0]
      let files : Array[String] = []
      for setting in settings {
        if !files.contains(setting.file) {
          files.push(setting.file)
        }
      }
      let where_ = if files.length() == 1 {
        files[0]
      } else {
        "\{files.length()} files"
      }
      let named = if setting_form(first.key) == form {
        first.key
      } else {
        word + ".*"
      }
      relations.push({
        project: profile.name,
        kind: UsesSetting,
        label: "uses \{named} in \{where_}",
        evidence: settings.map(setting => {
          "The notes name \{word}; \{setting.file} sets \{setting.key}"
        }),
      })
    }
  }
  relations
}

///|
/// A repository the base projects depend on that could be watched for its
/// releases.
pub(all) struct WatchCandidate {
  /// owner/name.
  repository : String
  /// Base projects that use it.
  projects : Array[String]
  /// What each use reads, such as "acme/web: 4.4.0".
  uses : Array[String]
  /// false when the repository publishes no GitHub releases, so watching
  /// it brings nothing into Releases.
  released : Bool
} derive(Eq, Debug)

///|
/// The repository a tool's releases come from, when that is known without
/// asking a registry: a GitHub Action or a Terraform provider is named by
/// its repository, and the known packages (pnpm, Spring Boot, Gradle, ...)
/// come from the table.
pub fn tool_repository(tool : ProjectTool) -> String? {
  let name = tool.name
  let parts = name.split("/").to_array()
  if parts.length() == 2 &&
    !name.has_prefix("@") &&
    !name.contains(":") &&
    parts[0] != "" &&
    parts[1] != "" {
    return Some(name)
  }
  for repository, entry in known_packages {
    if tool_matches(name, entry.0) {
      return Some(repository)
    }
  }
  None
}

///|
/// The repositories a profile depends on: those named by the tools
/// themselves and those the registry lookups found.
pub fn depended_repositories(profile : ProjectProfile) -> Array[String] {
  let found : Array[String] = []
  for tool in profile.tools {
    let repository = match tool_repository(tool) {
      Some(repository) => Some(repository)
      None => source_repository(profile, tool.name)
    }
    match repository {
      Some(name) if !found.contains(name) => found.push(name)
      _ => ()
    }
  }
  found
}

///|
/// Repositories the base projects depend on and `watched` does not hold.
/// Those with GitHub releases come first, then the ones most projects use.
pub fn watch_candidates(
  profiles : Array[ProjectProfile],
  watched : Array[String],
) -> Array[WatchCandidate] {
  let watched_keys = watched.map(name => name.to_lower())
  let found : Array[WatchCandidate] = []
  for profile in profiles {
    for tool in profile.tools {
      // A library found through its registry names its package, since one
      // repository can hold many, such as DefinitelyTyped's @types.
      let (repository, named) = match tool_repository(tool) {
        Some(repository) => (repository, false)
        None =>
          match source_repository(profile, tool.name) {
            Some(repository) => (repository, true)
            None => continue
          }
      }
      guard !watched_keys.contains(repository.to_lower()) else { continue }
      let use_ = if named {
        "\{profile.name}: \{tool.name} \{tool.version}"
      } else {
        "\{profile.name}: \{tool.version}"
      }
      // The first package stands for the others at the same version, such
      // as AWS SDK's service clients.
      let same_version = (entry : WatchCandidate) => {
        entry.uses.any(other => {
          other.has_prefix("\{profile.name}: ") &&
          other.has_suffix(" \{tool.version}")
        })
      }
      match found.search_by(entry => entry.repository == repository) {
        Some(index) => {
          let entry = found[index]
          if !entry.projects.contains(profile.name) {
            entry.projects.push(profile.name)
          }
          if !entry.uses.contains(use_) && !(named && same_version(entry)) {
            entry.uses.push(use_)
          }
        }
        None =>
          found.push({
            repository,
            projects: [profile.name],
            uses: [use_],
            released: !profiles.any(profile => {
              profile.unreleased.contains(repository)
            }),
          })
      }
    }
  }
  found.sort_by((a, b) => {
    let released = b.released.compare(a.released)
    let order = if released != 0 {
      released
    } else {
      b.projects.length().compare(a.projects.length())
    }
    if order != 0 {
      order
    } else {
      alphabetical(a.repository, b.repository)
    }
  })
  found
}

///|
/// Dictionary order, ignoring case; String::compare puts shorter strings
/// first.
fn alphabetical(a : String, b : String) -> Int {
  let left = a.to_lower().to_array()
  let right = b.to_lower().to_array()
  let shorter = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index = 0; index < shorter; index = index + 1 {
    if left[index] != right[index] {
      return left[index].compare(right[index])
    }
  }
  left.length().compare(right.length())
}
