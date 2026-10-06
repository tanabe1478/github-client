///|
struct PersonalActivityWire {
  number : Int
  title : String
  html_url : String
  repository_url : String
  user : ApiUser
  updated_at : String
  state : String?
  pull_request : Json?
} derive(FromJson)

///|
pub extend PersonalActivityWire with @json.FromJson::{from_json}

///|
struct SearchResponseWire {
  items : Array[PersonalActivityWire]
} derive(FromJson)

///|
pub extend SearchResponseWire with @json.FromJson::{from_json}

///|
fn repository_name_from_api_url(url : String) -> Result[String, String] {
  let parts = url.split("/repos/").to_array()
  guard parts.length() == 2 && parts[1] != "" else {
    return Err("GitHub activity response has an invalid repository URL")
  }
  Ok(parts[1].to_owned())
}

///|
fn personal_activity_from_wire(
  item : PersonalActivityWire,
) -> Result[ActivitySummary, String] {
  guard repository_name_from_api_url(item.repository_url) is Ok(repository) else {
    return Err("GitHub activity response has an invalid repository URL")
  }
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
    state: issue_state(item.state, item.pull_request),
  })
}

///|
fn decode_personal_activity_items(
  items : Array[PersonalActivityWire],
) -> Result[Array[ActivitySummary], String] {
  let result : Array[ActivitySummary] = []
  for item in items {
    guard personal_activity_from_wire(item) is Ok(activity) else {
      return Err("GitHub personal activity response could not be decoded")
    }
    result.push(activity)
  }
  Ok(result)
}

///|
pub fn decode_personal_activity_search(
  json : Json,
) -> Result[Array[ActivitySummary], String] {
  try {
    let response : SearchResponseWire = @json.from_json(json)
    decode_personal_activity_items(response.items)
  } catch {
    _ => Err("GitHub personal activity response could not be decoded")
  }
}

///|
pub fn decode_subscribed_issues(
  json : Json,
) -> Result[Array[ActivitySummary], String] {
  try {
    let items : Array[PersonalActivityWire] = @json.from_json(json)
    decode_personal_activity_items(items)
  } catch {
    _ => Err("GitHub subscribed issue response could not be decoded")
  }
}

///|
fn search_items_length(json : Json) -> Int {
  match json {
    Object(fields) =>
      match fields.get("items") {
        Some(Array(items)) => items.length()
        _ => 0
      }
    _ => 0
  }
}

///|
/// Personal issues and pull requests for one filter, up to 1,000.
async fn list_personal_issues(
  token : String,
  filter : String,
) -> Result[Listing, String] {
  get_all_pages(
    token,
    page => personal_issues_path(filter, page),
    10,
    decode_subscribed_issues,
    json_array_length,
  )
}

///|
pub async fn search_mentions(
  token : String,
  _login : String,
) -> Result[Listing, String] {
  list_personal_issues(token, "mentioned")
}

///|
/// Closed or merged issues and pull requests mentioning the viewer that
/// were updated at or after `since`, up to 1,000.
pub async fn list_closed_mentions(
  token : String,
  since : String,
) -> Result[Listing, String] {
  get_all_pages(
    token,
    page => closed_personal_issues_path("mentioned", since, page),
    10,
    decode_subscribed_issues,
    json_array_length,
  )
}

///|
pub async fn search_assignments(
  token : String,
  _login : String,
) -> Result[Listing, String] {
  list_personal_issues(token, "assigned")
}

///|
/// Open pull requests requesting the viewer's review, directly or through
/// a team. GitHub search returns at most 1,000 results.
pub async fn search_review_requests(
  token : String,
  login : String,
) -> Result[Listing, String] {
  get_all_pages(
    token,
    page => review_requests_search_path(login, page),
    10,
    decode_personal_activity_search,
    search_items_length,
  )
}

///|
pub async fn list_subscribed_issues(token : String) -> Result[Listing, String] {
  list_personal_issues(token, "subscribed")
}
