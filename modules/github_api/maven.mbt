///|
/// BOM poms already fetched, by URL. A published version never changes.
let maven_cache : Map[String, String] = Map([])

///|
/// The URL of a pom on Maven Central.
pub fn maven_pom_url(
  group : String,
  artifact : String,
  version : String,
) -> String {
  "https://repo1.maven.org/maven2/\{group.replace_all(old=".", new="/")}/\{artifact}/\{version}/\{artifact}-\{version}.pom"
}

///|
/// A published pom from Maven Central, such as Spring Boot's
/// spring-boot-dependencies BOM, or None when it is not published. Only the
/// public coordinates are sent; no token and nothing about the project.
pub async fn get_maven_pom(
  group : String,
  artifact : String,
  version : String,
) -> Result[String?, String] {
  let url = maven_pom_url(group, artifact, version)
  match maven_cache.get(url) {
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
    if response.code == 404 {
      return Ok(None)
    }
    if response.code < 200 || response.code >= 300 {
      return Err("Maven Central request failed with status \{response.code}")
    }
    let text = body.text()
    maven_cache.set(url, text)
    Ok(Some(text))
  } catch {
    _ => Err("Maven Central request failed before a response was received")
  }
}
