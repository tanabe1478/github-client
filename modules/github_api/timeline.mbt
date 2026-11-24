///|
/// One change on an issue or pull request timeline. `actor` is empty when
/// the timeline does not name a GitHub user, which is the case for
/// `committed` events: those carry the commit's `sha` in `commit` instead.
pub(all) struct TimelineEntry {
  at : String
  actor : String
  commit : String
} derive(Eq, Debug)

///|
fn json_string(fields : Map[String, Json], key : String) -> String {
  match fields.get(key) {
    Some(String(value)) => value
    _ => ""
  }
}

///|
fn json_login(fields : Map[String, Json], key : String) -> String {
  match fields.get(key) {
    Some(Object(user)) => json_string(user, "login")
    _ => ""
  }
}

///|
/// Timeline events with when they happened and who made them. Grouped
/// review comments (`line-commented`, `commit-commented`) count once per
/// comment. Entries without a time, such as a pending review, are dropped.
pub fn decode_timeline(json : Json) -> Result[Array[TimelineEntry], String] {
  guard json is Array(events) else {
    return Err("GitHub timeline response could not be decoded")
  }
  let entries : Array[TimelineEntry] = []
  for event in events {
    guard event is Object(fields) else { continue }
    if fields.get("comments") is Some(Array(comments)) {
      for comment in comments {
        guard comment is Object(comment_fields) else { continue }
        let at = json_string(comment_fields, "created_at")
        if at != "" {
          entries.push({
            at,
            actor: json_login(comment_fields, "user"),
            commit: "",
          })
        }
      }
      continue
    }
    if json_string(fields, "event") == "committed" {
      let at = match fields.get("committer") {
        Some(Object(committer)) => json_string(committer, "date")
        _ => ""
      }
      if at != "" {
        entries.push({ at, actor: "", commit: json_string(fields, "sha"), })
      }
      continue
    }
    let at = match json_string(fields, "submitted_at") {
      "" => json_string(fields, "created_at")
      submitted => submitted
    }
    if at == "" {
      continue
    }
    let actor = match json_login(fields, "actor") {
      "" => json_login(fields, "user")
      login => login
    }
    entries.push({ at, actor, commit: "", })
  }
  Ok(entries)
}

///|
/// The whole timeline of an issue or pull request, oldest first. The
/// `Bool` is false when the page limit stopped it before the end.
pub async fn list_timeline(
  token : String,
  owner : String,
  name : String,
  number : Int,
) -> Result[(Array[TimelineEntry], Bool), String] {
  let entries : Array[TimelineEntry] = []
  for page = 1; page <= 5; page = page + 1 {
    let json = match
      get_json(token, issue_timeline_path(owner, name, number, page)) {
      Ok(json) => json
      Err(error) => return Err(error)
    }
    match decode_timeline(json) {
      Ok(decoded) => entries.append(decoded)
      Err(error) => return Err(error)
    }
    if json_array_length(json) < PAGE_SIZE {
      return Ok((entries, true))
    }
  }
  Ok((entries, false))
}

///|
/// The GitHub login that authored each commit, by SHA. Commits whose
/// author email is not linked to an account are left out.
pub fn decode_commit_authors(
  json : Json,
) -> Result[Map[String, String], String] {
  guard json is Array(commits) else {
    return Err("GitHub commit response could not be decoded")
  }
  let authors : Map[String, String] = Map([])
  for commit in commits {
    guard commit is Object(fields) else { continue }
    let sha = json_string(fields, "sha")
    let login = json_login(fields, "author")
    if sha != "" && login != "" {
      authors.set(sha, login)
    }
  }
  Ok(authors)
}

///|
/// Authors of the first 100 commits of a pull request, by SHA.
pub async fn list_pull_request_commit_authors(
  token : String,
  owner : String,
  name : String,
  number : Int,
) -> Result[Map[String, String], String] {
  match get_json(token, pull_request_commits_path(owner, name, number)) {
    Ok(json) => decode_commit_authors(json)
    Err(error) => Err(error)
  }
}
