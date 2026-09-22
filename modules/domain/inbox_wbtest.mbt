///|
fn candidate(
  repository : RepositoryRef,
  mentions_viewer? : Bool = false,
  impacts_registered_repository? : Bool = false,
) -> InboxCandidate {
  {
    repository,
    number: 42,
    kind: InboxItemKind::Issue,
    title: "Relevant issue",
    mentions_viewer,
    impacts_registered_repository,
  }
}

///|
test "items in a registered repository are relevant" {
  let registered = RepositoryRef::new("acme", "desktop")
  let reason = classify_relevance([registered], [], candidate(registered))
  assert_true(reason is Some(RelevanceReason::RegisteredRepository(_)))
}

///|
test "mentions are relevant in any repository" {
  let external = RepositoryRef::new("external", "project")
  let reason = classify_relevance(
    [],
    [],
    candidate(external, mentions_viewer=true),
  )
  assert_true(reason is Some(RelevanceReason::ViewerMention))
}

///|
test "dependency activity requires an impact signal" {
  let registered = RepositoryRef::new("acme", "desktop")
  let dependency = RepositoryRef::new("vendor", "renderer")
  let edges = [DependencyEdge::new(registered, dependency)]
  let unrelated = classify_relevance([registered], edges, candidate(dependency))
  assert_true(unrelated is None)

  let relevant = classify_relevance(
    [registered],
    edges,
    candidate(dependency, impacts_registered_repository=true),
  )
  assert_true(relevant is Some(RelevanceReason::DependencyImpact(_, _)))
}
