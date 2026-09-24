///|
struct RepositoryWire {
  full_name : String
  private : Bool
  archived : Bool
} derive(FromJson)

///|
pub extend RepositoryWire with @json.FromJson::{from_json}

///|
pub struct RepositorySummary {
  full_name : String
  private : Bool
  archived : Bool
}

///|
pub fn RepositorySummary::full_name(self : RepositorySummary) -> String {
  self.full_name
}

///|
pub fn RepositorySummary::is_private(self : RepositorySummary) -> Bool {
  self.private
}

///|
pub fn RepositorySummary::is_archived(self : RepositorySummary) -> Bool {
  self.archived
}

///|
pub fn decode_repositories(
  json : Json,
) -> Result[Array[RepositorySummary], String] {
  try {
    let repositories : Array[RepositoryWire] = @json.from_json(json)
    Ok(
      repositories.map(repository => {
        full_name: repository.full_name,
        private: repository.private,
        archived: repository.archived,
      }),
    )
  } catch {
    _ => Err("GitHub repository response could not be decoded")
  }
}

///|
pub async fn list_accessible_repositories(
  token : String,
) -> Result[Array[RepositorySummary], String] {
  let result : Array[RepositorySummary] = []
  for page = 1; page <= 10; page = page + 1 {
    guard get_json(token, accessible_repositories_path(page)) is Ok(json) else {
      return Err("GitHub repository suggestions could not be loaded")
    }
    guard decode_repositories(json) is Ok(repositories) else {
      return Err("GitHub repository response could not be decoded")
    }
    let count = repositories.length()
    result.append(repositories)
    if count < 100 {
      break
    }
  }
  Ok(result)
}
