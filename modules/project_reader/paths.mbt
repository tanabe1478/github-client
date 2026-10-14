///|
/// What a file of a base project holds, by its path.
priv enum FileKind {
  PackageJson
  Npmrc
  PnpmWorkspace
  VersionCatalog
  GradleWrapper
  /// build.gradle(.kts), settings.gradle(.kts), and convention plugins
  /// under buildSrc or build-logic.
  GradleScript
  Pom
  GradleProperties
  /// .java-version, .sdkmanrc, .tool-versions, mise.toml, .node-version,
  /// or .nvmrc.
  VersionFile
  /// A GitHub Actions workflow or a composite action.
  Workflow
  /// terraform.tf, versions.tf, providers.tf, or .terraform.lock.hcl.
  Terraform
  /// application*.yml, .yaml, or .properties in src/main/resources.
  SpringConfig
  Other
}

///|
/// Directories that hold tests, examples, or generated files; their build
/// files and settings do not describe the project.
let excluded_segments : Array[String] = [
  "test", "tests", "__tests__", "fixtures", "examples", "samples", "testdata",
]

///|
/// The most files read from one base project.
pub const MAX_PROJECT_FILES : Int = 150

///|
fn file_kind(path : String) -> FileKind {
  let name = base_name(path)
  let root = !path.contains("/")
  match name {
    "package.json" => PackageJson
    ".npmrc" => Npmrc
    "pnpm-workspace.yaml" => PnpmWorkspace
    "gradle-wrapper.properties" => GradleWrapper
    "build.gradle"
    | "build.gradle.kts"
    | "settings.gradle"
    | "settings.gradle.kts" => GradleScript
    "pom.xml" => Pom
    "gradle.properties" => if root { GradleProperties } else { Other }
    ".java-version"
    | ".sdkmanrc"
    | ".tool-versions"
    | "mise.toml"
    | ".mise.toml" => if root { VersionFile } else { Other }
    ".node-version" | ".nvmrc" => VersionFile
    "terraform.tf" | "versions.tf" | "providers.tf" | ".terraform.lock.hcl" =>
      Terraform
    "action.yml" | "action.yaml" => Workflow
    _ =>
      if path.has_prefix(".github/workflows/") &&
        (name.has_suffix(".yml") || name.has_suffix(".yaml")) {
        Workflow
      } else if name.has_suffix(".versions.toml") && path.contains("gradle/") {
        VersionCatalog
      } else if (
          path.has_prefix("buildSrc/") || path.has_prefix("build-logic/")
        ) &&
        (name.has_suffix(".gradle.kts") || name.has_suffix(".gradle")) {
        GradleScript
      } else if name.has_prefix("application") &&
        path.contains("src/main/resources/") &&
        (
          name.has_suffix(".yml") ||
          name.has_suffix(".yaml") ||
          name.has_suffix(".properties")
        ) {
        SpringConfig
      } else {
        Other
      }
  }
}

///|
/// The files to read from a repository's file list: build files, version
/// files, and settings at any depth, outside dependency, build, and test
/// directories. Shallower files come first, and at most
/// `MAX_PROJECT_FILES` are kept.
pub fn project_paths(paths : Array[String]) -> Array[String] {
  let chosen = paths.filter(path => {
    let segments = path.split("/").to_array()
    let directories = segments[:segments.length() - 1]
    !directories
    .iter()
    .any(segment => {
      let text = segment.to_owned()
      skipped_directories.contains(text) || excluded_segments.contains(text)
    }) &&
    !(file_kind(path) is Other)
  })
  let depth = (path : String) => path.split("/").count()
  chosen.sort_by((a, b) => {
    let order = depth(a).compare(depth(b))
    if order != 0 {
      order
    } else {
      a.compare(b)
    }
  })
  if chosen.length() > MAX_PROJECT_FILES {
    chosen[:MAX_PROJECT_FILES].to_array()
  } else {
    chosen
  }
}
