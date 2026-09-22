///|
async fn main {
  println("github-client: starting GLFW + Dear ImGui host")
  let mut authenticated_login = ""
  match @credential_store.load_token() {
    Ok(Some(token)) =>
      match @github_api.get_authenticated_user(token) {
        Ok(user) => {
          authenticated_login = user.login()
          println("github-authenticated: \{authenticated_login}")
        }
        Err(error) => println("github-authentication: \{error}")
      }
    Ok(None) => ()
    Err(error) => println("credential-store: load failed: \{error}")
  }
  if !@glfw.glfw_init() {
    println("github-client: GLFW initialization failed")
    return
  }

  let window_title = if authenticated_login == "" {
    "MoonBit GitHub Client"
  } else {
    "MoonBit GitHub Client - @\{authenticated_login}"
  }
  let window = @glfw.create_opengl_window(1100, 720, window_title)
  @glfw.make_context_current(window)
  @glfw.set_swap_interval(true)
  if !imgui_init(window) {
    println("github-client: Dear ImGui initialization failed")
    @glfw.destroy_window(window)
    @glfw.terminate()
    return
  }

  let mut model = @domain.Model::new()
  let mut has_saved_token = @credential_store.has_saved_token()
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
      has_saved_token,
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
      3 =>
        match @credential_store.save_token(imgui_take_token()) {
          Ok(_) => {
            has_saved_token = true
            println("ui-action: auth.pat-saved")
          }
          Err(error) => println("credential-store: save failed: \{error}")
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
