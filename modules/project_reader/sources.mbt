///|
/// A registry entry to look up for a dependency's GitHub repository
/// (ADR 0007). Only public package names are sent.
pub(all) enum PackageLookup {
  /// group, artifact, version: the pom on Maven Central, or for a Gradle
  /// build the Gradle Plugin Portal.
  Maven(String, String, String)
  /// A Gradle plugin id and version, looked up through its marker pom on
  /// the Gradle Plugin Portal.
  GradlePlugin(String, String)
  /// An npm package, looked up on registry.npmjs.org.
  Npm(String)
} derive(Eq, Debug)

///|
/// The tool name the lookup is for.
pub fn PackageLookup::tool_name(self : PackageLookup) -> String {
  match self {
    Maven(group, artifact, _) => "\{group}:\{artifact}"
    GradlePlugin(id, _) => id
    Npm(name) => name
  }
}

///|
/// Registries that serve public npm packages.
let public_npm_registries : Array[String] = [
  "https://registry.npmjs.org", "https://registry.yarnpkg.com",
]

///|

///|
/// A registry URL without the trailing slash, as settings keep it.
pub fn registry_key(url : String) -> String {
  url.trim().trim_end(chars="/").to_owned()
}

///|
fn public_npm_registry(url : String) -> Bool {
  public_npm_registries.contains(registry_key(url))
}

///|
/// The non-public registry an .npmrc sends unscoped packages to.
fn npm_default_registry(source : String) -> String? {
  let scopes : Map[String, Bool] = Map([])
  match npm_registries(source, scopes) {
    Some(false) => {
      for raw in source.split("\n") {
        let line = raw.trim().to_owned()
        guard line.find("=") is Some(index) else { continue }
        if line[:index].trim() == "registry" {
          return Some(registry_key(line[index + 1:].to_owned()))
        }
      }
      None
    }
    _ => None
  }
}

///|
/// The registries an .npmrc names: whether each scope's registry is public,
/// and whether the default registry is, when it sets one.
fn npm_registries(source : String, scopes : Map[String, Bool]) -> Bool? {
  let mut default_public : Bool? = None
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    guard line.find("=") is Some(index) else { continue }
    let key = line[:index].trim().to_owned()
    let value = line[index + 1:].trim().to_owned()
    if key == "registry" {
      default_public = Some(public_npm_registry(value))
    } else if key.has_prefix("@") && key.has_suffix(":registry") {
      scopes.set(
        key[:key.length() - ":registry".length()].to_owned(),
        public_npm_registry(value),
      )
    }
  }
  default_public
}

///|
/// The project's own Maven groups: `group = "..."` in a Gradle script and
/// the `<groupId>` of a pom, outside `<parent>`.
fn own_groups(files : Array[(String, String)]) -> Array[String] {
  let groups : Array[String] = []
  for entry in files {
    let (path, source) = entry
    match file_kind(path) {
      GradleScript =>
        for raw in source.split("\n") {
          let line = raw.trim().to_owned()
          guard line.has_prefix("group ") || line.has_prefix("group=") else {
            continue
          }
          let strings = quoted_strings(line)
          if strings.length() == 1 && !groups.contains(strings[0]) {
            groups.push(strings[0])
          }
        }
      Pom => {
        let outside = match source.find("<parent>") {
          Some(start) =>
            match source.find("</parent>") {
              Some(end) =>
                source[:start].to_owned() +
                source[end + "</parent>".length():].to_owned()
              None => source
            }
          None => source
        }
        match xml_text(outside, "groupId") {
          Some(group) if group != "" && !groups.contains(group) =>
            groups.push(group)
          _ => ()
        }
      }
      _ => ()
    }
  }
  groups
}

///|
/// The registry lookups for a profile's dependencies whose repository is not
/// known otherwise: Maven libraries with an exact version, Gradle plugins,
/// and npm packages. The project's own groups and npm packages served by
/// another registry (an .npmrc `registry` or `@scope:registry`) are left
/// out, so their names stay in the project.
pub fn package_lookups(
  profile : @domain.ProjectProfile,
  files : Array[(String, String)],
  npm_mirrors? : Array[String] = [],
) -> Array[PackageLookup] {
  let mirrors = npm_mirrors.map(registry_key)
  let groups = own_groups(files)
  // npm sends a scoped package to its scope's registry, and everything
  // else to the default one.
  let scopes : Map[String, Bool] = Map([])
  let mut default_public = true
  for entry in files {
    let (path, source) = entry
    if file_kind(path) is Npmrc {
      match npm_registries(source, scopes) {
        Some(public_) =>
          default_public = default_public &&
            (
              public_ ||
              npm_default_registry(source).map(url => mirrors.contains(url)) ==
              Some(true)
            )
        None => ()
      }
      // A scope sent to a mirror of npm is public too.
      for raw in source.split("\n") {
        let line = raw.trim().to_owned()
        guard line.has_prefix("@") && line.find(":registry=") is Some(index) else {
          continue
        }
        let scope = line[:index].to_owned()
        let url = registry_key(line[index + ":registry=".length():].to_owned())
        if mirrors.contains(url) {
          scopes.set(scope, true)
        }
      }
    }
  }
  let lookups : Array[PackageLookup] = []
  for tool in profile.tools {
    guard @domain.tool_repository(tool) is None else { continue }
    let lookup = if tool.source.contains("package.json ") {
      guard tool.source.has_suffix("ependencies") else { continue }
      let public_ = match tool.name.find("/") {
        Some(index) if tool.name.has_prefix("@") =>
          scopes.get(tool.name[:index].to_owned()).unwrap_or(default_public)
        _ => default_public
      }
      guard public_ else { continue }
      Npm(tool.name)
    } else if tool.name.contains(":") {
      let parts = tool.name.split(":").to_array()
      guard parts.length() == 2 && tool.exact && single_version(tool.version) else {
        continue
      }
      let group = parts[0].to_owned()
      guard !groups.any(own => group == own || group.has_prefix(own + ".")) else {
        continue
      }
      Maven(group, parts[1].to_owned(), tool.version)
    } else if tool.source.has_suffix(" plugins") &&
      tool.exact &&
      single_version(tool.version) {
      GradlePlugin(tool.name, tool.version)
    } else {
      continue
    }
    if !lookups.contains(lookup) {
      lookups.push(lookup)
    }
  }
  lookups
}

///|
/// Hosts a source URL can name. A source on a host other than GitHub is
/// found, but cannot be watched.
let source_hosts : Array[String] = ["github.com", "gitlab.com", "bitbucket.org"]

///|
/// owner/name without what follows a repository name in a URL: "#readme",
/// a query, ".git", or the end of an XML or JSON value.
fn clean_repository(name : String?) -> String? {
  guard name is Some(text) else { return None }
  let parts = text.split("/").to_array()
  guard parts.length() >= 2 else { return None }
  let builder = StringBuilder()
  for character in parts[1] {
    if character == '#' ||
      character == '?' ||
      character == '"' ||
      character == '<' ||
      character == ' ' ||
      character == ')' {
      break
    }
    builder.write_char(character)
  }
  let mut repository = builder.to_string()
  if repository.has_suffix(".git") {
    repository = repository[:repository.length() - 4].to_owned()
  }
  guard parts[0] != "" && repository != "" else { return None }
  Some("\{parts[0]}/\{repository}")
}

///|
/// owner/name when `url` points at a GitHub repository, None when it points
/// at another source host or nowhere a source lives.
fn source_url_repository(url : String) -> String?? {
  let trimmed = url.trim().to_owned()
  guard source_hosts.any(host => {
    trimmed.contains(host + "/") || trimmed.contains(host + ":")
  }) else {
    return None
  }
  let github = trimmed.replace(old="git@github.com:", new="github.com/")
  Some(clean_repository(github_name_from_url(github)))
}

///|
/// The pom with blocks other than the project's own fields removed, so
/// `<url>` is the project's url.
fn pom_project_fields(pom : String) -> String {
  let mut text = pom
  for
    tag in [
      "parent", "licenses", "developers", "contributors", "organization", "scm",
      "issueManagement", "ciManagement", "distributionManagement", "repositories",
      "pluginRepositories", "mailingLists", "build", "profiles", "dependencies",
      "dependencyManagement", "reporting", "properties",
    ] {
    while text.find("<\{tag}>") is Some(start) {
      let close = "</\{tag}>"
      guard text.find(close) is Some(end) && end > start else { break }
      text = text[:start].to_owned() + text[end + close.length():].to_owned()
    }
  }
  text
}

///|
/// `${name}` references replaced from the pom's own properties and fields,
/// as Dependabot does: `${scm.github.url}` from
/// `<properties><scm.github.url>`, `${project.artifactId}` from
/// `<artifactId>`.
fn substitute_pom_properties(value : String, pom : String) -> String {
  let properties : Map[String, String] = Map([])
  match xml_blocks(pom, "properties") {
    [block, ..] => {
      let mut rest = block
      while rest.find("<") is Some(start) {
        let after = rest[start + 1:].to_owned()
        guard after.find(">") is Some(close) else { break }
        let name = after[:close].to_owned()
        let body = after[close + 1:].to_owned()
        if name.has_prefix("/") || name.has_prefix("!") || name.contains(" ") {
          rest = body
          continue
        }
        match body.find("</\{name}>") {
          Some(end) => {
            properties.set(name, body[:end].trim().to_owned())
            rest = body[end:].to_owned()
          }
          None => rest = body
        }
      }
    }
    _ => ()
  }
  let fields = pom_project_fields(pom)
  let mut text = value
  for _ in 0..<5 {
    guard text.find("${") is Some(start) else { break }
    guard text[start:].find("}") is Some(length) else { break }
    let name = text[start + 2:start + length].to_owned()
    let short = if name.has_prefix("project.") {
      name["project.".length():].to_owned()
    } else if name.has_prefix("pom.") {
      name["pom.".length():].to_owned()
    } else {
      name
    }
    let replacement = match properties.get(name) {
      Some(found) => found
      None => xml_text(fields, short).unwrap_or("")
    }
    text = text[:start].to_owned() +
      replacement +
      text[start + length + 1:].to_owned()
  }
  text
}

///|
/// The GitHub repository a pom names, by Dependabot's rules: the first of
/// `<url>`, `<scm><url>`, and `<issueManagement><url>` that points at a
/// source host, else a GitHub URL anywhere in the pom whose repository is
/// named like `artifact`. Some(None) means the pom points at a source that
/// is not on GitHub, such as Bitbucket.
pub fn pom_source(pom : String, artifact : String) -> String?? {
  let candidates : Array[String] = []
  match xml_text(pom_project_fields(pom), "url") {
    Some(url) => candidates.push(url)
    None => ()
  }
  for tag in ["scm", "issueManagement"] {
    match xml_blocks(pom, tag) {
      [block, ..] =>
        match xml_text(block, "url") {
          Some(url) => candidates.push(url)
          None => ()
        }
      _ => ()
    }
  }
  for url in candidates {
    match source_url_repository(substitute_pom_properties(url, pom)) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  let text = substitute_pom_properties(pom, pom)
  let mut rest = text
  while rest.find("github.com/") is Some(index) {
    let after = rest[index:].to_owned()
    match github_name_from_url(after) {
      Some(found) => {
        let name = clean_repository(Some(found))
        match name {
          Some(repository) if repository
            .to_lower()
            .has_suffix("/" + artifact.to_lower()) =>
            return Some(Some(repository))
          _ => ()
        }
      }
      None => ()
    }
    rest = after["github.com/".length():].to_owned()
  }
  None
}

///|
/// The `<parent>` of a pom, as (group, artifact, version).
pub fn pom_parent(pom : String) -> (String, String, String)? {
  guard xml_blocks(pom, "parent") is [block, ..] else { return None }
  match
    (
      xml_text(block, "groupId"),
      xml_text(block, "artifactId"),
      xml_text(block, "version"),
    ) {
    (Some(group), Some(artifact), Some(version)) if group != "" &&
      artifact != "" &&
      version != "" => Some((group, artifact, version))
    _ => None
  }
}

///|
/// Whether a repository found in an ancestor pom is the dependency's.
/// Dependabot reads one parent and accepts it when the repository is named
/// like the artifact; a parent in the dependency's own group is also
/// accepted, at any depth, so software.amazon.awssdk:dynamodb finds
/// aws/aws-sdk-java-v2 two parents up.
pub fn ancestor_source_accepted(
  group : String,
  artifact : String,
  ancestor_group : String,
  repository : String,
) -> Bool {
  ancestor_group == group ||
  repository.to_lower().has_suffix("/" + artifact.to_lower())
}

///|
/// The library a Gradle plugin marker pom points at, as (group, artifact,
/// version): the marker for org.springframework.boot depends on
/// org.springframework.boot:spring-boot-gradle-plugin.
pub fn plugin_marker_target(pom : String) -> (String, String, String)? {
  guard xml_blocks(pom, "dependency") is [block, ..] else { return None }
  match
    (
      xml_text(block, "groupId"),
      xml_text(block, "artifactId"),
      xml_text(block, "version"),
    ) {
    (Some(group), Some(artifact), Some(version)) =>
      Some((group, artifact, version))
    _ => None
  }
}

///|
/// The GitHub repository an npm registry entry names, by Dependabot's
/// rules: the first of `repository`, `homepage`, and `bugs` that points at a
/// source host. `repository` can be "owner/name", "github:owner/name", or an
/// object with `url`. Some(None) means the source is not on GitHub.
pub fn npm_source(listing : String) -> String?? {
  let json = @json.parse(listing) catch { _ => return None }
  guard json is Object(fields) else { return None }
  for key in ["repository", "homepage", "bugs"] {
    let url = match fields.get(key) {
      Some(String(text)) => text
      Some(Object(inner)) =>
        match inner.get("url") {
          Some(String(text)) => text
          _ => continue
        }
      _ => continue
    }
    let expanded = if url.has_prefix("github:") {
      "https://github.com/" + url["github:".length():].to_owned()
    } else if !url.contains(":") && url.split("/").count() == 2 {
      "https://github.com/" + url
    } else {
      url
    }
    match source_url_repository(expanded) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}
