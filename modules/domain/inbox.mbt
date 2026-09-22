///|
pub(all) struct RepositoryRef {
  owner : String
  name : String
}

///|
pub fn RepositoryRef::new(owner : String, name : String) -> RepositoryRef {
  { owner, name, }
}

///|
pub fn RepositoryRef::owner(self : RepositoryRef) -> String {
  self.owner
}

///|
pub fn RepositoryRef::name(self : RepositoryRef) -> String {
  self.name
}

///|
pub fn RepositoryRef::key(self : RepositoryRef) -> String {
  "\{self.owner}/\{self.name}"
}

///|
pub fn RepositoryRef::parse(value : String) -> Result[RepositoryRef, String] {
  let parts = value.trim().split("/").to_array()
  guard parts.length() == 2 && parts[0] != "" && parts[1] != "" else {
    return Err("repository must use owner/name format")
  }
  Ok({ owner: parts[0].to_owned(), name: parts[1].to_owned(), })
}

///|
pub(all) struct DependencyEdge {
  registered : RepositoryRef
  dependency : RepositoryRef
}

///|
pub fn DependencyEdge::new(
  registered : RepositoryRef,
  dependency : RepositoryRef,
) -> DependencyEdge {
  { registered, dependency, }
}

///|
pub(all) enum InboxItemKind {
  PullRequest
  Issue
}

///|
pub(all) enum RelevanceReason {
  RegisteredRepository(RepositoryRef)
  ViewerMention
  DependencyImpact(RepositoryRef, RepositoryRef)
}

///|
pub(all) struct InboxCandidate {
  repository : RepositoryRef
  number : Int
  kind : InboxItemKind
  title : String
  mentions_viewer : Bool
  impacts_registered_repository : Bool
}

///|
pub fn classify_relevance(
  registered : Array[RepositoryRef],
  dependencies : Array[DependencyEdge],
  candidate : InboxCandidate,
) -> RelevanceReason? {
  if candidate.mentions_viewer {
    return Some(ViewerMention)
  }
  for repository in registered {
    if repository.key() == candidate.repository.key() {
      return Some(RegisteredRepository(repository))
    }
  }
  if candidate.impacts_registered_repository {
    for edge in dependencies {
      if edge.dependency.key() == candidate.repository.key() {
        return Some(DependencyImpact(edge.registered, edge.dependency))
      }
    }
  }
  None
}
