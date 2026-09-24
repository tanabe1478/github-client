///|
#borrow(window)
extern "C" fn github_client_imgui_init(window : @glfw.GLFWwindow) -> Int = "github_client_imgui_init"

///|
#borrow(window, repositories, suggested_repositories, pull_requests, issues, personal_activity, saved_activity, credentials, sync_status)
extern "C" fn github_client_imgui_render(
  window : @glfw.GLFWwindow,
  page : Int,
  sign_in_requests : Int,
  repository_count : Int,
  credential_count : Int,
  repositories : String,
  suggested_repositories : String,
  pull_requests : String,
  issues : String,
  personal_activity : String,
  saved_activity : String,
  credentials : String,
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
extern "C" fn github_client_imgui_take_credential_scope() -> String = "github_client_imgui_take_credential_scope"

///|
extern "C" fn github_client_imgui_take_selected_credential() -> String = "github_client_imgui_take_selected_credential"

///|
extern "C" fn github_client_imgui_shutdown() -> Unit = "github_client_imgui_shutdown"

///|
extern "C" fn github_client_imgui_now() -> Double = "github_client_imgui_now"

///|
extern "C" fn github_client_imgui_auto_refresh_enabled() -> Int = "github_client_imgui_auto_refresh_enabled"

///|
#borrow(url, updated_at, repository)
extern "C" fn github_client_imgui_stage(
  url : String,
  updated_at : String,
  repository : String,
) -> Unit = "github_client_imgui_stage"

///|
extern "C" fn github_client_imgui_set_show_done(value : Int) -> Unit = "github_client_imgui_set_show_done"

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
  credential_count : Int,
  repositories : String,
  suggested_repositories : String,
  pull_requests : String,
  issues : String,
  personal_activity : String,
  saved_activity : String,
  credentials : String,
  sync_status : String,
) -> Int {
  github_client_imgui_render(
    window, page, sign_in_requests, repository_count, credential_count, repositories,
    suggested_repositories, pull_requests, issues, personal_activity, saved_activity,
    credentials, sync_status,
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
fn imgui_take_credential_scope() -> String {
  github_client_imgui_take_credential_scope()
}

///|
fn imgui_take_selected_credential() -> String {
  github_client_imgui_take_selected_credential()
}

///|
fn imgui_shutdown() -> Unit {
  github_client_imgui_shutdown()
}

///|
fn imgui_now() -> Double {
  github_client_imgui_now()
}

///|
fn imgui_auto_refresh_enabled() -> Bool {
  github_client_imgui_auto_refresh_enabled() != 0
}
