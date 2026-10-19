///|
/// Public registry responses already fetched, by URL. A published pom or
/// version never changes.
let registry_cache : Map[String, String] = Map([])

///|
pub const MAVEN_CENTRAL : String = "https://repo1.maven.org/maven2"

///|
/// Where Gradle plugins and their marker poms are published.
pub const GRADLE_PLUGIN_PORTAL : String = "https://plugins.gradle.org/m2"

///|
/// The URL of a pom in a Maven repository.
pub fn pom_url(
  repository : String,
  group : String,
  artifact : String,
  version : String,
) -> String {
  "\{repository}/\{group.replace_all(old=".", new="/")}/\{artifact}/\{version}/\{artifact}-\{version}.pom"
}

///|
/// The URL of a pom on Maven Central.
pub fn maven_pom_url(
  group : String,
  artifact : String,
  version : String,
) -> String {
  pom_url(MAVEN_CENTRAL, group, artifact, version)
}

///|
/// The body of a public registry URL, or None when it answers 404. No token
/// is sent, and nothing about the project beyond the URL.
async fn get_public(
  url : String,
  registry : String,
  cache? : Bool = true,
) -> Result[String?, String] {
  if cache {
    match registry_cache.get(url) {
      Some(cached) => return Ok(Some(cached))
      None => ()
    }
  }
  try {
    let started = @async.now()
    let headers : @http.Headers = Map([])
    headers.set(
      @http.CaseInsensitiveString("User-Agent"),
      "tanabe1478-github-client/0.1.0",
    )
    let (response, body) = @http.get(url, headers~)
    log(
      "http: status=\{response.code} fetch_ms=\{@async.now() - started} url=\{url}",
    )
    // The Gradle Plugin Portal answers with 303 to where the file is stored.
    if response.code >= 301 && response.code <= 308 && url != "" {
      match response.headers.get(@http.CaseInsensitiveString("Location")) {
        Some(location) if location.has_prefix("https://") && location != url =>
          return match get_public(location, registry, cache~) {
            Ok(Some(text)) => {
              if cache {
                registry_cache.set(url, text)
              }
              Ok(Some(text))
            }
            other => other
          }
        _ => ()
      }
    }
    if response.code == 404 {
      return Ok(None)
    }
    if response.code < 200 || response.code >= 300 {
      return Err("\{registry} request failed with status \{response.code}")
    }
    let text = body.text()
    if cache {
      registry_cache.set(url, text)
    }
    Ok(Some(text))
  } catch {
    _ => Err("\{registry} request failed before a response was received")
  }
}

///|
/// A published pom from a Maven repository such as Maven Central or the
/// Gradle Plugin Portal, or None when it is not published there. Only the
/// public coordinates are sent; no token and nothing about the project.
pub async fn get_pom(
  repository : String,
  group : String,
  artifact : String,
  version : String,
) -> Result[String?, String] {
  let registry = if repository == GRADLE_PLUGIN_PORTAL {
    "Gradle Plugin Portal"
  } else {
    "Maven Central"
  }
  get_public(pom_url(repository, group, artifact, version), registry)
}

///|
/// A published pom from Maven Central, such as Spring Boot's
/// spring-boot-dependencies BOM, or None when it is not published.
pub async fn get_maven_pom(
  group : String,
  artifact : String,
  version : String,
) -> Result[String?, String] {
  get_pom(MAVEN_CENTRAL, group, artifact, version)
}

///|
/// The npm registry's entry for a package's latest version, or None when
/// the package is not published there. Only the package name is sent.
pub async fn get_npm_latest(name : String) -> Result[String?, String] {
  // A scoped name keeps its @ and encodes the slash: @types%2Fnode.
  let encoded = name.replace_all(old="/", new="%2F")
  get_public("https://registry.npmjs.org/\{encoded}/latest", "npm registry")
}

///|
/// The `maven-metadata.xml` of a library or Gradle plugin marker: every
/// published version. Read fresh each time, since new versions are added.
pub async fn get_maven_metadata(
  repository : String,
  group : String,
  artifact : String,
) -> Result[String?, String] {
  let registry = if repository == GRADLE_PLUGIN_PORTAL {
    "Gradle Plugin Portal"
  } else {
    "Maven Central"
  }
  get_public(
    "\{repository}/\{group.replace_all(old=".", new="/")}/\{artifact}/maven-metadata.xml",
    registry,
    cache=false,
  )
}

///|
/// The npm registry's whole document for a package, with every version
/// and when it was published. Read fresh each time.
pub async fn get_npm_document(name : String) -> Result[String?, String] {
  let encoded = name.replace_all(old="/", new="%2F")
  get_public(
    "https://registry.npmjs.org/\{encoded}",
    "npm registry",
    cache=false,
  )
}

///|
/// The top-level file names of a public repository on Bitbucket or GitLab.
/// Only the repository's name is sent.
pub async fn list_hosted_files(
  host : String,
  repository : String,
) -> Result[Array[String], String] {
  let (url, key, array_field) = match host {
    "bitbucket.org" =>
      (
        "https://api.bitbucket.org/2.0/repositories/\{repository}/src/HEAD/?pagelen=100",
        "path",
        "values",
      )
    "gitlab.com" =>
      (
        "https://gitlab.com/api/v4/projects/\{repository.replace_all(old="/", new="%2F")}/repository/tree?per_page=100",
        "name",
        "",
      )
    _ => return Err("\{host} is not a supported source host")
  }
  match get_public(url, host, cache=false) {
    Ok(Some(text)) => {
      let json = @json.parse(text) catch {
        _ => return Err("\{host} file list could not be decoded")
      }
      let entries = match (json, array_field) {
        (Array(items), "") => items
        (Object(fields), field) =>
          match fields.get(field) {
            Some(Array(items)) => items
            _ => []
          }
        _ => []
      }
      let names : Array[String] = []
      for entry in entries {
        match entry {
          Object(fields) =>
            match fields.get(key) {
              Some(String(name)) => names.push(name)
              _ => ()
            }
          _ => ()
        }
      }
      Ok(names)
    }
    Ok(None) => Ok([])
    Err(error) => Err(error)
  }
}

///|
/// A file at the default branch of a public repository on Bitbucket or
/// GitLab, or None when it is not there.
pub async fn get_hosted_file(
  host : String,
  repository : String,
  path : String,
) -> Result[String?, String] {
  let url = match host {
    "bitbucket.org" => "https://bitbucket.org/\{repository}/raw/HEAD/\{path}"
    "gitlab.com" => "https://gitlab.com/\{repository}/-/raw/HEAD/\{path}"
    _ => return Err("\{host} is not a supported source host")
  }
  get_public(url, host, cache=false)
}
