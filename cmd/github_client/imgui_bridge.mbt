///|
#borrow(window)
extern "C" fn github_client_imgui_init(window : @glfw.GLFWwindow) -> Int = "github_client_imgui_init"

///|
#borrow(window, repositories, suggested_repositories, pull_requests, issues, personal_activity, sync_status)
extern "C" fn github_client_imgui_render(
  window : @glfw.GLFWwindow,
  page : Int,
  sign_in_requests : Int,
  repository_count : Int,
  has_saved_token : Int,
  repositories : String,
  suggested_repositories : String,
  pull_requests : String,
  issues : String,
  personal_activity : String,
  sync_status : String,
) -> Int = "github_client_imgui_render"

///|
extern "C" fn github_client_imgui_take_repository() -> String = "github_client_imgui_take_repository"

///|
extern "C" fn github_client_imgui_take_token() -> String = "github_client_imgui_take_token"

///|
extern "C" fn github_client_imgui_take_url() -> String = "github_client_imgui_take_url"

///|
extern "C" fn github_client_imgui_take_activity_updated_at() -> String = "github_client_imgui_take_activity_updated_at"

///|
extern "C" fn github_client_imgui_take_selected_repository() -> String = "github_client_imgui_take_selected_repository"

///|
extern "C" fn github_client_imgui_shutdown() -> Unit = "github_client_imgui_shutdown"

///|
fn imgui_init(window : @glfw.GLFWwindow) -> Bool {
  github_client_imgui_init(window) != 0
}

///|
fn imgui_render(
  window : @glfw.GLFWwindow,
  page : Int,
  sign_in_requests : Int,
  repository_count : Int,
  has_saved_token : Bool,
  repositories : String,
  suggested_repositories : String,
  pull_requests : String,
  issues : String,
  personal_activity : String,
  sync_status : String,
) -> Int {
  github_client_imgui_render(
    window,
    page,
    sign_in_requests,
    repository_count,
    if has_saved_token {
      1
    } else {
      0
    },
    repositories,
    suggested_repositories,
    pull_requests,
    issues,
    personal_activity,
    sync_status,
  )
}

///|
fn imgui_take_repository() -> String {
  github_client_imgui_take_repository()
}

///|
fn imgui_take_token() -> String {
  github_client_imgui_take_token()
}

///|
fn imgui_take_url() -> String {
  github_client_imgui_take_url()
}

///|
fn imgui_take_activity_updated_at() -> String {
  github_client_imgui_take_activity_updated_at()
}

///|
fn imgui_take_selected_repository() -> String {
  github_client_imgui_take_selected_repository()
}

///|
fn imgui_shutdown() -> Unit {
  github_client_imgui_shutdown()
}
