///|
/// GitHub's mention filter (`/issues?filter=mentioned`, `mentions:` search)
/// does not cover review comments on pull request diffs, so mentions there
/// are found by reading the comments.

///|
fn is_login_char(character : Char) -> Bool {
  (character >= 'a' && character <= 'z') ||
  (character >= 'A' && character <= 'Z') ||
  (character >= '0' && character <= '9') ||
  character == '-' ||
  character == '_'
}

///|
/// Whether `body` mentions `@login`, ignoring case. An address such as
/// `name@login.dev` and a team such as `@login/team` do not count.
pub fn mentions_login(body : String, login : String) -> Bool {
  if login == "" {
    return false
  }
  let text = body.to_lower().to_array()
  let needle = ("@" + login.to_lower()).to_array()
  for start = 0; start + needle.length() <= text.length(); start = start + 1 {
    let mut matched = true
    for offset = 0; offset < needle.length(); offset = offset + 1 {
      if text[start + offset] != needle[offset] {
        matched = false
        break
      }
    }
    guard matched else { continue }
    let end = start + needle.length()
    let before_ok = start == 0 || !is_login_char(text[start - 1])
    let after_ok = end == text.length() ||
      !(is_login_char(text[end]) || text[end] == '/')
    if before_ok && after_ok {
      return true
    }
  }
  false
}

///|
fn pull_number_from_api_url(url : String) -> Int? {
  let parts = url.split("/pulls/").to_array()
  guard parts.length() == 2 && parts[1] != "" else { return None }
  let mut number = 0
  for character in parts[1] {
    guard character >= '0' && character <= '9' else { return None }
    number = number * 10 + (character.to_int() - '0'.to_int())
  }
  if number > 0 {
    Some(number)
  } else {
    None
  }
}

///|
/// Pull request numbers whose review comments mention one of `logins`,
/// in first-seen order. Comments written by those logins are skipped.
pub fn decode_review_comment_mentions(
  json : Json,
  logins : Array[String],
) -> Result[Array[Int], String] {
  guard json is Array(comments) else {
    return Err("GitHub review comment response could not be decoded")
  }
  let lowered = logins.map(login => login.to_lower())
  let numbers : Array[Int] = []
  for comment in comments {
    guard comment is Object(fields) &&
      fields.get("body") is Some(String(body)) &&
      fields.get("pull_request_url") is Some(String(url)) else {
      continue
    }
    if fields.get("user") is Some(Object(user)) &&
      user.get("login") is Some(String(author)) &&
      lowered.contains(author.to_lower()) {
      continue
    }
    guard logins.any(login => mentions_login(body, login)) else { continue }
    guard pull_number_from_api_url(url) is Some(number) else { continue }
    if !numbers.contains(number) {
      numbers.push(number)
    }
  }
  Ok(numbers)
}

///|
pub(all) struct MentionedPullRequests {
  numbers : Array[Int]
  /// False when the page limit stopped the listing before its last page.
  complete : Bool
}

///|
/// Pull requests whose review comments updated since `since` mention one
/// of `logins`, reading up to 1,000 comments.
pub async fn list_review_comment_mentions(
  token : String,
  owner : String,
  name : String,
  since : String,
  logins : Array[String],
) -> Result[MentionedPullRequests, String] {
  let numbers : Array[Int] = []
  for page = 1; page <= 10; page = page + 1 {
    let json = match
      get_json(token, repository_review_comments_path(owner, name, since, page)) {
      Ok(json) => json
      Err(error) => return Err(error)
    }
    match decode_review_comment_mentions(json, logins) {
      Ok(found) =>
        for number in found {
          if !numbers.contains(number) {
            numbers.push(number)
          }
        }
      Err(error) => return Err(error)
    }
    if json_array_length(json) < PAGE_SIZE {
      return Ok({ numbers, complete: true, })
    }
  }
  Ok({ numbers, complete: false, })
}
