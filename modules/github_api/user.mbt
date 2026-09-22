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
  match get_json(token, authenticated_user_path()) {
    Ok(json) => decode_authenticated_user(json)
    Err(error) => Err(error)
  }
}
