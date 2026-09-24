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
    review_requests_search_path("octocat"),
    content="/search/issues?q=is%3Aopen+is%3Apr+review-requested%3Aoctocat&sort=updated&order=desc&per_page=50",
  )
  inspect(
    repository_pulls_path("moonbitlang", "moonbit"),
    content="/repos/moonbitlang/moonbit/pulls?state=open&sort=updated&direction=desc&per_page=50",
  )
  inspect(
    repository_sbom_path("acme", "desktop"),
    content="/repos/acme/desktop/dependency-graph/sbom",
  )
}
