///|
/// The newest 30 releases, the most a watched repository shows.
pub fn repository_releases_path(owner : String, name : String) -> String {
  "/repos/\{owner}/\{name}/releases?per_page=30"
}

///|
/// The first sentence of release notes: the first line that is prose, not
/// a heading, list item, table, quote, or HTML, cut at its first ". ".
pub fn release_summary(body : String) -> String {
  for raw in body.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw.trim().to_owned()
    if line == "" ||
      line.has_prefix("#") ||
      line.has_prefix("-") ||
      line.has_prefix("*") ||
      line.has_prefix("|") ||
      line.has_prefix(">") ||
      line.has_prefix("<") ||
      line.has_prefix("```") {
      continue
    }
    return match line.find(". ") {
      Some(index) => line[:index + 1].to_owned()
      None => line
    }
  }
  ""
}

///|
/// Published releases, newest first. Drafts and releases without a
/// publication date are skipped. `updated_at` holds the publication date,
/// so Done stays until a new release replaces it.
pub fn decode_releases(
  json : Json,
  repository : String,
) -> Result[Array[ActivitySummary], String] {
  guard json is Array(entries) else {
    return Err("GitHub release response could not be decoded")
  }
  let releases : Array[ActivitySummary] = []
  for entry in entries {
    guard entry is Object(fields) else { continue }
    guard fields.get("draft") is Some(False) || fields.get("draft") is None else {
      continue
    }
    guard fields.get("published_at") is Some(String(published_at)) &&
      fields.get("html_url") is Some(String(html_url)) &&
      fields.get("tag_name") is Some(String(tag)) else {
      continue
    }
    let title = match fields.get("name") {
      Some(String(name)) if name.trim() != "" => name.trim().to_owned()
      _ => tag
    }
    let author = match fields.get("author") {
      Some(Object(user)) =>
        match user.get("login") {
          Some(String(login)) => login
          _ => ""
        }
      _ => ""
    }
    let notes = match fields.get("body") {
      Some(String(body)) => body
      _ => ""
    }
    let summary = release_summary(notes)
    releases.push({
      repository,
      number: 0,
      title,
      html_url,
      author,
      updated_at: published_at,
      tag,
      summary,
      notes,
      prerelease: fields.get("prerelease") is Some(True),
      kind: Release,
      draft: false,
      state: Open,
    })
  }
  Ok(releases)
}

///|
pub async fn list_releases(
  token : String,
  owner : String,
  name : String,
) -> Result[Array[ActivitySummary], String] {
  match get_json(token, repository_releases_path(owner, name)) {
    Ok(json) => decode_releases(json, "\{owner}/\{name}")
    Err(error) => Err(error)
  }
}

///|
/// `tag` as it appears in a release URL, already percent-encoded.
pub fn release_by_tag_path(
  owner : String,
  name : String,
  tag : String,
) -> String {
  "/repos/\{owner}/\{name}/releases/tags/\{tag}"
}

///|
pub async fn get_release(
  token : String,
  owner : String,
  name : String,
  tag : String,
) -> Result[ActivitySummary, String] {
  match get_json(token, release_by_tag_path(owner, name, tag)) {
    Ok(json) =>
      match decode_releases([json], "\{owner}/\{name}") {
        Ok(releases) if releases.length() > 0 => Ok(releases[0])
        Ok(_) => Err("the release is a draft or not published")
        Err(error) => Err(error)
      }
    Err(error) => Err(error)
  }
}

///|
/// A file at the root of a repository's default branch, as the contents API
/// returns it (base64). None when the repository has no such file.
pub fn repository_file_path(
  owner : String,
  name : String,
  path : String,
) -> String {
  "/repos/\{owner}/\{name}/contents/\{path}"
}

///|
/// Paths of every file on the default branch, or None when the repository
/// does not exist. An empty repository has no files. GitHub may truncate a
/// very large tree; the paths it sent are used.
pub async fn list_files(
  token : String,
  owner : String,
  name : String,
) -> Result[Array[String]?, String] {
  match get_json(token, "/repos/\{owner}/\{name}/git/trees/HEAD?recursive=1") {
    Ok(Object(fields)) => {
      let paths : Array[String] = []
      match fields.get("tree") {
        Some(Array(entries)) =>
          for entry in entries {
            guard entry is Object(item) else { continue }
            guard item.get("type") is Some(String("blob")) else { continue }
            guard item.get("path") is Some(String(path)) else { continue }
            paths.push(path)
          }
        _ => ()
      }
      Ok(Some(paths))
    }
    Ok(_) => Err("GitHub sent an unexpected file list")
    Err(error) =>
      if classify_failure(error) is NotFound {
        Ok(None)
      } else if error.contains("status 409") {
        // 409 Conflict: the repository is empty.
        Ok(Some([]))
      } else {
        Err(error)
      }
  }
}

///|
/// The base64 content of a file, or None when it does not exist.
pub async fn get_file_content(
  token : String,
  owner : String,
  name : String,
  path : String,
) -> Result[String?, String] {
  match get_json(token, repository_file_path(owner, name, path)) {
    Ok(Object(fields)) =>
      match fields.get("content") {
        Some(String(content)) => Ok(Some(content))
        _ => Err("\{path} is not a file")
      }
    Ok(_) => Err("\{path} is not a file")
    Err(error) =>
      if classify_failure(error) is NotFound {
        Ok(None)
      } else {
        Err(error)
      }
  }
}
