///|
fn safe_row_text(value : String) -> String {
  value
  .replace_all(old="\r", new=" ")
  .replace_all(old="\n", new=" ")
  .replace_all(old="\t", new=" ")
}

///|
fn repository_rows(repositories : Array[@domain.RepositoryRef]) -> String {
  repositories.map(repository => repository.key()).join("\n")
}

///|
fn suggested_repository_rows(
  repositories : Array[@github_api.RepositorySummary],
) -> String {
  repositories
  .map(repository => {
    let visibility = if repository.is_private() { "Private" } else { "Public" }
    let archived = if repository.is_archived() { " · Archived" } else { "" }
    "\{repository.full_name()}  · \{visibility}\{archived}\t\{repository.full_name()}"
  })
  .join("\n")
}

///|
fn activity_rows(activities : Array[@github_api.ActivitySummary]) -> String {
  activities
  .map(activity => {
    let draft = if activity.is_draft() { " [draft]" } else { "" }
    let label = safe_row_text(
      "\{activity.repository()} #\{activity.number()}\{draft}  \{activity.title()}  · @\{activity.author()}",
    )
    "\{label}\t\{activity.html_url()}"
  })
  .join("\n")
}

///|
async fn fetch_repository_activity(
  token : String,
  repository : @domain.RepositoryRef,
  pull_requests : Array[@github_api.ActivitySummary],
  issues : Array[@github_api.ActivitySummary],
) -> String? {
  let errors : Array[String] = []
  match
    @github_api.list_open_pull_requests(
      token,
      repository.owner(),
      repository.name(),
    ) {
    Ok(items) => {
      println(
        "github-activity: \{repository.key()} pull-requests=\{items.length()}",
      )
      pull_requests.append(items)
    }
    Err(error) => errors.push("pull requests: \{error}")
  }
  match
    @github_api.list_open_issues(token, repository.owner(), repository.name()) {
    Ok(items) => {
      println("github-activity: \{repository.key()} issues=\{items.length()}")
      issues.append(items)
    }
    Err(error) => errors.push("issues: \{error}")
  }
  if errors.is_empty() {
    None
  } else {
    Some("\{repository.key()}: \{errors.join(", ")}")
  }
}

///|
async fn main {
  println("github-client: starting GLFW + Dear ImGui host")
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
  let pull_requests : Array[@github_api.ActivitySummary] = []
  let issues : Array[@github_api.ActivitySummary] = []
  let suggested_repositories : Array[@github_api.RepositorySummary] = []
  let mut authenticated_login = ""
  let mut saved_token : String? = None
  let mut sync_status = "Add a token to load GitHub activity."
  match @credential_store.load_token() {
    Ok(Some(token)) =>
      match @github_api.get_authenticated_user(token) {
        Ok(user) => {
          authenticated_login = user.login()
          saved_token = Some(token)
          sync_status = "Connected as @\{authenticated_login}."
          println("github-authenticated: \{authenticated_login}")
          match @github_api.list_owned_repositories(token) {
            Ok(repositories) => {
              println(
                "github-repositories: suggestions=\{repositories.length()}",
              )
              suggested_repositories.append(repositories)
            }
            Err(error) => {
              sync_status = "Repository suggestions: \{error}"
              println("github-repositories: \{error}")
            }
          }
          for repository in model.repositories() {
            match
              fetch_repository_activity(
                token, repository, pull_requests, issues,
              ) {
              Some(error) => {
                sync_status = error
                println("github-activity: \{error}")
              }
              None => ()
            }
          }
        }
        Err(error) => {
          sync_status = error
          println("github-authentication: \{error}")
        }
      }
    Ok(None) => ()
    Err(error) => {
      sync_status = error
      println("credential-store: load failed: \{error}")
    }
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

  let mut has_saved_token = @credential_store.has_saved_token()
  while !@glfw.window_should_close(window) {
    @glfw.poll_events()
    let action = imgui_render(
      window,
      model.page().code(),
      model.sign_in_requests(),
      model.repositories().length(),
      has_saved_token,
      repository_rows(model.repositories()),
      suggested_repository_rows(suggested_repositories),
      activity_rows(pull_requests),
      activity_rows(issues),
      sync_status,
    )
    match action {
      1 => {
        model = @domain.update(model, @domain.Msg::RequestSignIn)
        println("ui-action: auth.sign-in count=\{model.sign_in_requests()}")
      }
      2 =>
        match @domain.RepositoryRef::parse(imgui_take_repository()) {
          Ok(repository) => {
            let previous_count = model.repositories().length()
            model = @domain.update(
              model,
              @domain.Msg::RegisterRepository(repository),
            )
            match @repository_store.save_default(model.repositories()) {
              Ok(_) => println("ui-action: repository.register")
              Err(error) => println("repository-store: save failed: \{error}")
            }
            if model.repositories().length() > previous_count {
              match saved_token {
                Some(token) =>
                  match
                    fetch_repository_activity(
                      token, repository, pull_requests, issues,
                    ) {
                    Some(error) => sync_status = error
                    None => sync_status = "Repository activity loaded."
                  }
                None =>
                  sync_status = "Repository saved. Add a token to load activity."
              }
            } else {
              sync_status = "Repository is already registered."
            }
          }
          Err(error) => println("repository-register: \{error}")
        }
      3 => {
        let token = imgui_take_token()
        match @credential_store.save_token(token) {
          Ok(_) => {
            has_saved_token = true
            match @github_api.get_authenticated_user(token) {
              Ok(user) => {
                saved_token = Some(token)
                authenticated_login = user.login()
                sync_status = "Connected as @\{authenticated_login}."
                pull_requests.clear()
                issues.clear()
                suggested_repositories.clear()
                match @github_api.list_owned_repositories(token) {
                  Ok(repositories) => {
                    println(
                      "github-repositories: suggestions=\{repositories.length()}",
                    )
                    suggested_repositories.append(repositories)
                  }
                  Err(error) => sync_status = "Repository suggestions: \{error}"
                }
                for repository in model.repositories() {
                  match
                    fetch_repository_activity(
                      token, repository, pull_requests, issues,
                    ) {
                    Some(error) => sync_status = error
                    None => ()
                  }
                }
                println("ui-action: auth.pat-saved")
              }
              Err(error) => {
                sync_status = error
                println("github-authentication: \{error}")
              }
            }
          }
          Err(error) => {
            sync_status = error
            println("credential-store: save failed: \{error}")
          }
        }
      }
      4 =>
        match @shell.open(imgui_take_url()) {
          Ok(_) => println("ui-action: activity.open")
          Err(error) => println("shell: open failed: \{error}")
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
      14 => {
        model = @domain.update(
          model,
          @domain.Msg::Navigate(@domain.Page::Settings),
        )
        println("ui-action: nav.settings")
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
