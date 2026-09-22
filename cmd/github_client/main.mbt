///|
fn main {
  println("github-client: starting GLFW host")
  if !@glfw.glfw_init() {
    println("github-client: GLFW initialization failed")
    return
  }

  let window = @glfw.create_window(1100, 720, "MoonBit GitHub Client")
  while !@glfw.window_should_close(window) {
    @glfw.poll_events()
  }

  @glfw.destroy_window(window)
  @glfw.terminate()
  println("github-client: stopped")
}
