///|
test "routes cover only the product API surface" {
  inspect(authenticated_user_path(), content="/user")
  inspect(
    accessible_repositories_path(2),
    content="/user/repos?affiliation=owner,collaborator,organization_member&visibility=all&sort=updated&direction=desc&per_page=100&page=2",
  )
  inspect(
    personal_issues_path("mentioned", 2),
    content="/issues?filter=mentioned&state=open&sort=updated&direction=desc&per_page=100&page=2",
  )
  inspect(
    closed_personal_issues_path("mentioned", "2026-09-06T00:00:00Z", 1),
    content="/issues?filter=mentioned&state=closed&since=2026-09-06T00:00:00Z&sort=updated&direction=desc&per_page=100&page=1",
  )
  inspect(
    review_requests_search_path("octocat", 2),
    content="/search/issues?q=is%3Aopen+is%3Apr+review-requested%3Aoctocat&sort=updated&order=desc&per_page=100&page=2",
  )
  inspect(
    repository_pulls_path("moonbitlang", "moonbit", 1),
    content="/repos/moonbitlang/moonbit/pulls?state=open&sort=updated&direction=desc&per_page=100&page=1",
  )
  inspect(
    repository_sbom_path("acme", "desktop"),
    content="/repos/acme/desktop/dependency-graph/sbom",
  )
}
