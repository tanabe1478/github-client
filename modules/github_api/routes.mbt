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
pub fn review_requests_search_path(login : String, page : Int) -> String {
  "/search/issues?q=is%3Aopen+is%3Apr+review-requested%3A\{login}&sort=updated&order=desc&per_page=100&page=\{page}"
}

///|
pub fn repository_path(owner : String, name : String) -> String {
  "/repos/\{owner}/\{name}"
}

///|
pub fn repository_issues_path(
  owner : String,
  name : String,
  page : Int,
) -> String {
  "/repos/\{owner}/\{name}/issues?state=open&sort=updated&direction=desc&per_page=100&page=\{page}"
}

///|
pub fn repository_issue_path(
  owner : String,
  name : String,
  number : Int,
) -> String {
  "/repos/\{owner}/\{name}/issues/\{number}"
}

///|
pub fn pull_request_path(owner : String, name : String, number : Int) -> String {
  "/repos/\{owner}/\{name}/pulls/\{number}"
}

///|
pub fn pull_request_reviews_path(
  owner : String,
  name : String,
  number : Int,
) -> String {
  "/repos/\{owner}/\{name}/pulls/\{number}/reviews?per_page=100"
}

///|
pub fn repository_pulls_path(
  owner : String,
  name : String,
  page : Int,
) -> String {
  "/repos/\{owner}/\{name}/pulls?state=open&sort=updated&direction=desc&per_page=100&page=\{page}"
}

///|
/// Review comments on any pull request in the repository, updated at or
/// after `since` (ISO 8601).
pub fn repository_review_comments_path(
  owner : String,
  name : String,
  since : String,
  page : Int,
) -> String {
  "/repos/\{owner}/\{name}/pulls/comments?sort=updated&direction=desc&since=\{since}&per_page=100&page=\{page}"
}

///|
pub fn repository_sbom_path(owner : String, name : String) -> String {
  "/repos/\{owner}/\{name}/dependency-graph/sbom"
}
