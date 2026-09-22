///|
test "routes cover only the product API surface" {
  inspect(authenticated_user_path(), content="/user")
  inspect(
    owned_repositories_path(2),
    content="/user/repos?affiliation=owner&visibility=all&sort=updated&direction=desc&per_page=100&page=2",
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
