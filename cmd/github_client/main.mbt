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

  let mut model = @domain.Model::new()
  match @repository_store.load_default() {
    Ok(repositories) =>
      for repository in repositories {
        model = @domain.update(
          model,
          @domain.Msg::RegisterRepository(repository),
        )
      }
    Err(error) => println("repository-store: load failed: \{error}")
  }
  while !@glfw.window_should_close(window) {
    @glfw.poll_events()
    let action = imgui_render(
      window,
      model.page().code(),
      model.sign_in_requests(),
      model.repositories().length(),
    )
    match action {
      1 => {
        model = @domain.update(model, @domain.Msg::RequestSignIn)
        println("ui-action: auth.sign-in count=\{model.sign_in_requests()}")
      }
      2 =>
        match @domain.RepositoryRef::parse(imgui_take_repository()) {
          Ok(repository) => {
            model = @domain.update(
              model,
              @domain.Msg::RegisterRepository(repository),
            )
            match @repository_store.save_default(model.repositories()) {
              Ok(_) => println("ui-action: repository.register")
              Err(error) => println("repository-store: save failed: \{error}")
            }
          }
          Err(error) => println("repository-register: \{error}")
        }
      10 => {
        model = @domain.update(
          model,
          @domain.Msg::Navigate(@domain.Page::Inbox),
        )
        println("ui-action: nav.inbox")
      }
      11 => {
        model = @domain.update(
          model,
          @domain.Msg::Navigate(@domain.Page::Repositories),
        )
        println("ui-action: nav.repositories")
      }
      12 => {
        model = @domain.update(
          model,
          @domain.Msg::Navigate(@domain.Page::PullRequests),
        )
        println("ui-action: nav.pull-requests")
      }
      13 => {
        model = @domain.update(
          model,
          @domain.Msg::Navigate(@domain.Page::Issues),
        )
        println("ui-action: nav.issues")
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
