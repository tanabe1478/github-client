///|
fn main {
  println("github-client: starting GLFW + Dear ImGui host")
  if !@glfw.glfw_init() {
    println("github-client: GLFW initialization failed")
    return
  }

  let window = @glfw.create_opengl_window(1100, 720, "MoonBit GitHub Client")
  @glfw.make_context_current(window)
  @glfw.set_swap_interval(true)
  if !imgui_init(window) {
    println("github-client: Dear ImGui initialization failed")
    @glfw.destroy_window(window)
    @glfw.terminate()
    return
  }

  let mut counter = 0
  while !@glfw.window_should_close(window) {
    @glfw.poll_events()
    if imgui_render(window, counter) {
      counter += 1
    }
    @glfw.swap_buffers(window)
  }

  imgui_shutdown()
  @glfw.destroy_window(window)
  @glfw.terminate()
  println("github-client: stopped")
}
