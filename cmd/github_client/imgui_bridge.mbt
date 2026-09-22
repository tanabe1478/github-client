///|
#borrow(window)
extern "C" fn github_client_imgui_init(window : @glfw.GLFWwindow) -> Int = "github_client_imgui_init"

///|
#borrow(window)
extern "C" fn github_client_imgui_render(
  window : @glfw.GLFWwindow,
  page : Int,
  sign_in_requests : Int,
) -> Int = "github_client_imgui_render"

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
) -> Int {
  github_client_imgui_render(window, page, sign_in_requests)
}

///|
fn imgui_shutdown() -> Unit {
  github_client_imgui_shutdown()
}
