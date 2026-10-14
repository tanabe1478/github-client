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
} derive(Eq, Debug)

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
  ("nodejs/node", ("node", "node")),
  ("yarnpkg/berry", ("yarn", "yarn")),
  ("spring-projects/spring-boot", ("org.springframework.boot", "Spring Boot")),
  (
    "spring-projects/spring-framework",
    ("org.springframework", "Spring Framework"),
  ),
  ("gradle/gradle", ("gradle", "Gradle")),
])

///|
/// The package a release belongs to: the prefix of a tag such as
/// "pnpr@0.1.0", a known repository, or the repository's name.
pub fn release_package(repository : String, tag : String) -> String {
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
      tool.source.has_suffix("packageManager") ||
      tool.source.has_suffix("engines") ||
      tool.source.has_suffix("parent") ||
      tool.source.has_suffix("java.version")
    let name = if tool.name == "java" {
      "Java"
    } else {
      known.unwrap_or(tool.name)
    }
    guard headline && !seen.contains(name) else { continue }
    seen.push(name)
    shown.push("\{name} \{tool.version}")
  }
  shown
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
fn tool_for(profile : ProjectProfile, package : String) -> ProjectTool? {
  let mut exact : (ProjectTool, Version)? = None
  let mut range : (ProjectTool, Version)? = None
  for tool in profile.tools {
    guard tool_matches(tool.name, package) else { continue }
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
/// Whether a range such as "^11.0.0", "~11.4.0", or ">=10" allows
/// `version`. A range with no upper bound allows every newer version.
pub fn range_allows(range : String, lower : Version, version : Version) -> Bool {
  let text = range.trim()
  if version.compare_to(lower) < 0 {
    false
  } else if text.has_prefix("^") {
    version.major == lower.major
  } else if text.has_prefix("~") {
    version.major == lower.major && version.minor == lower.minor
  } else if text.has_prefix(">") || text.contains("x") || text.contains("*") {
    true
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
    guard tool_for(profile, package) is Some(tool) else { continue }
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
    } else if order > 0 && tool.exact {
      relations.push({
        project: profile.name,
        kind: NewerThanInUse,
        label: "\{label} \{used_text} → \{shown}",
        evidence: [from, "\{shown} is newer than \{used.text()}"],
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
