///|
pub(all) enum Page {
  Inbox
  Repositories
  PullRequests
  Issues
}

///|
pub(all) enum Msg {
  Navigate(Page)
  RequestSignIn
}

///|
pub struct Model {
  page : Page
  sign_in_requests : Int
}

///|
pub fn Model::new() -> Model {
  { page: Inbox, sign_in_requests: 0, }
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
pub fn update(model : Model, msg : Msg) -> Model {
  match msg {
    Navigate(page) => { page, sign_in_requests: model.sign_in_requests, }
    RequestSignIn =>
      { page: model.page, sign_in_requests: model.sign_in_requests + 1, }
  }
}

///|
pub fn Page::code(self : Page) -> Int {
  match self {
    Inbox => 0
    Repositories => 1
    PullRequests => 2
    Issues => 3
  }
}

///|
pub fn Page::name(self : Page) -> String {
  match self {
    Inbox => "Inbox"
    Repositories => "Repositories"
    PullRequests => "PullRequests"
    Issues => "Issues"
  }
}
