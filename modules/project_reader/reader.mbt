///|
/// Directories never searched for repositories.
let skipped_directories : Array[String] = [
  "node_modules", ".git", "build", "dist", "out", "target", "vendor", "coverage",
  ".gradle", ".next", ".tmp", ".cache", ".terraform",
]

///|
/// Top-level pnpm-workspace.yaml keys that describe the workspace rather
/// than configure pnpm.
let structural_keys : Array[String] = ["packages", "catalog", "catalogs"]

///|
/// How deep a directory is searched for Git repositories.
pub const MAX_DEPTH : Int = 2

///|
/// "~" and "~/..." become the home directory.
pub fn expand_home(path : String) -> String {
  guard path == "~" || path.has_prefix("~/") else { return path }
  match @env.get_env_var("HOME") {
    Some(home) => home + path[1:].to_owned()
    None => path
  }
}

///|
fn join(directory : String, relative : String) -> String {
  if relative == "" {
    directory
  } else if directory == "" {
    relative
  } else {
    directory + "/" + relative
  }
}

///|
/// The last segment of a path, or the path itself.
fn base_name(path : String) -> String {
  let trimmed = path.trim_end(chars="/").to_owned()
  match trimmed.rev_find("/") {
    Some(index) => trimmed[index + 1:].to_owned()
    None => trimmed
  }
}

///|
/// "owner/name" from a GitHub remote URL: https://github.com/owner/name(.git)
/// or git@github.com:owner/name(.git).
pub fn github_name_from_url(url : String) -> String? {
  let rest = if url.has_prefix("git@github.com:") {
    url["git@github.com:".length():].to_owned()
  } else {
    match url.find("github.com/") {
      Some(index) => url[index + "github.com/".length():].to_owned()
      None => return None
    }
  }
  let trimmed = if rest.has_suffix(".git") {
    rest[:rest.length() - 4].to_owned()
  } else {
    rest
  }
  let parts = trimmed.split("/").to_array()
  guard parts.length() >= 2 && parts[0] != "" && parts[1] != "" else {
    return None
  }
  Some("\{parts[0]}/\{parts[1]}")
}

///|
/// A repository as typed or pasted: a GitHub URL becomes owner/name, and
/// anything else is returned trimmed.
pub fn repository_input(value : String) -> String {
  let trimmed = value.trim().to_owned()
  match github_name_from_url(trimmed) {
    Some(name) => name
    None => trimmed
  }
}

///|
/// The origin remote of `.git/config`, as owner/name.
pub fn origin_name(config : String) -> String? {
  let mut in_origin = false
  for raw in config.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("[") {
      in_origin = line == "[remote \"origin\"]"
    } else if in_origin && line.has_prefix("url") {
      match line.find("=") {
        Some(index) =>
          return github_name_from_url(line[index + 1:].trim().to_owned())
        None => ()
      }
    }
  }
  None
}

///|
/// A dependency value that names a version: "5.2.0", "^5.2.0", ">=10".
/// Protocols such as "workspace:" or "file:" and URLs are not versions.
fn version_value(value : String) -> Bool {
  !value.contains(":") &&
  !value.contains("/") &&
  @domain.parse_version(value) is Some(_)
}

///|
/// A plain version without range operators.
fn exact_value(value : String) -> Bool {
  match value.get_char(0) {
    Some(character) => character >= '0' && character <= '9'
    None => false
  }
}

///|
fn object_field(fields : Map[String, Json], key : String) -> Map[String, Json] {
  match fields.get(key) {
    Some(Object(map)) => map
    _ => Map([])
  }
}

///|
/// Tools, the package name, and the number of dependencies in one
/// package.json. `location` is its directory relative to the base project.
fn read_package_json(
  location : String,
  source : String,
  tools : Array[@domain.ProjectTool],
  dependencies : Map[String, Bool],
) -> Result[String, String] {
  let file = join(location, "package.json")
  let json = @json.parse(source) catch {
    _ => return Err("Couldn't read \{file}: it is not valid JSON.")
  }
  guard json is Object(fields) else {
    return Err("Couldn't read \{file}: it is not a JSON object.")
  }
  match fields.get("packageManager") {
    Some(String(value)) =>
      match value.find("@") {
        Some(index) if index > 0 => {
          let version = match value.find("+") {
            Some(plus) => value[index + 1:plus].to_owned()
            None => value[index + 1:].to_owned()
          }
          tools.push({
            name: value[:index].to_owned(),
            version,
            exact: exact_value(version),
            source: "\{file} packageManager",
          })
        }
        _ => ()
      }
    _ => ()
  }
  for name, value in object_field(fields, "engines") {
    guard value is String(range) && version_value(range) else { continue }
    tools.push({
      name,
      version: range,
      exact: exact_value(range),
      source: "\{file} engines",
    })
  }
  for section in ["dependencies", "devDependencies"] {
    for name, value in object_field(fields, section) {
      note_dependency(dependencies, name, true)
      guard value is String(range) && version_value(range) else { continue }
      tools.push({
        name,
        version: range,
        exact: exact_value(range),
        source: "\{file} \{section}",
      })
    }
  }
  match fields.get("name") {
    Some(String(name)) => Ok(name)
    _ => Ok("")
  }
}

///|
/// Setting keys of an .npmrc. Registry and credential lines (those naming a
/// host or scope) are skipped, and values are never kept.
pub fn npmrc_keys(source : String) -> Array[String] {
  let keys : Array[String] = []
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" || line.has_prefix("#") || line.has_prefix(";") {
      continue
    }
    guard line.find("=") is Some(index) else { continue }
    let key = line[:index].trim().to_owned()
    if key == "" ||
      key.contains(":") ||
      key.has_prefix("@") ||
      keys.contains(key) {
      continue
    }
    keys.push(key)
  }
  keys
}

///|
/// Top-level keys of a pnpm-workspace.yaml, except the structural ones.
pub fn workspace_keys(source : String) -> Array[String] {
  let keys : Array[String] = []
  for raw in source.split("\n") {
    let line = raw.trim_end().to_owned()
    guard line != "" else { continue }
    match line.get_char(0) {
      Some(' ' | '\t' | '#' | '-') => continue
      _ => ()
    }
    guard line.find(":") is Some(index) else { continue }
    let key = line[:index].trim().trim(chars="\"'").to_owned()
    if key == "" || structural_keys.contains(key) || keys.contains(key) {
      continue
    }
    keys.push(key)
  }
  keys
}

///|
/// The profile of a repository from its files, as (path relative to the
/// repository root, contents).
pub fn parse_files(
  repository : String,
  files : Array[(String, String)],
) -> @domain.ProjectProfile {
  let tools : Array[@domain.ProjectTool] = []
  let settings : Array[@domain.ProjectSetting] = []
  let dependencies : Map[String, Bool] = Map([])
  let read : Array[String] = []
  let problems : Array[String] = []
  let mut package_name = ""
  for entry in files {
    let (relative, source) = entry
    let name = base_name(relative)
    let location = if relative.contains("/") {
      relative[:relative.length() - name.length() - 1].to_owned()
    } else {
      ""
    }
    match file_kind(relative) {
      PackageJson =>
        match read_package_json(location, source, tools, dependencies) {
          Ok(found) => {
            read.push(relative)
            if location == "" || package_name == "" {
              package_name = if location == "" { found } else { package_name }
            }
          }
          Err(problem) => problems.push(problem)
        }
      Npmrc => {
        read.push(relative)
        for key in npmrc_keys(source) {
          settings.push({ key, file: relative, })
        }
      }
      PnpmWorkspace => {
        read.push(relative)
        for key in workspace_keys(source) {
          settings.push({ key, file: relative, })
        }
      }
      VersionCatalog => {
        read.push(relative)
        read_version_catalog(relative, source, tools, dependencies)
      }
      GradleWrapper => {
        read.push(relative)
        read_gradle_wrapper(relative, source, tools)
      }
      GradleScript => {
        read.push(relative)
        read_gradle_build(relative, source, tools, dependencies)
      }
      Pom => {
        read.push(relative)
        read_pom(relative, source, tools, dependencies)
      }
      GradleProperties => {
        read.push(relative)
        for key in properties_keys(source) {
          settings.push({ key, file: relative, })
        }
      }
      VersionFile => {
        read.push(relative)
        read_version_file(relative, source, tools)
      }
      Workflow => {
        read.push(relative)
        read_workflow(relative, source, tools)
      }
      Terraform => {
        read.push(relative)
        read_terraform(relative, source, tools)
      }
      SpringConfig => {
        read.push(relative)
        let keys = if relative.has_suffix(".properties") {
          properties_keys(source)
        } else {
          yaml_keys(source)
        }
        for key in keys {
          settings.push({ key, file: relative, })
        }
      }
      Other => ()
    }
  }
  {
    name: repository,
    package_name,
    tools,
    settings,
    files: read,
    dependency_count: dependencies.length(),
    managed: dependencies
    .iter()
    .filter(entry => !entry.1)
    .map(entry => entry.0)
    .to_array(),
    problem: problems.join(" "),
    moved_to: "",
  }
}

///|
pub fn is_directory(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
/// GitHub repositories found under a directory on this machine, as
/// owner/name from each `.git/config` origin, at most `MAX_DEPTH` levels
/// down. A repository is not searched inside.
pub fn discover_repositories(path : String) -> Result[Array[String], String] {
  let root = expand_home(path).trim_end(chars="/").to_owned()
  let exists = @fs.is_dir(root) catch { _ => false }
  guard exists else { return Err("The directory does not exist.") }
  let found : Array[String] = []
  fn visit(directory : String, depth : Int) -> Unit {
    let config = @fs.read_file_to_string(
      directory + "/.git/config",
      encoding="utf8",
    ) catch {
      _ => ""
    }
    if config != "" {
      match origin_name(config) {
        Some(name) if !found.contains(name) => found.push(name)
        _ => ()
      }
      return
    }
    guard depth < MAX_DEPTH else { return }
    let entries = @fs.read_dir(directory) catch { _ => return }
    let names = entries.to_array()
    names.sort()
    for name in names {
      if skipped_directories.contains(name) || name.has_prefix(".") {
        continue
      }
      let child = directory + "/" + name
      let is_directory = @fs.is_dir(child) catch { _ => false }
      if is_directory {
        visit(child, depth + 1)
      }
    }
  }

  visit(root, 0)
  Ok(found)
}

///|
fn base64_value(character : Char) -> Int {
  if character >= 'A' && character <= 'Z' {
    character.to_int() - 'A'.to_int()
  } else if character >= 'a' && character <= 'z' {
    character.to_int() - 'a'.to_int() + 26
  } else if character >= '0' && character <= '9' {
    character.to_int() - '0'.to_int() + 52
  } else if character == '+' || character == '-' {
    62
  } else if character == '/' || character == '_' {
    63
  } else {
    -1
  }
}

///|
/// Base64 as the GitHub contents API sends it (with line breaks), decoded
/// as UTF-8.
pub fn decode_base64(encoded : String) -> String {
  let bytes = Array::new()
  let mut buffer = 0
  let mut bits = 0
  for character in encoded {
    let value = base64_value(character)
    guard value >= 0 else { continue }
    buffer = (buffer << 6) | value
    bits += 6
    if bits >= 8 {
      bits -= 8
      bytes.push(((buffer >> bits) & 0xff).to_byte())
    }
  }
  @utf8.decode_lossy(Bytes::from_array(bytes))
}
