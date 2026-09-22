///|
pub(all) enum Page {
  Inbox
  Repositories
  PullRequests
  Issues
  Settings
  ForYou
}

///|
pub(all) enum Msg {
  Navigate(Page)
  RequestSignIn
  RegisterRepository(RepositoryRef)
  RemoveRepository(String)
}

///|
pub struct Model {
  page : Page
  sign_in_requests : Int
  repositories : Array[RepositoryRef]
}

///|
pub fn Model::new() -> Model {
  { page: Inbox, sign_in_requests: 0, repositories: [], }
}

///|
pub fn Model::page(self : Model) -> Page {
  self.page
}

///|
pub fn Model::sign_in_requests(self : Model) -> Int {
  self.sign_in_requests
}

///|
pub fn Model::repositories(self : Model) -> Array[RepositoryRef] {
  self.repositories.copy()
}

///|
pub fn update(model : Model, msg : Msg) -> Model {
  match msg {
    Navigate(page) =>
      {
        page,
        sign_in_requests: model.sign_in_requests,
        repositories: model.repositories,
      }
    RequestSignIn =>
      {
        page: model.page,
        sign_in_requests: model.sign_in_requests + 1,
        repositories: model.repositories,
      }
    RegisterRepository(repository) => {
      let repositories = model.repositories.copy()
      if !repositories.any(item => item.key() == repository.key()) {
        repositories.push(repository)
      }
      {
        page: model.page,
        sign_in_requests: model.sign_in_requests,
        repositories,
      }
    }
    RemoveRepository(key) => {
      let repositories : Array[RepositoryRef] = []
      for repository in model.repositories {
        if repository.key() != key {
          repositories.push(repository)
        }
      }
      {
        page: model.page,
        sign_in_requests: model.sign_in_requests,
        repositories,
      }
    }
  }
}

///|
pub fn Page::code(self : Page) -> Int {
  match self {
    Inbox => 0
    Repositories => 1
    PullRequests => 2
    Issues => 3
    Settings => 4
    ForYou => 5
  }
}

///|
pub fn Page::name(self : Page) -> String {
  match self {
    Inbox => "Inbox"
    Repositories => "Repositories"
    PullRequests => "PullRequests"
    Issues => "Issues"
    Settings => "Settings"
    ForYou => "ForYou"
  }
}
