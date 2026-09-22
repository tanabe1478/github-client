///|
test "routes cover only the product API surface" {
  inspect(@github_api.authenticated_user_path(), content="/user")
  inspect(
    @github_api.repository_pulls_path("moonbitlang", "moonbit"),
    content="/repos/moonbitlang/moonbit/pulls?state=open&sort=updated&direction=desc&per_page=50",
  )
  inspect(
    @github_api.repository_sbom_path("acme", "desktop"),
    content="/repos/acme/desktop/dependency-graph/sbom",
  )
}
