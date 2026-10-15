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
async fn get_public(url : String, registry : String) -> Result[String?, String] {
  match registry_cache.get(url) {
    Some(cached) => return Ok(Some(cached))
    None => ()
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
          return match get_public(location, registry) {
            Ok(Some(text)) => {
              registry_cache.set(url, text)
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
    registry_cache.set(url, text)
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
