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
/// Last response per token and path, with its ETag. GitHub answers a
/// request carrying the ETag with 304 Not Modified and an empty body when
/// nothing changed; 304 responses do not count against the rate limit.
let etag_cache : Map[String, (String, Json)] = Map([])

///|
async fn get_json(token : String, path : String) -> Result[Json, String] {
  try {
    let started = @async.now()
    let cache_key = "\{token.hash()}|\{path}"
    let headers = request_headers(token)
    match etag_cache.get(cache_key) {
      Some((etag, _)) =>
        headers.set(@http.CaseInsensitiveString("If-None-Match"), etag)
      None => ()
    }
    let (response, body) = @http.get("https://api.github.com\{path}", headers~)
    let fetched = @async.now()
    defer log(
      "http: status=\{response.code} fetch_ms=\{fetched - started} path=\{path}",
    )
    if response.code == 304 {
      match etag_cache.get(cache_key) {
        Some((_, json)) => return Ok(json)
        None => return Err("GitHub request failed with status 304")
      }
    }
    if response.code == 401 {
      return Err("GitHub rejected the saved token")
    }
    if response.code == 403 || response.code == 429 {
      let remaining = response.headers.get(
        @http.CaseInsensitiveString("X-RateLimit-Remaining"),
      )
      let reset = response.headers.get(
        @http.CaseInsensitiveString("X-RateLimit-Reset"),
      )
      if remaining == Some("0") && reset is Some(epoch) {
        return Err("\{rate_limit_message_prefix}\{epoch})")
      }
      return Err("GitHub denied the request or the API rate limit was reached")
    }
    if response.code == 404 {
      return Err("GitHub repository was not found or is not accessible")
    }
    if response.code < 200 || response.code >= 300 {
      return Err("GitHub request failed with status \{response.code}")
    }
    let json = body.json()
    log("http: parse_ms=\{@async.now() - fetched} path=\{path}")
    match response.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag_cache.set(cache_key, (etag, json))
      None => ()
    }
    Ok(json)
  } catch {
    _ => Err("GitHub request failed before a response was received")
  }
}

///|
let rate_limit_message_prefix = "GitHub API rate limit was reached (resets at "

///|
/// The kind of failure behind an error message from this package.
pub(all) enum ApiFailure {
  Unauthorized
  /// Seconds since the Unix epoch at which the limit resets.
  RateLimited(Int64)
  Forbidden
  NotFound
  Network
  Other
} derive(Eq, Debug)

///|
/// Classifies an error message returned by this package, including messages
/// that callers prefixed with context.
pub fn classify_failure(message : String) -> ApiFailure {
  if message.contains("GitHub rejected the saved token") {
    return Unauthorized
  }
  if message.find(rate_limit_message_prefix) is Some(start) {
    let rest = message[start + rate_limit_message_prefix.length():]
    let mut epoch = 0L
    for character in rest {
      if character >= '0' && character <= '9' {
        epoch = epoch * 10L + (character.to_int() - '0'.to_int()).to_int64()
      } else {
        break
      }
    }
    return RateLimited(epoch)
  }
  if message.contains("GitHub denied the request") {
    return Forbidden
  }
  if message.contains("not found or is not accessible") {
    return NotFound
  }
  if message.contains("failed before a response was received") {
    return Network
  }
  Other
}

///|
let logger : Ref[(String) -> Unit] = Ref(println)

///|
/// Replaces where diagnostic lines from this package and its callers go.
/// The desktop app keeps the default (stdout); the command-line client
/// silences them so stdout carries only its own output.
pub fn set_logger(write : (String) -> Unit) -> Unit {
  logger.val = write
}

///|
pub fn log(message : String) -> Unit {
  (logger.val)(message)
}

///|
/// Items from a paged list endpoint. `complete` is false when the page
/// limit stopped the listing before its last page.
pub(all) struct Listing {
  items : Array[ActivitySummary]
  complete : Bool
}

///|
/// GitHub pages hold at most 100 items.
const PAGE_SIZE : Int = 100

///|
fn json_array_length(json : Json) -> Int {
  match json {
    Array(items) => items.length()
    _ => 0
  }
}

///|
/// Fetches pages 1..`max_pages` until a page holds fewer than 100 raw
/// entries. `decode` turns one page into items; `raw_count` counts the
/// entries GitHub returned on it, which can exceed the items kept.
async fn get_all_pages(
  token : String,
  path_for : (Int) -> String,
  max_pages : Int,
  decode : (Json) -> Result[Array[ActivitySummary], String],
  raw_count : (Json) -> Int,
) -> Result[Listing, String] {
  let items : Array[ActivitySummary] = []
  for page = 1; page <= max_pages; page = page + 1 {
    let json = match get_json(token, path_for(page)) {
      Ok(json) => json
      Err(error) => return Err(error)
    }
    match decode(json) {
      Ok(decoded) => items.append(decoded)
      Err(error) => return Err(error)
    }
    if raw_count(json) < PAGE_SIZE {
      return Ok({ items, complete: true, })
    }
  }
  Ok({ items, complete: false, })
}
