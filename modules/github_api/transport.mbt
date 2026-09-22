///|
fn request_headers(token : String) -> @http.Headers {
  let headers : @http.Headers = Map([])
  headers.set(
    @http.CaseInsensitiveString("Accept"),
    "application/vnd.github+json",
  )
  headers.set(@http.CaseInsensitiveString("X-GitHub-Api-Version"), "2022-11-28")
  headers.set(
    @http.CaseInsensitiveString("User-Agent"),
    "tanabe1478-github-client/0.1.0",
  )
  headers.set(@http.CaseInsensitiveString("Authorization"), "Bearer \{token}")
  headers
}

///|
async fn get_json(token : String, path : String) -> Result[Json, String] {
  try {
    let (response, body) = @http.get(
      "https://api.github.com\{path}",
      headers=request_headers(token),
    )
    if response.code == 401 {
      return Err("GitHub rejected the saved token")
    }
    if response.code == 403 {
      return Err("GitHub denied the request or the API rate limit was reached")
    }
    if response.code == 404 {
      return Err("GitHub repository was not found or is not accessible")
    }
    if response.code < 200 || response.code >= 300 {
      return Err("GitHub request failed with status \{response.code}")
    }
    Ok(body.json())
  } catch {
    _ => Err("GitHub request failed before a response was received")
  }
}
