///|
pub struct AuthenticatedUser {
  login : String
  name : String?
  avatar_url : String
}

///|
pub fn AuthenticatedUser::login(self : AuthenticatedUser) -> String {
  self.login
}

///|
pub fn AuthenticatedUser::name(self : AuthenticatedUser) -> String? {
  self.name
}

///|
pub fn AuthenticatedUser::avatar_url(self : AuthenticatedUser) -> String {
  self.avatar_url
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
) -> Result[String, String] {
  match fields.get(key) {
    Some(String(value)) => Ok(value)
    _ => Err("GitHub response is missing \{key}")
  }
}

///|
fn optional_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
pub fn decode_authenticated_user(
  json : Json,
) -> Result[AuthenticatedUser, String] {
  guard json is Object(fields) else {
    return Err("GitHub user response must be an object")
  }
  guard required_string(fields, "login") is Ok(login) else {
    return Err("GitHub response is missing login")
  }
  guard required_string(fields, "avatar_url") is Ok(avatar_url) else {
    return Err("GitHub response is missing avatar_url")
  }
  Ok({ login, name: optional_string(fields, "name"), avatar_url, })
}

///|
pub async fn get_authenticated_user(
  token : String,
) -> Result[AuthenticatedUser, String] {
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
  try {
    let (response, body) = @http.get("https://api.github.com/user", headers~)
    if response.code == 401 {
      return Err("GitHub rejected the saved token")
    }
    if response.code < 200 || response.code >= 300 {
      return Err("GitHub request failed with status \{response.code}")
    }
    decode_authenticated_user(body.json())
  } catch {
    _ => Err("GitHub request failed before a response was received")
  }
}
