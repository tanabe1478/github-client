///|
/// The quoted strings of a line, in order: `id("x") version "1.0"` gives
/// ["x", "1.0"]. Single and double quotes both count.
fn quoted_strings(line : String) -> Array[String] {
  let found : Array[String] = []
  let current = StringBuilder()
  let mut quote : Char? = None
  for character in line {
    match quote {
      Some(open) =>
        if character == open {
          found.push(current.to_string())
          current.reset()
          quote = None
        } else {
          current.write_char(character)
        }
      None =>
        if character == '"' || character == '\'' {
          quote = Some(character)
        }
    }
  }
  found
}

///|
/// A version Gradle or Maven treats as one release: "4.1.1" or
/// "33.0.0-jre", not "4.+" or "[1.0,2.0)".
fn single_version(value : String) -> Bool {
  exact_value(value) &&
  !value.contains("+") &&
  !value.contains("[") &&
  !value.contains("(") &&
  !value.contains(",")
}

///|
/// A tool with a Gradle or Maven version; versions that are not numbers,
/// such as "latest.release", are skipped.
fn push_jvm_tool(
  tools : Array[@domain.ProjectTool],
  name : String,
  version : String,
  source : String,
) -> Unit {
  guard name != "" && version_value(version) else { return }
  tools.push({ name, version, exact: single_version(version), source, })
}

///|
/// The fields of a TOML inline table, nested tables flattened with dots:
/// `{ module = "a:b", version = { strictly = "1.0" } }` gives module and
/// version.strictly.
fn inline_fields(text : String) -> Map[String, String] {
  let fields : Map[String, String] = Map([])
  let characters = text.to_array()
  let prefixes : Array[String] = []
  let key = StringBuilder()
  let value = StringBuilder()
  let mut in_value = false
  let mut quote : Char? = None
  let full_key = fn(name : String) {
    if prefixes.is_empty() {
      name
    } else {
      prefixes.join(".") + "." + name
    }
  }
  let mut index = 0
  while index < characters.length() {
    let character = characters[index]
    index += 1
    match quote {
      Some(open) =>
        if character == open {
          fields.set(
            full_key(key.to_string().trim().to_owned()),
            value.to_string(),
          )
          key.reset()
          value.reset()
          in_value = false
          quote = None
        } else {
          value.write_char(character)
        }
      None =>
        match character {
          '{' =>
            if in_value {
              prefixes.push(key.to_string().trim().to_owned())
              key.reset()
              in_value = false
            }
          '}' => {
            if !prefixes.is_empty() {
              prefixes.pop() |> ignore
            }
            key.reset()
          }
          '=' => in_value = true
          ',' => key.reset()
          '"' | '\'' => if in_value { quote = Some(character) }
          _ => if !in_value { key.write_char(character) }
        }
    }
  }
  fields
}

///|
/// The version a catalog entry asks for: `version`, `version.ref` resolved
/// in [versions], or a rich version's strictly, require, or prefer.
fn catalog_version(
  fields : Map[String, String],
  versions : Map[String, String],
) -> String {
  for
    key in ["version", "version.strictly", "version.require", "version.prefer"] {
    match fields.get(key) {
      Some(version) => return version
      None => ()
    }
  }
  match fields.get("version.ref") {
    Some(name) => versions.get(name).unwrap_or("")
    None => ""
  }
}

///|
/// Libraries and plugins of a Gradle version catalog
/// (`gradle/libs.versions.toml`). A library without a version, managed by a
/// platform such as Spring Boot's, counts as a dependency only.
fn read_version_catalog(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
  dependencies : Map[String, Bool],
) -> Unit {
  let versions : Map[String, String] = Map([])
  let entries : Array[(String, String, String)] = []
  let mut section = ""
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    if line.has_prefix("[") {
      section = line.trim(chars="[]").trim().to_owned()
      continue
    }
    guard line.find("=") is Some(index) else { continue }
    let key = line[:index].trim().trim(chars="\"").to_owned()
    let value = line[index + 1:].trim().to_owned()
    match section {
      "versions" =>
        if value.has_prefix("{") {
          let fields = inline_fields(value)
          for rich in ["strictly", "require", "prefer"] {
            if fields.get(rich) is Some(text) {
              versions.set(key, text)
              break
            }
          }
        } else {
          match quoted_strings(value) {
            [text, ..] => versions.set(key, text)
            [] => ()
          }
        }
      "libraries" | "plugins" => entries.push((section, key, value))
      _ => ()
    }
  }
  for entry in entries {
    let (kind, _, value) = entry
    let (name, version) = if value.has_prefix("{") {
      let fields = inline_fields(value)
      let name = if kind == "plugins" {
        fields.get("id").unwrap_or("")
      } else {
        match fields.get("module") {
          Some(module) => module
          None =>
            match (fields.get("group"), fields.get("name")) {
              (Some(group), Some(artifact)) => "\{group}:\{artifact}"
              _ => ""
            }
        }
      }
      (name, catalog_version(fields, versions))
    } else {
      // "group:artifact:version" or "plugin.id:version".
      match quoted_strings(value) {
        [text, ..] =>
          match text.rev_find(":") {
            Some(at) if kind == "plugins" || text[:at].contains(":") =>
              (text[:at].to_owned(), text[at + 1:].to_owned())
            _ => (text, "")
          }
        [] => ("", "")
      }
    }
    if kind == "libraries" && name != "" {
      note_dependency(dependencies, name, version != "")
    }
    push_jvm_tool(tools, name, version, "\{file} \{kind}")
  }
}

///|
/// The Gradle version of the wrapper, from its distributionUrl
/// (".../gradle-8.12.1-bin.zip").
fn read_gradle_wrapper(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
) -> Unit {
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    guard line.has_prefix("distributionUrl") else { continue }
    guard line.rev_find("gradle-") is Some(start) else { continue }
    let rest = line[start + "gradle-".length():].to_owned()
    let end = match rest.find("-") {
      Some(at) => at
      None => rest.find(".zip").unwrap_or(rest.length())
    }
    push_jvm_tool(tools, "gradle", rest[:end].to_owned(), file)
  }
}

///|
/// Configurations whose dependency strings a build script declares, such as
/// `implementation("org.springframework.boot:spring-boot-starter-web")`.
let dependency_configurations : Array[String] = [
  "implementation", "api", "compileOnly", "runtimeOnly", "testImplementation", "testRuntimeOnly",
  "annotationProcessor", "developmentOnly", "testFixturesImplementation", "kapt",
]

///|
/// Plugins with a version (`id("org.springframework.boot") version "3.4.2"`),
/// dependency strings ("group:artifact:version", or "group:artifact" left to
/// a BOM), and the Java version (`JavaLanguageVersion.of(21)`,
/// `jvmToolchain(21)`, `JavaVersion.VERSION_21`) of a build script or a
/// convention plugin. Catalog references such as `alias(libs.plugins.x)` are
/// read from the catalog instead.
fn read_gradle_build(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
  dependencies : Map[String, Bool],
) -> Unit {
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("//") || line.has_prefix("*") || line.has_prefix("/*") {
      continue
    }
    for
      marker in [
        "JavaLanguageVersion.of(", "jvmToolchain(", "JavaVersion.VERSION_",
      ] {
      match line.find(marker) {
        Some(at) => {
          let rest = line[at + marker.length():].to_owned()
          // VERSION_1_8 is Java 8.
          let rest = if rest.has_prefix("1_") {
            rest[2:].to_owned()
          } else {
            rest
          }
          push_java(tools, rest, "\{file} toolchain")
          break
        }
        None => ()
      }
    }
    let strings = quoted_strings(line)
    if line.has_prefix("id") &&
      line.contains("version") &&
      strings.length() >= 2 {
      push_jvm_tool(tools, strings[0], strings[1], "\{file} plugins")
      continue
    }
    let configuration = dependency_configurations.any(name => {
      line.has_prefix(name + "(") || line.has_prefix(name + " ")
    })
    for text in strings {
      let parts = text.split(":").to_array()
      guard parts.length() >= 2 && parts[0] != "" && parts[1] != "" else {
        continue
      }
      let name = "\{parts[0]}:\{parts[1]}"
      if parts.length() == 3 {
        note_dependency(dependencies, name, true)
        push_jvm_tool(tools, name, parts[2].to_owned(), "\{file} dependencies")
      } else if parts.length() == 2 && configuration {
        note_dependency(dependencies, name, false)
      }
    }
  }
}

///|
/// The text of the first `<tag>...</tag>` in `xml`, trimmed.
fn xml_text(xml : String, tag : String) -> String? {
  guard xml.find("<\{tag}>") is Some(start) else { return None }
  let rest = xml[start + tag.length() + 2:].to_owned()
  guard rest.find("</\{tag}>") is Some(end) else { return None }
  Some(rest[:end].trim().to_owned())
}

///|
/// Every `<tag>...</tag>` block of `xml`, without the tags.
fn xml_blocks(xml : String, tag : String) -> Array[String] {
  let blocks : Array[String] = []
  let mut rest = xml
  while rest.find("<\{tag}>") is Some(start) {
    let after = rest[start + tag.length() + 2:].to_owned()
    guard after.find("</\{tag}>") is Some(end) else { break }
    blocks.push(after[:end].to_owned())
    rest = after[end + tag.length() + 3:].to_owned()
  }
  blocks
}

///|
/// `${name}` replaced from the pom's properties; anything else unchanged.
fn resolve_property(value : String, properties : Map[String, String]) -> String {
  guard value.has_prefix("${") && value.has_suffix("}") else { return value }
  properties.get(value[2:value.length() - 1].to_owned()).unwrap_or("")
}

///|
/// The parent (spring-boot-starter-parent, for example), `java.version`,
/// and the dependencies and plugins with a version of a `pom.xml`.
fn read_pom(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
  dependencies : Map[String, Bool],
) -> Unit {
  // Comments could hold whole dependencies.
  let xml = StringBuilder()
  let mut rest = source
  while rest.find("<!--") is Some(start) {
    xml.write_string(rest[:start].to_owned())
    match rest[start:].find("-->") {
      Some(end) => rest = rest[start + end + 3:].to_owned()
      None => rest = ""
    }
  }
  xml.write_string(rest)
  let text = xml.to_string()
  let properties : Map[String, String] = Map([])
  match xml_text(text, "properties") {
    Some(block) =>
      for line in block.split("<") {
        guard line.find(">") is Some(at) else { continue }
        let name = line[:at].to_owned()
        if name.has_prefix("/") || name == "" {
          continue
        }
        properties.set(name, line[at + 1:].trim().to_owned())
      }
    None => ()
  }
  match xml_blocks(text, "parent") {
    [parent, ..] => {
      let name = "\{xml_text(parent, "groupId").unwrap_or("")}:\{xml_text(parent, "artifactId").unwrap_or("")}"
      let version = resolve_property(
        xml_text(parent, "version").unwrap_or(""),
        properties,
      )
      push_jvm_tool(tools, name, version, "\{file} parent")
    }
    [] => ()
  }
  for
    key in [
      "java.version", "maven.compiler.release", "maven.compiler.source", "maven.compiler.target",
    ] {
    if properties.get(key) is Some(version) {
      push_java(tools, version, "\{file} \{key}")
      break
    }
  }
  for tag in ["dependency", "plugin"] {
    for block in xml_blocks(text, tag) {
      let group = xml_text(block, "groupId").unwrap_or(
        "org.apache.maven.plugins",
      )
      guard xml_text(block, "artifactId") is Some(artifact) else { continue }
      let name = "\{group}:\{artifact}"
      if tag == "dependency" {
        note_dependency(
          dependencies,
          name,
          xml_text(block, "version") is Some(_),
        )
      }
      match xml_text(block, "version") {
        Some(version) =>
          push_jvm_tool(
            tools,
            name,
            resolve_property(version, properties),
            "\{file} \{tag}",
          )
        None => ()
      }
    }
  }
}

///|
/// Keys of a properties file such as gradle.properties; values are never
/// kept, since they can hold credentials.
pub fn properties_keys(source : String) -> Array[String] {
  let keys : Array[String] = []
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" || line.has_prefix("#") || line.has_prefix("!") {
      continue
    }
    let end = match (line.find("="), line.find(":")) {
      (Some(a), Some(b)) => if a < b { a } else { b }
      (Some(a), None) | (None, Some(a)) => a
      (None, None) => continue
    }
    let key = line[:end].trim().to_owned()
    if key != "" && !keys.contains(key) {
      keys.push(key)
    }
  }
  keys
}

///|
/// Records a dependency; one declared with a version anywhere counts as
/// versioned.
fn note_dependency(
  dependencies : Map[String, Bool],
  name : String,
  versioned : Bool,
) -> Unit {
  dependencies.set(name, versioned || dependencies.get(name).unwrap_or(false))
}

///|
/// The digits and dots at the start of `text`, after any leading
/// non-digits: "21)" gives "21", "temurin-21.0.2" gives "21.0.2".
fn leading_number(text : String) -> String {
  let builder = StringBuilder()
  let mut started = false
  for character in text {
    let digit = character >= '0' && character <= '9'
    if digit || (started && character == '.') {
      started = true
      builder.write_char(character)
    } else if started {
      break
    }
  }
  builder.to_string().trim_end(chars=".").to_owned()
}

///|
/// The Java version, once per version and source file.
fn push_java(
  tools : Array[@domain.ProjectTool],
  version : String,
  source : String,
) -> Unit {
  let number = leading_number(version)
  if number == "" ||
    tools.any(tool => {
      tool.name == "java" && tool.version == number && tool.source == source
    }) {
    return
  }
  tools.push({ name: "java", version: number, exact: true, source, })
}

///|
/// The Java version of `.java-version` ("21" or "temurin-21.0.2"),
/// `.sdkmanrc` ("java=21.0.6-tem"), or `.tool-versions` ("java temurin-21").
fn read_java_version_file(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
) -> Unit {
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    if file.has_suffix(".java-version") {
      push_java(tools, line, file)
      return
    }
    if line.has_prefix("java=") || line.has_prefix("java ") {
      push_java(tools, line[5:].to_owned(), file)
      return
    }
  }
}

///|
/// Setting keys of a Spring `application.yml`, as dotted paths of the
/// values: `spring.jpa.open-in-view`. List items and values are skipped.
pub fn yaml_keys(source : String) -> Array[String] {
  let keys : Array[String] = []
  // (indent, key) of the open parents.
  let parents : Array[(Int, String)] = []
  for raw in source.split("\n") {
    let line = raw.trim_end().to_owned()
    let text = line.trim_start().to_owned()
    if text == "" || text.has_prefix("#") {
      continue
    }
    if text == "---" {
      parents.clear()
      continue
    }
    let indent = line.length() - text.length()
    while parents.last() is Some((open, _)) && open >= indent {
      parents.pop() |> ignore
    }
    if text.has_prefix("-") {
      continue
    }
    guard text.find(":") is Some(at) else { continue }
    let key = text[:at].trim().trim(chars="\"'").to_owned()
    guard key != "" && !key.contains(" ") else { continue }
    let path = parents.map(entry => entry.1)
    path.push(key)
    let full = path.join(".")
    let value = text[at + 1:].trim().to_owned()
    if value == "" || value.has_prefix("#") {
      parents.push((indent, key))
    } else if !keys.contains(full) {
      keys.push(full)
    }
  }
  keys
}

///|
/// The most BOMs read for one base project.
pub const MAX_BOMS : Int = 5

///|
/// The BOMs whose versions a profile relies on, as (group, artifact,
/// version): Spring Boot's spring-boot-dependencies for its plugin or
/// parent, and libraries named like a BOM ("-bom", "-dependencies") that
/// are imported with a version.
pub fn bom_coordinates(
  profile : @domain.ProjectProfile,
) -> Array[(String, String, String)] {
  let found : Array[(String, String, String)] = []
  let add = fn(group : String, artifact : String, version : String) {
    let entry = (group, artifact, version)
    if found.length() < MAX_BOMS && !found.contains(entry) {
      found.push(entry)
    }
  }
  for tool in profile.tools {
    guard tool.exact else { continue }
    if tool.name == "org.springframework.boot" ||
      tool.name.has_prefix(
        "org.springframework.boot:spring-boot-starter-parent",
      ) ||
      tool.name.has_prefix("org.springframework.boot:spring-boot-gradle-plugin") ||
      tool.name.has_prefix("org.springframework.boot:spring-boot-dependencies") {
      add("org.springframework.boot", "spring-boot-dependencies", tool.version)
      continue
    }
    guard tool.name.find(":") is Some(at) else { continue }
    let artifact = tool.name[at + 1:].to_owned()
    if artifact.has_suffix("-bom") || artifact.has_suffix("-dependencies") {
      add(tool.name[:at].to_owned(), artifact, tool.version)
    }
  }
  found
}

///|
fn group_of(name : String) -> String {
  match name.find(":") {
    Some(at) => name[:at].to_owned()
    None => name
  }
}

///|
/// A profile with the versions a BOM decides: those of its dependencies
/// declared without a version, directly or through a BOM the BOM imports
/// for their group, and those of known packages such as Spring Framework.
/// BOMs imported by the BOM are not read.
pub fn apply_bom(
  profile : @domain.ProjectProfile,
  coordinate : (String, String, String),
  source : String,
) -> @domain.ProjectProfile {
  let (group, artifact, version) = coordinate
  let label = if @domain.known_package(group) {
    "\{@domain.package_label(group)} \{version} BOM"
  } else {
    "\{group}:\{artifact} \{version} BOM"
  }
  let entries : Array[@domain.ProjectTool] = []
  read_pom("", source, entries, Map([]))
  let tools = profile.tools.copy()
  let push = fn(name : String, entry : @domain.ProjectTool) {
    if !tools.any(tool => tool.name == name && tool.source == label) {
      tools.push({ ..entry, name, source: label, })
    }
  }
  for managed in profile.managed {
    match entries.filter(entry => entry.name == managed) {
      [entry, ..] => push(managed, entry)
      [] =>
        // An imported BOM of the same group, such as spring-session-bom.
        match
          entries.filter(entry => {
            group_of(entry.name) == group_of(managed) &&
            entry.name.has_suffix("-bom")
          }) {
          [entry, ..] => push(managed, entry)
          [] => ()
        }
    }
  }
  // The BOM's own group, such as every Spring Boot starter, is the BOM
  // itself and already matched by the plugin or parent.
  for entry in entries {
    if group_of(entry.name) != group &&
      @domain.known_package(group_of(entry.name)) {
      push(entry.name, entry)
    }
  }
  { ..profile, tools, }
}
