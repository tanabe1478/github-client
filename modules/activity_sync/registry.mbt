///|
/// A version as a changelog writes it: "^17.4.2" is "17.4.2".
fn written_version(version : String) -> String {
  version.trim().trim_start(chars="^~>=<v ").to_owned()
}

///|
/// The changelog of a dependency's source repository, or "" when it has
/// none that can be read. GitHub is read with a token; Bitbucket and GitLab
/// are read without one.
async fn source_changelog(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  host : String,
  repository : String,
) -> String {
  guard @domain.RepositoryRef::parse(repository) is Ok(reference) else {
    return ""
  }
  if host == "github.com" {
    guard resolve_token(
        tokens,
        repo_scopes,
        owner_scopes,
        reference.owner(),
        reference.name(),
      )
      is Some(token) else {
      return ""
    }
    let files = match
      @github_api.list_root_files(token, reference.owner(), reference.name()) {
      Ok(files) => files
      Err(error) => {
        @github_api.log("registry: files of \{repository}: \{error}")
        return ""
      }
    }
    guard @project_reader.changelog_file(files) is Some(file) else { return "" }
    match
      @github_api.get_file_content(
        token,
        reference.owner(),
        reference.name(),
        file,
      ) {
      Ok(Some(content)) => @project_reader.decode_base64(content)
      _ => ""
    }
  } else {
    let files = match @github_api.list_hosted_files(host, repository) {
      Ok(files) => files
      Err(error) => {
        @github_api.log("registry: files of \{host}/\{repository}: \{error}")
        return ""
      }
    }
    guard @project_reader.changelog_file(files) is Some(file) else { return "" }
    match @github_api.get_hosted_file(host, repository, file) {
      Ok(Some(text)) => text
      _ => ""
    }
  }
}

///|
/// The versions a followed dependency's registry publishes, each with when
/// it was published when the registry says.
async fn registry_versions(
  followed : @domain.FollowedPackage,
) -> Array[(String, String)] {
  let fetched = match followed.ecosystem {
    "npm" =>
      match @github_api.get_npm_document(followed.name) {
        Ok(Some(document)) =>
          return @project_reader.npm_document_versions(document)
        Ok(None) => return []
        Err(error) => Err(error)
      }
    "gradle-plugin" =>
      @github_api.get_maven_metadata(
        followed.registry,
        followed.name,
        "\{followed.name}.gradle.plugin",
      )
    _ => {
      let parts = followed.name.split(":").to_array()
      guard parts.length() == 2 else { return [] }
      @github_api.get_maven_metadata(
        followed.registry,
        parts[0].to_owned(),
        parts[1].to_owned(),
      )
    }
  }
  match fetched {
    Ok(Some(xml)) => {
      // Maven metadata only says when the newest version was published.
      let (versions, updated) = @project_reader.maven_metadata_versions(xml)
      versions.map(version => (version, updated))
    }
    Ok(None) => []
    Err(error) => {
      @github_api.log("registry: versions of \{followed.name}: \{error}")
      []
    }
  }
}

///|
/// The version's page on its registry.
fn registry_page(
  followed : @domain.FollowedPackage,
  version : String,
) -> String {
  match followed.ecosystem {
    "npm" => "https://www.npmjs.com/package/\{followed.name}/v/\{version}"
    "gradle-plugin" =>
      "https://plugins.gradle.org/plugin/\{followed.name}/\{version}"
    _ => {
      let path = followed.name.replace_all(old=":", new="/")
      if followed.registry == @github_api.GRADLE_PLUGIN_PORTAL {
        "\{@github_api.GRADLE_PLUGIN_PORTAL}/\{path.replace_all(old=".", new="/")}/\{version}/"
      } else {
        "https://central.sonatype.com/artifact/\{path}/\{version}"
      }
    }
  }
}

///|
fn registry_label(followed : @domain.FollowedPackage) -> String {
  match followed.ecosystem {
    "npm" => "npm"
    _ =>
      if followed.registry == @github_api.GRADLE_PLUGIN_PORTAL {
        "the Gradle Plugin Portal"
      } else {
        "Maven Central"
      }
  }
}

///|
/// New versions of the dependencies the base projects follow on their
/// registries (ADR 0008): for each, the newest stable version newer than
/// the oldest one a project uses, with the changelog's section from that
/// version to it as notes. Dependencies already at the newest version give
/// nothing.
pub async fn fetch_registry_releases(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  profiles : Array[@domain.ProjectProfile],
) -> Array[@github_api.ActivitySummary] {
  // One entry per package, with every version the projects use. A Gradle
  // plugin whose library comes from the same source repository, such as
  // forbiddenapis, is left to the library.
  let packages : Array[(@domain.FollowedPackage, Array[String])] = []
  for profile in profiles {
    for followed in profile.followed {
      if followed.ecosystem == "gradle-plugin" &&
        followed.source_repository != "" &&
        profiles.any(other => {
          other.followed.any(library => {
            library.ecosystem == "maven" &&
            library.source_host == followed.source_host &&
            library.source_repository == followed.source_repository
          })
        }) {
        continue
      }
      let used = profile.tools
        .filter(tool => tool.name == followed.name)
        .map(tool => tool.version)
      match
        packages.search_by(entry => {
          entry.0.name == followed.name &&
          entry.0.ecosystem == followed.ecosystem
        }) {
        Some(index) => packages[index].1.append(used)
        None => packages.push((followed, used))
      }
    }
  }
  let found = @async.all(
    packages.map(entry => {
      async fn() -> @github_api.ActivitySummary? {
        let (followed, used) = entry
        // The oldest version in use, so the notes cover every project.
        let mut oldest : (String, @domain.Version)? = None
        for version in used {
          guard @domain.parse_version(version) is Some(parsed) else { continue }
          match oldest {
            Some((_, kept)) if parsed.compare_to(kept) >= 0 => ()
            _ => oldest = Some((version, parsed))
          }
        }
        guard oldest is Some((oldest_used, _)) else { return None }
        let versions = registry_versions(followed)
        guard @domain.newest_version(
            versions.map(entry => entry.0),
            oldest_used,
          )
          is Some(newest) else {
          return None
        }
        let published_at = versions
          .filter(entry => entry.0 == newest)
          .map(entry => entry.1)
          .get(0)
          .unwrap_or("")
        let changelog = if followed.source_host == "" {
          ""
        } else {
          source_changelog(
            tokens,
            repo_scopes,
            owner_scopes,
            followed.source_host,
            followed.source_repository,
          )
        }
        let notes = @project_reader.changelog_section(
          changelog,
          newest,
          written_version(oldest_used),
        )
        Some(
          @github_api.registry_release(
            followed.name,
            newest,
            registry_page(followed, newest),
            published_at,
            notes,
            @project_reader.changelog_summary(changelog, newest),
            registry_label(followed),
          ),
        )
      }
    }),
    max_concurrent=8,
  )
  found.filter_map(item => item)
}
