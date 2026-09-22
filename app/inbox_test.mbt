///|
fn candidate(
  repository : @app.RepositoryRef,
  mentions_viewer? : Bool = false,
  impacts_registered_repository? : Bool = false,
) -> @app.InboxCandidate {
  {
    repository,
    number: 42,
    kind: @app.InboxItemKind::Issue,
    title: "Relevant issue",
    mentions_viewer,
    impacts_registered_repository,
  }
}

///|
test "items in a registered repository are relevant" {
  let registered = @app.RepositoryRef::new("acme", "desktop")
  let reason = @app.classify_relevance([registered], [], candidate(registered))
  assert_true(reason is Some(@app.RelevanceReason::RegisteredRepository(_)))
}

///|
test "mentions are relevant in any repository" {
  let external = @app.RepositoryRef::new("external", "project")
  let reason = @app.classify_relevance(
    [],
    [],
    candidate(external, mentions_viewer=true),
  )
  assert_true(reason is Some(@app.RelevanceReason::ViewerMention))
}

///|
test "dependency activity requires an impact signal" {
  let registered = @app.RepositoryRef::new("acme", "desktop")
  let dependency = @app.RepositoryRef::new("vendor", "renderer")
  let edges = [@app.DependencyEdge::new(registered, dependency)]
  let unrelated = @app.classify_relevance(
    [registered],
    edges,
    candidate(dependency),
  )
  assert_true(unrelated is None)

  let relevant = @app.classify_relevance(
    [registered],
    edges,
    candidate(dependency, impacts_registered_repository=true),
  )
  assert_true(relevant is Some(@app.RelevanceReason::DependencyImpact(_, _)))
}
