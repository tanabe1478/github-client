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
fn ascii_lower(value : String) -> String {
  let lowered = StringBuilder()
  for character in value {
    if character >= 'A' && character <= 'Z' {
      lowered.write_char((character.to_int() + 32).unsafe_to_char())
    } else {
      lowered.write_char(character)
    }
  }
  lowered.to_string()
}

///|
fn resolve_token(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  owner : String,
  name : String,
) -> String? {
  let owner_key = ascii_lower(owner)
  match tokens.get(owner_key) {
    Some(token) => Some(token)
    None =>
      match repo_scopes.get(ascii_lower("\{owner}/\{name}")) {
        Some(scope) => tokens.get(scope)
        None =>
          match owner_scopes.get(owner_key) {
            Some(scope) => tokens.get(scope)
            None => tokens.get("default")
          }
      }
  }
}

///|
fn credentials_text() -> String {
  @credential_store.list_scopes()
  .map(scope => {
    let login = @credential_store.load_login_label(scope).unwrap_or("")
    "\{scope}\t\{login}"
  })
  .join("\n")
}

///|
fn activity_row(
  activity : @github_api.ActivitySummary,
  label : String,
  read_markers : Array[@domain.ReadMarker],
  saved : Map[String, Bool],
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
  let saved_state = if saved.contains(activity.html_url()) {
    "saved"
  } else {
    ""
  }
  "\{safe_row_text(label)}\t\{activity.html_url()}\t\{read_state}\t\{activity.updated_at()}\t\{saved_state}"
}

///|
fn activity_label(activity : @github_api.ActivitySummary) -> String {
  let draft = if activity.is_draft() { " [draft]" } else { "" }
  "\{activity.repository()} #\{activity.number()}\{draft}  \{activity.title()}  · @\{activity.author()}"
}

///|
fn activity_rows(
  activities : Array[@github_api.ActivitySummary],
  read_markers : Array[@domain.ReadMarker],
  saved : Map[String, Bool],
  muted : Map[String, Bool],
) -> String {
  activities
  .filter(activity => !muted.contains(activity.html_url()))
  .map(activity => {
    activity_row(activity, activity_label(activity), read_markers, saved)
  })
  .join("\n")
}

///|
fn saved_activity_rows(
  read_markers : Array[@domain.ReadMarker],
  saved : Map[String, Bool],
  muted : Map[String, Bool],
  activity_sets : Array[Array[@github_api.ActivitySummary]],
) -> String {
  let seen : Map[String, Bool] = Map([])
  let rows : Array[String] = []
  for activities in activity_sets {
    for activity in activities {
      let url = activity.html_url()
      if saved.contains(url) && !muted.contains(url) && !seen.contains(url) {
        seen.set(url, true)
        rows.push(
          activity_row(activity, activity_label(activity), read_markers, saved),
        )
      }
    }
  }
  rows.join("\n")
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
  muted : Map[String, Bool],
) -> Unit {
  for activity in activities {
    if muted.contains(activity.html_url()) ||
      !@domain.repository_is_watched(
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
  saved : Map[String, Bool],
  muted : Map[String, Bool],
) -> String {
  let rows : Array[PersonalRow] = []
  let indices : Map[String, Int] = Map([])
  merge_personal_rows(
    rows, indices, review_requests, "Review requested", watched_repositories, muted,
  )
  merge_personal_rows(
    rows, indices, assignments, "Assigned", watched_repositories, muted,
  )
  merge_personal_rows(
    rows, indices, mentions, "Mentioned", watched_repositories, muted,
  )
  merge_personal_rows(
    rows, indices, subscriptions, "Subscribed", watched_repositories, muted,
  )
  rows
  .map(row => {
    let activity = row.activity
    let label = "[\{row.reasons.join(", ")}] \{activity.repository()} #\{activity.number()}  \{activity.title()}  · @\{activity.author()}"
    activity_row(activity, label, read_markers, saved)
  })
  .join("\n")
}

///|
fn append_unique_activities(
  dst : Array[@github_api.ActivitySummary],
  items : Array[@github_api.ActivitySummary],
) -> Unit {
  for item in items {
    let mut found = false
    for existing in dst {
      if existing.html_url() == item.html_url() {
        found = true
        break
      }
    }
    if !found {
      dst.push(item)
    }
  }
}

///|
fn applescript_escape(value : String) -> String {
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
async fn post_notification(title : String, body : String) -> Unit {
  let script = "display notification \"\{applescript_escape(body)}\" with title \"\{applescript_escape(title)}\" sound name \"Glass\""
  let status = @async_shell.Cmd::Cmd("osascript", ["-e", script]).status()
  if status != 0 {
    println("notification: osascript exited with \{status}")
  }
}

///|
fn record_seen_revisions(
  seen : Map[String, String],
  activity_sets : Array[Array[@github_api.ActivitySummary]],
) -> Unit {
  for activities in activity_sets {
    for activity in activities {
      seen.set(activity.html_url(), activity.updated_at())
    }
  }
}

///|
fn collect_fresh_labels(
  seen : Map[String, String],
  watched : Array[@domain.RepositoryRef],
  muted : Map[String, Bool],
  activity_sets : Array[Array[@github_api.ActivitySummary]],
  personal_sets : Array[Array[@github_api.ActivitySummary]],
) -> Array[String] {
  let fresh : Array[String] = []
  let fresh_urls : Map[String, Bool] = Map([])
  for activities in activity_sets {
    for activity in activities {
      let url = activity.html_url()
      if !muted.contains(url) &&
        !fresh_urls.contains(url) &&
        seen.get(url) != Some(activity.updated_at()) {
        fresh_urls.set(url, true)
        fresh.push(
          "\{activity.repository()} #\{activity.number()}  \{activity.title()}  · @\{activity.author()}",
        )
      }
    }
  }
  for activities in personal_sets {
    for activity in activities {
      let url = activity.html_url()
      if @domain.repository_is_watched(watched, activity.repository()) &&
        !muted.contains(url) &&
        !fresh_urls.contains(url) &&
        seen.get(url) != Some(activity.updated_at()) {
        fresh_urls.set(url, true)
        fresh.push(
          "\{activity.repository()} #\{activity.number()}  \{activity.title()}  · @\{activity.author()}",
        )
      }
    }
  }
  fresh
}

///|
fn persist_triage(
  saved : Map[String, Bool],
  muted : Map[String, Bool],
) -> Result[Unit, String] {
  let saved_list : Array[String] = []
  for url, _ in saved {
    saved_list.push(url)
  }
  let muted_list : Array[String] = []
  for url, _ in muted {
    muted_list.push(url)
  }
  @triage_store.save_default(
    @triage_store.TriageState::new(saved_list, muted_list),
  )
}

///|
struct ControlCommand {
  action : Int
  url : String
  updated_at : String
  repository : String
}

///|
fn control_command(action : Int) -> ControlCommand {
  { action, url: "", updated_at: "", repository: "", }
}

///|
fn find_activity_updated_at(
  url : String,
  activity_sets : Array[Array[@github_api.ActivitySummary]],
) -> String {
  for activities in activity_sets {
    for activity in activities {
      if activity.html_url() == url {
        return activity.updated_at()
      }
    }
  }
  ""
}

///|
fn poll_control_commands(
  control_path : String,
  queue : Array[ControlCommand],
  activity_sets : Array[Array[@github_api.ActivitySummary]],
) -> Unit {
  if !@fs.path_exists(control_path) {
    return
  }
  let source = @fs.read_file_to_string(control_path, encoding="utf8") catch {
    _ => return
  }
  @fs.remove_file(control_path) catch {
    _ => ()
  }
  for
    raw_line in source.replace_all(old="\r\n", new="\n").split("\n").to_array() {
    let line = raw_line.trim()
    if line == "" {
      continue
    }
    let parts = line.split(" ").to_array()
    match parts[0] {
      "open" =>
        if parts.length() > 1 {
          queue.push({ ..control_command(4), url: parts[1].to_owned(), })
        }
      "done" =>
        if parts.length() > 1 {
          let url = parts[1].to_owned()
          let updated_at = find_activity_updated_at(url, activity_sets)
          if updated_at == "" {
            println("control: done target not found: \{url}")
          } else {
            queue.push({ ..control_command(6), url, updated_at, })
          }
        }
      "save" =>
        if parts.length() > 1 {
          queue.push({ ..control_command(22), url: parts[1].to_owned(), })
        }
      "unsub" | "unsubscribe" =>
        if parts.length() > 1 {
          queue.push({ ..control_command(23), url: parts[1].to_owned(), })
        }
      "nav" =>
        if parts.length() > 1 {
          let action = match parts[1] {
            "inbox" => 10
            "repositories" => 11
            "pull-requests" => 12
            "issues" => 13
            "settings" => 14
            "for-you" => 15
            "saved" => 16
            _ => 0
          }
          if action != 0 {
            queue.push(control_command(action))
          }
        }
      "watch" =>
        if parts.length() > 1 {
          queue.push({ ..control_command(2), repository: parts[1].to_owned(), })
        }
      "refresh" => queue.push(control_command(20))
      "refresh-for-you" => queue.push(control_command(21))
      "show-done" =>
        github_client_imgui_set_show_done(
          if parts.length() > 1 && parts[1] == "0" {
            0
          } else {
            1
          },
        )
      "quit" => queue.push(control_command(99))
      _ => println("control: unknown command \{line}")
    }
  }
}

///|
async fn notify_fresh_activities(fresh : Array[String]) -> Unit {
  if fresh.is_empty() {
    return
  }
  if fresh.length() <= 3 {
    for body in fresh {
      post_notification("GitHub Client", body)
    }
  } else {
    post_notification(
      "GitHub Client",
      "\{fresh.length()} new activities in watched repositories",
    )
  }
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
      append_unique_activities(review_requests, items)
    }
    Err(error) => errors.push("review requests: \{error}")
  }
  match @github_api.search_assignments(token, login) {
    Ok(items) => {
      println("github-personal-activity: assignments=\{items.length()}")
      append_unique_activities(assignments, items)
    }
    Err(error) => errors.push("assignments: \{error}")
  }
  match @github_api.search_mentions(token, login) {
    Ok(items) => {
      println("github-personal-activity: mentions=\{items.length()}")
      append_unique_activities(mentions, items)
    }
    Err(error) => errors.push("mentions: \{error}")
  }
  match @github_api.list_subscribed_issues(token) {
    Ok(items) => {
      println("github-personal-activity: subscriptions=\{items.length()}")
      append_unique_activities(subscriptions, items)
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
async fn fetch_repository_suggestions(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  suggested_repositories : Array[@github_api.RepositorySummary],
) -> String? {
  repo_scopes.clear()
  owner_scopes.clear()
  let ordered_scopes : Array[String] = []
  for scope, _ in tokens {
    if scope != "default" {
      ordered_scopes.push(scope)
    }
  }
  ordered_scopes.sort()
  if tokens.contains("default") {
    ordered_scopes.insert(0, "default")
  }
  let seen : Map[String, Bool] = Map([])
  let mut last_error : String? = None
  for scope in ordered_scopes {
    guard tokens.get(scope) is Some(token) else { continue }
    match @github_api.list_accessible_repositories(token) {
      Ok(repositories) => {
        println(
          "github-repositories: scope=\{scope} suggestions=\{repositories.length()}",
        )
        for repository in repositories {
          let key = repository.full_name()
          let lowered_key = ascii_lower(key)
          if !repo_scopes.contains(lowered_key) {
            repo_scopes.set(lowered_key, scope)
          }
          match key.find("/") {
            Some(index) => {
              let owner_key = ascii_lower(key[:index].to_owned())
              if !owner_scopes.contains(owner_key) {
                owner_scopes.set(owner_key, scope)
              }
            }
            None => ()
          }
          if !seen.contains(key) {
            seen.set(key, true)
            suggested_repositories.push(repository)
          }
        }
      }
      Err(error) => {
        last_error = Some("\{scope}: \{error}")
        println("github-repositories: scope=\{scope} \{error}")
      }
    }
  }
  last_error
}

///|
async fn refresh_personal_activity(
  tokens : Map[String, String],
  review_requests : Array[@github_api.ActivitySummary],
  assignments : Array[@github_api.ActivitySummary],
  mentions : Array[@github_api.ActivitySummary],
  subscriptions : Array[@github_api.ActivitySummary],
) -> String? {
  if tokens.is_empty() {
    return Some("no token")
  }
  review_requests.clear()
  assignments.clear()
  mentions.clear()
  subscriptions.clear()
  let mut last_error : String? = None
  for scope, token in tokens {
    let login = match @credential_store.load_login_label(scope) {
      Some(login) => login
      None =>
        match @github_api.get_authenticated_user(token) {
          Ok(user) => {
            ignore(@credential_store.save_login_label(scope, user.login()))
            user.login()
          }
          Err(error) => {
            last_error = Some("\{scope}: \{error}")
            continue
          }
        }
    }
    match
      fetch_personal_activity(
        token, login, review_requests, assignments, mentions, subscriptions,
      ) {
      Some(error) => {
        last_error = Some("\{scope}: \{error}")
        println("github-personal-activity: scope=\{scope} \{error}")
      }
      None => ()
    }
  }
  last_error
}

///|
async fn fetch_repository_activity(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  repository : @domain.RepositoryRef,
  pull_requests : Array[@github_api.ActivitySummary],
  issues : Array[@github_api.ActivitySummary],
) -> String? {
  guard resolve_token(
      tokens,
      repo_scopes,
      owner_scopes,
      repository.owner(),
      repository.name(),
    )
    is Some(token) else {
    return Some("\{repository.key()}: no token for \{repository.owner()}")
  }
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
  let saved_urls : Map[String, Bool] = Map([])
  let muted_urls : Map[String, Bool] = Map([])
  match @triage_store.load_default() {
    Ok(state) => {
      for url in state.saved {
        saved_urls.set(url, true)
      }
      for url in state.muted {
        muted_urls.set(url, true)
      }
    }
    Err(error) => println("triage-store: load failed: \{error}")
  }
  let mut authenticated_login = ""
  let saved_tokens : Map[String, String] = Map([])
  let repo_scopes : Map[String, String] = Map([])
  let owner_scopes : Map[String, String] = Map([])
  let mut sync_status = "Add a token to load GitHub activity."
  for scope in @credential_store.list_scopes() {
    match @credential_store.load_token_for(scope) {
      Ok(Some(token)) => saved_tokens.set(scope, token)
      Ok(None) => ()
      Err(error) => println("credential-store: load \{scope} failed: \{error}")
    }
  }
  match saved_tokens.get("default") {
    Some(token) =>
      match @github_api.get_authenticated_user(token) {
        Ok(user) => {
          authenticated_login = user.login()
          sync_status = "Connected as @\{authenticated_login}."
          println("github-authenticated: \{authenticated_login}")
          if @credential_store.load_login_label("default") is None {
            ignore(
              @credential_store.save_login_label("default", authenticated_login),
            )
          }
        }
        Err(error) => {
          sync_status = error
          println("github-authentication: \{error}")
        }
      }
    None => ()
  }
  match
    fetch_repository_suggestions(
      saved_tokens, repo_scopes, owner_scopes, suggested_repositories,
    ) {
    Some(error) => {
      sync_status = "Repository suggestions: \{error}"
      println("github-repositories: \{error}")
    }
    None => ()
  }
  match
    refresh_personal_activity(
      saved_tokens, review_requests, assignments, mentions, subscriptions,
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
        saved_tokens, repo_scopes, owner_scopes, repository, pull_requests, issues,
      ) {
      Some(error) => {
        sync_status = error
        println("github-activity: \{error}")
      }
      None => ()
    }
  }
  let seen_revisions : Map[String, String] = Map([])
  let control_queue : Array[ControlCommand] = []
  let control_path = match @app_paths.data_file("control.txt") {
    Ok(path) => path
    Err(_) => ""
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

  let mut last_auto_refresh = imgui_now()
  let mut last_control_poll = imgui_now()
  while !@glfw.window_should_close(window) {
    @glfw.poll_events()
    let poll_now = imgui_now()
    if control_path != "" && poll_now - last_control_poll >= 0.5 {
      last_control_poll = poll_now
      poll_control_commands(control_path, control_queue, [
        pull_requests, issues, review_requests, assignments, mentions, subscriptions,
      ])
    }
    record_seen_revisions(seen_revisions, [
      pull_requests, issues, review_requests, assignments, mentions, subscriptions,
    ])
    let credential_count = @credential_store.list_scopes().length()
    let action = imgui_render(
      window,
      model.page().code(),
      model.sign_in_requests(),
      model.repositories().length(),
      credential_count,
      repository_rows(model.repositories()),
      suggested_repository_rows(suggested_repositories),
      activity_rows(pull_requests, read_markers, saved_urls, muted_urls),
      activity_rows(issues, read_markers, saved_urls, muted_urls),
      personal_activity_rows(
        review_requests,
        assignments,
        mentions,
        subscriptions,
        model.repositories(),
        read_markers,
        saved_urls,
        muted_urls,
      ),
      saved_activity_rows(read_markers, saved_urls, muted_urls, [
        pull_requests, issues, review_requests, assignments, mentions, subscriptions,
      ]),
      credentials_text(),
      sync_status,
    )
    let mut action = action
    if action == 0 && !control_queue.is_empty() {
      let command = control_queue.remove(0)
      if command.action == 99 {
        @glfw.set_window_should_close(window, true)
      } else {
        github_client_imgui_stage(
          command.url,
          command.updated_at,
          command.repository,
        )
        action = command.action
      }
    }
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
              if saved_tokens.is_empty() {
                sync_status = "Repository saved. Add a token to load activity."
              } else {
                match
                  fetch_repository_activity(
                    saved_tokens, repo_scopes, owner_scopes, repository, pull_requests,
                    issues,
                  ) {
                  Some(error) => sync_status = error
                  None => sync_status = "Repository activity loaded."
                }
                match
                  refresh_personal_activity(
                    saved_tokens, review_requests, assignments, mentions, subscriptions,
                  ) {
                  Some(error) => sync_status = error
                  None => ()
                }
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
        let scope_raw = imgui_take_credential_scope()
        let token = imgui_take_token()
        match @credential_store.normalize_scope(scope_raw) {
          Err(error) => {
            sync_status = error
            println("credential-scope: \{error}")
          }
          Ok(scope) =>
            match @credential_store.save_token_for(scope, token) {
              Ok(_) =>
                match @github_api.get_authenticated_user(token) {
                  Ok(user) => {
                    saved_tokens.set(scope, token)
                    match
                      @credential_store.save_login_label(scope, user.login()) {
                      Ok(_) => ()
                      Err(error) =>
                        println(
                          "credential-store: login label failed: \{error}",
                        )
                    }
                    sync_status = "Saved token for \{scope} (@\{user.login()})."
                    if scope == "default" {
                      authenticated_login = user.login()
                    }
                    suggested_repositories.clear()
                    match
                      fetch_repository_suggestions(
                        saved_tokens, repo_scopes, owner_scopes, suggested_repositories,
                      ) {
                      Some(error) =>
                        sync_status = "Repository suggestions: \{error}"
                      None => ()
                    }
                    match
                      refresh_personal_activity(
                        saved_tokens, review_requests, assignments, mentions, subscriptions,
                      ) {
                      Some(error) => sync_status = error
                      None => ()
                    }
                    pull_requests.clear()
                    issues.clear()
                    for repository in model.repositories() {
                      match
                        fetch_repository_activity(
                          saved_tokens, repo_scopes, owner_scopes, repository, pull_requests,
                          issues,
                        ) {
                        Some(error) => sync_status = error
                        None => ()
                      }
                    }
                    println("ui-action: auth.pat-saved scope=\{scope}")
                  }
                  Err(error) => {
                    sync_status = error
                    println("github-authentication: \{error}")
                  }
                }
              Err(error) => {
                sync_status = error
                println("credential-store: save failed: \{error}")
              }
            }
        }
      }
      4 => {
        let url = imgui_take_url()
        match @shell.open(url) {
          Ok(_) => println("ui-action: activity.open")
          Err(_) => {
            let status = @async_shell.Cmd::Cmd("open", [url]).status()
            if status == 0 {
              println("ui-action: activity.open")
            } else {
              sync_status = "Could not open the link."
              println("shell: open exited with \{status}")
            }
          }
        }
      }
      5 => {
        let repository = imgui_take_selected_repository()
        model = @domain.update(model, @domain.Msg::RemoveRepository(repository))
        pull_requests = without_repository(pull_requests, repository)
        issues = without_repository(issues, repository)
        match
          refresh_personal_activity(
            saved_tokens, review_requests, assignments, mentions, subscriptions,
          ) {
          Some(error) => sync_status = error
          None => ()
        }
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
          sync_status = "Moved back to inbox."
          println("ui-action: activity.restore")
        } else {
          read_markers = @domain.mark_activity_read(
            read_markers, url, updated_at,
          )
          sync_status = "Marked as done."
          println("ui-action: activity.done")
        }
        match @read_state_store.save_default(read_markers) {
          Ok(_) => ()
          Err(error) => {
            sync_status = error
            println("read-state-store: save failed: \{error}")
          }
        }
      }
      22 => {
        let url = imgui_take_url()
        if saved_urls.contains(url) {
          saved_urls.remove(url)
          sync_status = "Removed from Saved."
          println("ui-action: activity.unsave")
        } else {
          saved_urls.set(url, true)
          sync_status = "Saved for later."
          println("ui-action: activity.save")
        }
        match persist_triage(saved_urls, muted_urls) {
          Ok(_) => ()
          Err(error) => println("triage-store: save failed: \{error}")
        }
      }
      23 => {
        let url = imgui_take_url()
        muted_urls.set(url, true)
        match persist_triage(saved_urls, muted_urls) {
          Ok(_) => {
            sync_status = "Unsubscribed. The item is hidden and excluded from notifications."
            println("ui-action: activity.unsubscribe")
          }
          Err(error) => {
            sync_status = error
            println("triage-store: save failed: \{error}")
          }
        }
      }
      7 => {
        let scope = imgui_take_selected_credential()
        match @credential_store.delete_token_for(scope) {
          Ok(_) => {
            saved_tokens.remove(scope)
            if scope == "default" {
              authenticated_login = ""
            }
            suggested_repositories.clear()
            match
              fetch_repository_suggestions(
                saved_tokens, repo_scopes, owner_scopes, suggested_repositories,
              ) {
              Some(error) => sync_status = "Repository suggestions: \{error}"
              None => ()
            }
            match
              refresh_personal_activity(
                saved_tokens, review_requests, assignments, mentions, subscriptions,
              ) {
              Some(error) => sync_status = error
              None => ()
            }
            for repository in model.repositories() {
              pull_requests = without_repository(
                pull_requests,
                repository.key(),
              )
              issues = without_repository(issues, repository.key())
              match
                fetch_repository_activity(
                  saved_tokens, repo_scopes, owner_scopes, repository, pull_requests,
                  issues,
                ) {
                Some(error) => sync_status = error
                None => ()
              }
            }
            sync_status = "Removed credential for \{scope}."
            println("ui-action: credential.remove scope=\{scope}")
          }
          Err(error) => {
            sync_status = error
            println("credential-store: delete failed: \{error}")
          }
        }
      }
      20 => {
        pull_requests.clear()
        issues.clear()
        let mut refresh_error : String? = None
        for repository in model.repositories() {
          match
            fetch_repository_activity(
              saved_tokens, repo_scopes, owner_scopes, repository, pull_requests,
              issues,
            ) {
            Some(error) => refresh_error = Some(error)
            None => ()
          }
        }
        match refresh_error {
          Some(error) => sync_status = error
          None => sync_status = "Watched activity refreshed."
        }
        println("ui-action: refresh.watched")
      }
      21 =>
        if saved_tokens.is_empty() {
          sync_status = "Add a token to load personal activity."
        } else {
          match
            refresh_personal_activity(
              saved_tokens, review_requests, assignments, mentions, subscriptions,
            ) {
            Some(error) => sync_status = error
            None => sync_status = "For you refreshed."
          }
          println("ui-action: refresh.for-you")
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
      16 => {
        model = @domain.update(
          model,
          @domain.Msg::Navigate(@domain.Page::Saved),
        )
        println("ui-action: nav.saved")
      }
      _ => ()
    }
    if imgui_auto_refresh_enabled() && !saved_tokens.is_empty() {
      let now = imgui_now()
      if now - last_auto_refresh >= 300.0 {
        last_auto_refresh = now
        pull_requests.clear()
        issues.clear()
        let mut refresh_error : String? = None
        for repository in model.repositories() {
          match
            fetch_repository_activity(
              saved_tokens, repo_scopes, owner_scopes, repository, pull_requests,
              issues,
            ) {
            Some(error) => refresh_error = Some(error)
            None => ()
          }
        }
        match
          refresh_personal_activity(
            saved_tokens, review_requests, assignments, mentions, subscriptions,
          ) {
          Some(error) => refresh_error = Some(error)
          None => ()
        }
        let fresh = collect_fresh_labels(
          seen_revisions,
          model.repositories(),
          muted_urls,
          [pull_requests, issues],
          [review_requests, assignments, mentions, subscriptions],
        )
        match refresh_error {
          Some(error) => sync_status = error
          None => sync_status = "Auto refreshed."
        }
        println("auto-refresh: fresh=\{fresh.length()}")
        notify_fresh_activities(fresh)
      }
    }
    @glfw.swap_buffers(window)
  }

  imgui_shutdown()
  @glfw.destroy_window(window)
  @glfw.terminate()
  println("github-client: stopped")
}
