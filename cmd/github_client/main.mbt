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

  let mut model = @app.Model::new()
  while !@glfw.window_should_close(window) {
    @glfw.poll_events()
    let action = imgui_render(
      window,
      model.page().code(),
      model.sign_in_requests(),
    )
    match action {
      1 => {
        model = @app.update(model, @app.Msg::RequestSignIn)
        println("ui-action: auth.sign-in count=\{model.sign_in_requests()}")
      }
      10 => {
        model = @app.update(model, @app.Msg::Navigate(@app.Page::Repositories))
        println("ui-action: nav.repositories")
      }
      11 => {
        model = @app.update(model, @app.Msg::Navigate(@app.Page::PullRequests))
        println("ui-action: nav.pull-requests")
      }
      12 => {
        model = @app.update(model, @app.Msg::Navigate(@app.Page::Issues))
        println("ui-action: nav.issues")
      }
      13 => {
        model = @app.update(model, @app.Msg::Navigate(@app.Page::Actions))
        println("ui-action: nav.actions")
      }
      _ => ()
    }
    @glfw.swap_buffers(window)
  }

  imgui_shutdown()
  @glfw.destroy_window(window)
  @glfw.terminate()
  println("github-client: stopped")
}
