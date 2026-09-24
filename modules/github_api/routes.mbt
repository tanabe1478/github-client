///| Minimal GitHub REST routes required by this product. Keeping these routes

///|
/// local prevents the application from inheriting an SDK-sized API surface.
pub fn authenticated_user_path() -> String {
  "/user"
}

///|
pub fn accessible_repositories_path(page : Int) -> String {
  "/user/repos?affiliation=owner,collaborator,organization_member&visibility=all&sort=updated&direction=desc&per_page=100&page=\{page}"
}

///|
pub fn personal_issues_path(filter : String, page : Int) -> String {
  "/issues?filter=\{filter}&state=open&sort=updated&direction=desc&per_page=100&page=\{page}"
}

///|
pub fn review_requests_search_path(login : String) -> String {
  "/search/issues?q=is%3Aopen+is%3Apr+review-requested%3A\{login}&sort=updated&order=desc&per_page=50"
}

///|
pub fn repository_path(owner : String, name : String) -> String {
  "/repos/\{owner}/\{name}"
}

///|
pub fn repository_issues_path(owner : String, name : String) -> String {
  "/repos/\{owner}/\{name}/issues?state=open&sort=updated&direction=desc&per_page=50"
}

///|
pub fn repository_pulls_path(owner : String, name : String) -> String {
  "/repos/\{owner}/\{name}/pulls?state=open&sort=updated&direction=desc&per_page=50"
}

///|
pub fn repository_sbom_path(owner : String, name : String) -> String {
  "/repos/\{owner}/\{name}/dependency-graph/sbom"
}
