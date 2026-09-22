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
fn activity_row(
  activity : @github_api.ActivitySummary,
  label : String,
  read_markers : Array[@domain.ReadMarker],
) -> String {
  let read_state = if @domain.activity_is_read(
      read_markers,
      activity.html_url(),
      activity.updated_at(),
    ) {
    "read"
  } else {
    "unread"
  }
  "\{safe_row_text(label)}\t\{activity.html_url()}\t\{read_state}\t\{activity.updated_at()}"
}

///|
fn activity_rows(
  activities : Array[@github_api.ActivitySummary],
  read_markers : Array[@domain.ReadMarker],
) -> String {
  activities
  .map(activity => {
    let draft = if activity.is_draft() { " [draft]" } else { "" }
    let label = "\{activity.repository()} #\{activity.number()}\{draft}  \{activity.title()}  · @\{activity.author()}"
    activity_row(activity, label, read_markers)
  })
  .join("\n")
}

///|
struct PersonalRow {
  activity : @github_api.ActivitySummary
  reasons : Array[String]
}

///|
fn merge_personal_rows(
  rows : Array[PersonalRow],
  indices : Map[String, Int],
  activities : Array[@github_api.ActivitySummary],
  reason : String,
  watched_repositories : Array[@domain.RepositoryRef],
) -> Unit {
  for activity in activities {
    if !@domain.repository_is_watched(
        watched_repositories,
        activity.repository(),
      ) {
      continue
    }
    match indices.get(activity.html_url()) {
      Some(index) =>
        if !rows[index].reasons.contains(reason) {
          rows[index].reasons.push(reason)
        }
      None => {
        indices.set(activity.html_url(), rows.length())
        rows.push({ activity, reasons: [reason], })
      }
    }
  }
}

///|
fn personal_activity_rows(
  review_requests : Array[@github_api.ActivitySummary],
  assignments : Array[@github_api.ActivitySummary],
  mentions : Array[@github_api.ActivitySummary],
  subscriptions : Array[@github_api.ActivitySummary],
  watched_repositories : Array[@domain.RepositoryRef],
  read_markers : Array[@domain.ReadMarker],
) -> String {
  let rows : Array[PersonalRow] = []
  let indices : Map[String, Int] = Map([])
  merge_personal_rows(
    rows, indices, review_requests, "Review requested", watched_repositories,
  )
  merge_personal_rows(
    rows, indices, assignments, "Assigned", watched_repositories,
  )
  merge_personal_rows(
    rows, indices, mentions, "Mentioned", watched_repositories,
  )
  merge_personal_rows(
    rows, indices, subscriptions, "Subscribed", watched_repositories,
  )
  rows
  .map(row => {
    let activity = row.activity
    let label = "[\{row.reasons.join(", ")}] \{activity.repository()} #\{activity.number()}  \{activity.title()}  · @\{activity.author()}"
    activity_row(activity, label, read_markers)
  })
  .join("\n")
}

///|
async fn fetch_personal_activity(
  token : String,
  login : String,
  review_requests : Array[@github_api.ActivitySummary],
  assignments : Array[@github_api.ActivitySummary],
  mentions : Array[@github_api.ActivitySummary],
  subscriptions : Array[@github_api.ActivitySummary],
) -> String? {
  let errors : Array[String] = []
  match @github_api.search_review_requests(token, login) {
    Ok(items) => {
      println("github-personal-activity: review-requests=\{items.length()}")
      review_requests.append(items)
    }
    Err(error) => errors.push("review requests: \{error}")
  }
  match @github_api.search_assignments(token, login) {
    Ok(items) => {
      println("github-personal-activity: assignments=\{items.length()}")
      assignments.append(items)
    }
    Err(error) => errors.push("assignments: \{error}")
  }
  match @github_api.search_mentions(token, login) {
    Ok(items) => {
      println("github-personal-activity: mentions=\{items.length()}")
      mentions.append(items)
    }
    Err(error) => errors.push("mentions: \{error}")
  }
  match @github_api.list_subscribed_issues(token) {
    Ok(items) => {
      println("github-personal-activity: subscriptions=\{items.length()}")
      subscriptions.append(items)
    }
    Err(error) => errors.push("subscriptions: \{error}")
  }
  if errors.is_empty() {
    None
  } else {
    Some("For you: \{errors.join(", ")}")
  }
}

///|
fn without_repository(
  activities : Array[@github_api.ActivitySummary],
  repository : String,
) -> Array[@github_api.ActivitySummary] {
  let remaining : Array[@github_api.ActivitySummary] = []
  for activity in activities {
    if activity.repository() != repository {
      remaining.push(activity)
    }
  }
  remaining
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
  let mut pull_requests : Array[@github_api.ActivitySummary] = []
  let mut issues : Array[@github_api.ActivitySummary] = []
  let suggested_repositories : Array[@github_api.RepositorySummary] = []
  let review_requests : Array[@github_api.ActivitySummary] = []
  let assignments : Array[@github_api.ActivitySummary] = []
  let mentions : Array[@github_api.ActivitySummary] = []
  let subscriptions : Array[@github_api.ActivitySummary] = []
  let mut read_markers : Array[@domain.ReadMarker] = match
    @read_state_store.load_default() {
    Ok(markers) => markers
    Err(error) => {
      println("read-state-store: load failed: \{error}")
      []
    }
  }
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
          match
            fetch_personal_activity(
              token, authenticated_login, review_requests, assignments, mentions,
              subscriptions,
            ) {
            Some(error) => {
              sync_status = error
              println("github-personal-activity: \{error}")
            }
            None => ()
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
      activity_rows(pull_requests, read_markers),
      activity_rows(issues, read_markers),
      personal_activity_rows(
        review_requests,
        assignments,
        mentions,
        subscriptions,
        model.repositories(),
        read_markers,
      ),
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
          Err(error) => {
            sync_status = error
            println("repository-register: \{error}")
          }
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
                review_requests.clear()
                assignments.clear()
                mentions.clear()
                subscriptions.clear()
                match @github_api.list_owned_repositories(token) {
                  Ok(repositories) => {
                    println(
                      "github-repositories: suggestions=\{repositories.length()}",
                    )
                    suggested_repositories.append(repositories)
                  }
                  Err(error) => sync_status = "Repository suggestions: \{error}"
                }
                match
                  fetch_personal_activity(
                    token, authenticated_login, review_requests, assignments, mentions,
                    subscriptions,
                  ) {
                  Some(error) => sync_status = error
                  None => ()
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
      4 => {
        let url = imgui_take_url()
        let updated_at = imgui_take_activity_updated_at()
        if updated_at != "" {
          read_markers = @domain.mark_activity_read(
            read_markers, url, updated_at,
          )
          match @read_state_store.save_default(read_markers) {
            Ok(_) => ()
            Err(error) => println("read-state-store: save failed: \{error}")
          }
        }
        match @shell.open(url) {
          Ok(_) => println("ui-action: activity.open")
          Err(error) => println("shell: open failed: \{error}")
        }
      }
      5 => {
        let repository = imgui_take_selected_repository()
        model = @domain.update(model, @domain.Msg::RemoveRepository(repository))
        pull_requests = without_repository(pull_requests, repository)
        issues = without_repository(issues, repository)
        match @repository_store.save_default(model.repositories()) {
          Ok(_) => {
            sync_status = "Removed \{repository} from Watched repositories."
            println("ui-action: repository.remove")
          }
          Err(error) => {
            sync_status = error
            println("repository-store: save failed: \{error}")
          }
        }
      }
      6 => {
        let url = imgui_take_url()
        let updated_at = imgui_take_activity_updated_at()
        if @domain.activity_is_read(read_markers, url, updated_at) {
          read_markers = @domain.mark_activity_unread(read_markers, url)
          sync_status = "Activity marked unread."
          println("ui-action: activity.mark-unread")
        } else {
          read_markers = @domain.mark_activity_read(
            read_markers, url, updated_at,
          )
          sync_status = "Activity marked read."
          println("ui-action: activity.mark-read")
        }
        match @read_state_store.save_default(read_markers) {
          Ok(_) => ()
          Err(error) => {
            sync_status = error
            println("read-state-store: save failed: \{error}")
          }
        }
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
      15 => {
        model = @domain.update(
          model,
          @domain.Msg::Navigate(@domain.Page::ForYou),
        )
        println("ui-action: nav.for-you")
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
