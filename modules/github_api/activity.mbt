///|
struct ApiUser {
  login : String
} derive(FromJson)

///|
pub extend ApiUser with @json.FromJson::{from_json}

///|
struct IssueWire {
  number : Int
  title : String
  html_url : String
  user : ApiUser
  updated_at : String
  pull_request : Json?
} derive(FromJson)

///|
pub extend IssueWire with @json.FromJson::{from_json}

///|
struct PullRequestWire {
  number : Int
  title : String
  html_url : String
  user : ApiUser
  updated_at : String
  draft : Bool
} derive(FromJson)

///|
pub extend PullRequestWire with @json.FromJson::{from_json}

///|
pub(all) enum ActivityKind {
  Issue
  PullRequest
}

///|
pub struct ActivitySummary {
  repository : String
  number : Int
  title : String
  html_url : String
  author : String
  updated_at : String
  kind : ActivityKind
  draft : Bool
}

///|
pub fn ActivitySummary::repository(self : ActivitySummary) -> String {
  self.repository
}

///|
pub fn ActivitySummary::number(self : ActivitySummary) -> Int {
  self.number
}

///|
pub fn ActivitySummary::title(self : ActivitySummary) -> String {
  self.title
}

///|
pub fn ActivitySummary::html_url(self : ActivitySummary) -> String {
  self.html_url
}

///|
pub fn ActivitySummary::author(self : ActivitySummary) -> String {
  self.author
}

///|
pub fn ActivitySummary::updated_at(self : ActivitySummary) -> String {
  self.updated_at
}

///|
pub fn ActivitySummary::kind(self : ActivitySummary) -> ActivityKind {
  self.kind
}

///|
pub fn ActivitySummary::is_draft(self : ActivitySummary) -> Bool {
  self.draft
}

///|
pub fn decode_issues(
  json : Json,
  repository : String,
) -> Result[Array[ActivitySummary], String] {
  try {
    let wire : Array[IssueWire] = @json.from_json(json)
    let issues : Array[ActivitySummary] = []
    for item in wire {
      if item.pull_request is None {
        issues.push({
          repository,
          number: item.number,
          title: item.title,
          html_url: item.html_url,
          author: item.user.login,
          updated_at: item.updated_at,
          kind: Issue,
          draft: false,
        })
      }
    }
    Ok(issues)
  } catch {
    _ => Err("GitHub issue response could not be decoded")
  }
}

///|
pub fn decode_pull_requests(
  json : Json,
  repository : String,
) -> Result[Array[ActivitySummary], String] {
  try {
    let wire : Array[PullRequestWire] = @json.from_json(json)
    Ok(
      wire.map(item => {
        repository,
        number: item.number,
        title: item.title,
        html_url: item.html_url,
        author: item.user.login,
        updated_at: item.updated_at,
        kind: PullRequest,
        draft: item.draft,
      }),
    )
  } catch {
    _ => Err("GitHub pull request response could not be decoded")
  }
}

///|
/// Up to 2,000 open issues per repository, newest first.
pub async fn list_open_issues(
  token : String,
  owner : String,
  name : String,
) -> Result[Listing, String] {
  // The issues endpoint also returns pull requests, which decode_issues
  // drops, so a full page is judged by the raw entry count.
  get_all_pages(
    token,
    page => repository_issues_path(owner, name, page),
    20,
    json => decode_issues(json, "\{owner}/\{name}"),
    json_array_length,
  )
}

///|
/// Up to 2,000 open pull requests per repository, newest first.
pub async fn list_open_pull_requests(
  token : String,
  owner : String,
  name : String,
) -> Result[Listing, String] {
  get_all_pages(
    token,
    page => repository_pulls_path(owner, name, page),
    20,
    json => decode_pull_requests(json, "\{owner}/\{name}"),
    json_array_length,
  )
}

///|
/// Decodes one item from the issues endpoint, which also returns pull
/// requests. The endpoint does not report draft state.
pub fn decode_activity(
  json : Json,
  repository : String,
) -> Result[ActivitySummary, String] {
  try {
    let item : IssueWire = @json.from_json(json)
    Ok({
      repository,
      number: item.number,
      title: item.title,
      html_url: item.html_url,
      author: item.user.login,
      updated_at: item.updated_at,
      kind: if item.pull_request is Some(_) {
        PullRequest
      } else {
        Issue
      },
      draft: false,
    })
  } catch {
    _ => Err("GitHub issue response could not be decoded")
  }
}

///|
/// One issue or pull request by number.
pub async fn get_activity(
  token : String,
  owner : String,
  name : String,
  number : Int,
) -> Result[ActivitySummary, String] {
  match get_json(token, repository_issue_path(owner, name, number)) {
    Ok(json) => decode_activity(json, "\{owner}/\{name}")
    Err(error) => Err(error)
  }
}

///|
struct PullRequestStateWire {
  number : Int
  title : String
  html_url : String
  user : ApiUser
  updated_at : String
  draft : Bool
  state : String
  merged : Bool
} derive(FromJson)

///|
pub extend PullRequestStateWire with @json.FromJson::{from_json}

///|
/// A pull request with whether it is still open (not closed or merged).
pub fn decode_pull_request_state(
  json : Json,
  repository : String,
) -> Result[(ActivitySummary, Bool), String] {
  try {
    let item : PullRequestStateWire = @json.from_json(json)
    Ok(
      (
        {
          repository,
          number: item.number,
          title: item.title,
          html_url: item.html_url,
          author: item.user.login,
          updated_at: item.updated_at,
          kind: PullRequest,
          draft: item.draft,
        },
        item.state == "open" && !item.merged,
      ),
    )
  } catch {
    _ => Err("GitHub pull request response could not be decoded")
  }
}

///|
pub async fn get_pull_request_state(
  token : String,
  owner : String,
  name : String,
  number : Int,
) -> Result[(ActivitySummary, Bool), String] {
  match get_json(token, pull_request_path(owner, name, number)) {
    Ok(json) => decode_pull_request_state(json, "\{owner}/\{name}")
    Err(error) => Err(error)
  }
}

///|
/// Logins that submitted a review that still stands: pending drafts and
/// dismissed reviews do not count. Reviews by deleted users have no login.
pub fn decode_review_authors(json : Json) -> Result[Array[String], String] {
  guard json is Array(reviews) else {
    return Err("GitHub review response could not be decoded")
  }
  let authors : Array[String] = []
  for review in reviews {
    guard review is Object(fields) else { continue }
    guard fields.get("state") is Some(String(state)) &&
      state != "PENDING" &&
      state != "DISMISSED" else {
      continue
    }
    guard fields.get("user") is Some(Object(user)) &&
      user.get("login") is Some(String(login)) else {
      continue
    }
    if !authors.contains(login) {
      authors.push(login)
    }
  }
  Ok(authors)
}

///|
pub async fn list_review_authors(
  token : String,
  owner : String,
  name : String,
  number : Int,
) -> Result[Array[String], String] {
  match get_json(token, pull_request_reviews_path(owner, name, number)) {
    Ok(json) => decode_review_authors(json)
    Err(error) => Err(error)
  }
}
