///|
struct PersonalActivityWire {
  number : Int
  title : String
  html_url : String
  repository_url : String
  user : ApiUser
  updated_at : String
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
async fn search_personal_activity(
  token : String,
  path : String,
) -> Result[Array[ActivitySummary], String] {
  match get_json(token, path) {
    Ok(json) => decode_personal_activity_search(json)
    Err(error) => Err(error)
  }
}

///|
async fn list_personal_issues(
  token : String,
  filter : String,
) -> Result[Array[ActivitySummary], String] {
  let result : Array[ActivitySummary] = []
  for page = 1; page <= 10; page = page + 1 {
    guard get_json(token, personal_issues_path(filter, page)) is Ok(json) else {
      return Err("GitHub personal activity could not be loaded")
    }
    guard decode_subscribed_issues(json) is Ok(items) else {
      return Err("GitHub personal activity response could not be decoded")
    }
    let count = items.length()
    result.append(items)
    if count < 100 {
      break
    }
  }
  Ok(result)
}

///|
pub async fn search_mentions(
  token : String,
  _login : String,
) -> Result[Array[ActivitySummary], String] {
  list_personal_issues(token, "mentioned")
}

///|
pub async fn search_assignments(
  token : String,
  _login : String,
) -> Result[Array[ActivitySummary], String] {
  list_personal_issues(token, "assigned")
}

///|
pub async fn search_review_requests(
  token : String,
  login : String,
) -> Result[Array[ActivitySummary], String] {
  search_personal_activity(token, review_requests_search_path(login))
}

///|
pub async fn list_subscribed_issues(
  token : String,
) -> Result[Array[ActivitySummary], String] {
  list_personal_issues(token, "subscribed")
}
