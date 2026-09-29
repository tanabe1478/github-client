///|
#borrow(window)
extern "C" fn github_client_imgui_init(window : @glfw.GLFWwindow) -> Int = "github_client_imgui_init"

///|
#borrow(window, nav, header, rows, repositories, suggestions, credentials, banners, loading, snackbar, alert, token, page_error)
extern "C" fn github_client_imgui_render(
  window : @glfw.GLFWwindow,
  page : Int,
  busy : Int,
  progress_done : Int,
  progress_total : Int,
  flags : Int,
  nav : String,
  header : String,
  rows : String,
  repositories : String,
  suggestions : String,
  credentials : String,
  banners : String,
  loading : String,
  snackbar : String,
  alert : String,
  token : String,
  page_error : String,
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
extern "C" fn github_client_imgui_take_key() -> String = "github_client_imgui_take_key"

///|
extern "C" fn github_client_imgui_view_kind() -> Int = "github_client_imgui_view_kind"

///|
extern "C" fn github_client_imgui_view_repository() -> String = "github_client_imgui_view_repository"

///|
extern "C" fn github_client_imgui_view_query() -> String = "github_client_imgui_view_query"

///|
extern "C" fn github_client_imgui_view_reason() -> String = "github_client_imgui_view_reason"

///|
extern "C" fn github_client_imgui_view_show_done() -> Int = "github_client_imgui_view_show_done"

///|
extern "C" fn github_client_imgui_auto_refresh_enabled() -> Int = "github_client_imgui_auto_refresh_enabled"

///|
extern "C" fn github_client_imgui_set_show_done(value : Int) -> Unit = "github_client_imgui_set_show_done"

///|
extern "C" fn github_client_imgui_set_view_kind(value : Int) -> Unit = "github_client_imgui_set_view_kind"

///|
#borrow(value)
extern "C" fn github_client_imgui_set_view_repository(value : String) -> Unit = "github_client_imgui_set_view_repository"

///|
#borrow(value)
extern "C" fn github_client_imgui_set_view_query(value : String) -> Unit = "github_client_imgui_set_view_query"

///|
#borrow(value)
extern "C" fn github_client_imgui_set_view_reason(value : String) -> Unit = "github_client_imgui_set_view_reason"

///|
#borrow(url, repository)
extern "C" fn github_client_imgui_open_row_menu(
  url : String,
  repository : String,
) -> Unit = "github_client_imgui_open_row_menu"

///|
#borrow(url, updated_at, repository, key)
extern "C" fn github_client_imgui_stage(
  url : String,
  updated_at : String,
  repository : String,
  key : String,
) -> Unit = "github_client_imgui_stage"

///|
extern "C" fn github_client_imgui_format_clock(epoch_seconds : Int64) -> String = "github_client_imgui_format_clock"

///|
extern "C" fn github_client_imgui_shutdown() -> Unit = "github_client_imgui_shutdown"

///|
extern "C" fn github_client_imgui_now() -> Double = "github_client_imgui_now"

///|
extern "C" fn github_client_imgui_exit(code : Int) -> Unit = "github_client_imgui_exit"

///|
extern "C" fn github_client_imgui_clock() -> Double = "github_client_imgui_clock"

///|
fn imgui_init(window : @glfw.GLFWwindow) -> Bool {
  github_client_imgui_init(window) != 0
}

///|
fn imgui_now() -> Double {
  github_client_imgui_now()
}

///|
fn imgui_auto_refresh_enabled() -> Bool {
  github_client_imgui_auto_refresh_enabled() != 0
}

///|
/// Filters chosen in the toolbar, read from the bridge every frame.
fn imgui_view_filter() -> @domain.ActivityFilter {
  {
    kind: match github_client_imgui_view_kind() {
      1 => PullRequestsOnly
      2 => IssuesOnly
      _ => AllKinds
    },
    repository: github_client_imgui_view_repository(),
    query: github_client_imgui_view_query(),
    reason: github_client_imgui_view_reason(),
    show_done: github_client_imgui_view_show_done() != 0,
  }
}
