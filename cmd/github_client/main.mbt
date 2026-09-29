///|
/// GitHub fetches run as background tasks so the window keeps rendering.
/// Jobs run one at a time in request order.
priv enum FetchJob {
  Startup
  Watched
  Personal
  Everything
  AddedRepository(@domain.RepositoryRef)
  RemovedRepository
  VerifyToken(String, String)
  Credentials(String)
  Auto
  /// Watched repositories changed outside the app, for example by ghclient.
  External
}

///|
fn FetchJob::title(self : FetchJob) -> String {
  match self {
    Startup => "Loading your activity"
    Watched => "Refreshing watched activity"
    Personal => "Refreshing For you"
    Everything => "Refreshing activity"
    AddedRepository(repository) => "Loading \{repository.key()}"
    RemovedRepository => "Updating For you"
    VerifyToken(_, _) => "Verifying token"
    Credentials(_) => "Reloading activity"
    Auto => "Auto refreshing"
    External => "Updating watched repositories"
  }
}

///|
/// Fetches the user started block the window with the loading dialog.
/// Background work and token checks (shown in their own dialog) do not.
fn FetchJob::is_modal(self : FetchJob) -> Bool {
  !(self is (Auto | External | RemovedRepository | VerifyToken(_, _)))
}

///|
fn FetchJob::is_cancellable(self : FetchJob) -> Bool {
  self
  is (Watched | Personal | Everything | AddedRepository(_) | Credentials(_))
}

///|
fn FetchJob::success_message(self : FetchJob) -> String? {
  match self {
    Startup | RemovedRepository | VerifyToken(_, _) | Auto | External => None
    Watched => Some("Watched activity refreshed.")
    Personal => Some("For you refreshed.")
    Everything => Some("Activity refreshed.")
    AddedRepository(repository) => Some("Watching \{repository.key()}.")
    Credentials(message) => if message == "" { None } else { Some(message) }
  }
}

///|
priv enum UndoOp {
  /// Read markers to put back: URL and its previous read_at, if any.
  Restore(Array[(String, String?)])
  Unmute(String)
  ToggleSave(String)
  Rewatch(@domain.RepositoryRef)
}

///|
const FETCH_JOB_TIMEOUT_MS : Int = 90_000

///|
const AUTO_REFRESH_SECONDS : Double = 300.0

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
fn previous_read_at(
  markers : Array[@domain.ReadMarker],
  url : String,
) -> String? {
  for marker in markers {
    if marker.url() == url {
      return Some(marker.read_at())
    }
  }
  None
}

///|
fn applescript_escape(value : String) -> String {
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
async fn post_notification(
  title : String,
  subtitle : String,
  body : String,
) -> Unit {
  let script = "display notification \"\{applescript_escape(body)}\" with title \"\{applescript_escape(title)}\" subtitle \"\{applescript_escape(subtitle)}\" sound name \"Glass\""
  let status = @async_shell.Cmd::Cmd("osascript", ["-e", script]).status() catch {
    error => {
      println("notification: osascript failed: \{error}")
      return
    }
  }
  if status != 0 {
    println("notification: osascript exited with \{status}")
  }
}

///|
/// Up to three individual notifications, otherwise one summary grouped by
/// repository. `reason` is empty for watched activity.
async fn notify_fresh_activities(
  fresh : Array[(@github_api.ActivitySummary, String)],
) -> Unit {
  if fresh.is_empty() {
    return
  }
  if fresh.length() <= 3 {
    for entry in fresh {
      let (activity, reason) = entry
      let subtitle = "#\{activity.number()} \{activity.title()}"
      if reason == "" {
        post_notification(
          activity.repository(),
          subtitle,
          "by @\{activity.author()}",
        )
      } else {
        post_notification(reason, subtitle, activity.repository())
      }
    }
    return
  }
  let order : Array[String] = []
  let counts : Map[String, Int] = Map([])
  let mut dependency_updates = 0
  for entry in fresh {
    let repository = entry.0.repository()
    if !counts.contains(repository) {
      order.push(repository)
    }
    counts.set(repository, counts.get(repository).unwrap_or(0) + 1)
    if @domain.is_dependency_bot(entry.0.author()) {
      dependency_updates += 1
    }
  }
  let subtitle = order
    .map(repository => "\{repository} \{counts.get(repository).unwrap_or(0)}")
    .join(" · ")
  let body = if dependency_updates > 0 {
    "\{dependency_updates} are dependency updates"
  } else {
    "Open GitHub Client to review them."
  }
  post_notification(
    "\{fresh.length()} updates in watched repositories",
    subtitle,
    body,
  )
}

///|
async fn open_in_browser(url : String) -> Bool {
  match @shell.open(url) {
    Ok(_) => true
    Err(_) => {
      let status = @async_shell.Cmd::Cmd("open", [url]).status() catch {
        _ => return false
      }
      status == 0
    }
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
  let review_requests : Array[@github_api.ActivitySummary] = []
  let assignments : Array[@github_api.ActivitySummary] = []
  let mentions : Array[@github_api.ActivitySummary] = []
  let subscriptions : Array[@github_api.ActivitySummary] = []
  // Review requests GitHub dropped (usually after a teammate reviewed for
  // the team) that still wait for the viewer's own review.
  let kept_review_requests : Array[@github_api.ActivitySummary] = []
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
  // Problems from the last fetches, keyed by token scope or repository.
  let broken_scopes : Map[String, String] = Map([])
  let scope_failures : Map[String, String] = Map([])
  let repository_failures : Map[String, String] = Map([])
  // Lists that hit the page limit, so only their newest items are shown.
  let watched_incomplete : Map[String, Bool] = Map([])
  let personal_incomplete : Map[String, Bool] = Map([])
  for scope in @credential_store.list_scopes() {
    match @credential_store.load_token_for(scope) {
      Ok(Some(token)) => saved_tokens.set(scope, token)
      Ok(None) => ()
      Err(error) => {
        broken_scopes.set(
          scope, "Couldn't read this token from the Keychain. Add it again to keep loading its repositories.",
        )
        println("credential-store: load \{scope} failed: \{error}")
      }
    }
  }
  match saved_tokens.get("default") {
    Some(token) =>
      match @github_api.get_authenticated_user(token) {
        Ok(user) => {
          authenticated_login = user.login()
          println("github-authenticated: \{authenticated_login}")
          if @credential_store.load_login_label("default") is None {
            ignore(
              @credential_store.save_login_label("default", authenticated_login),
            )
          }
        }
        Err(error) => {
          scope_failures.set("default", error)
          println("github-authentication: \{error}")
        }
      }
    None => ()
  }
  let data_directory = @app_paths.data_directory().unwrap_or("")
  let seen_revisions : Map[String, String] = Map([])
  let fresh_since : Map[String, Double] = Map([])
  let expanded_bundles : Map[String, Bool] = Map([])
  let dismissed_banners : Map[String, Bool] = Map([])
  let control_queue : Array[ControlCommand] = []
  let control_path = @app_paths.data_file("control.txt").unwrap_or("")
  // Commands left from before this launch were meant for an earlier
  // instance; a stale `quit` would otherwise close this one at once.
  if control_path != "" && @fs.path_exists(control_path) {
    @fs.remove_file(control_path) catch {
      _ => ()
    }
    println("control: discarded commands left from before launch")
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
  let window = @glfw.create_opengl_window(1180, 780, window_title)
  @glfw.make_context_current(window)
  @glfw.set_swap_interval(true)
  if !imgui_init(window) {
    println("github-client: Dear ImGui initialization failed")
    @glfw.destroy_window(window)
    @glfw.terminate()
    return
  }

  let mut has_loaded = false
  let mut last_synced : Double? = None
  let mut snack_seq = 0
  let mut snack_message = ""
  let mut undo_op : UndoOp? = None
  let mut alert_seq = 0
  let mut alert_title = ""
  let mut alert_body = ""
  let mut token_state = 0
  let mut token_field = 0
  let mut token_message = ""
  let mut token_open_seq = 0
  let mut token_close_seq = 0
  let mut token_prefill = ""
  let mut auto_paused_until_ms = 0L
  let pending_jobs : Array[FetchJob] = []
  let mut running_job : FetchJob? = None
  let mut running_task : @async.Task[Unit]? = None
  // Each job gets a generation. A cancelled or timed-out job is abandoned
  // without waiting for it: some GitHub reads never return and ignore
  // cancellation, and their late results must not overwrite newer ones.
  let mut active_generation = 0
  let mut job_started_at = 0.0
  let mut live_tasks = 0
  let mut loading_detail = ""
  let mut loading_done = 0
  let mut loading_total = 0
  if !saved_tokens.is_empty() {
    pending_jobs.push(Startup)
  }

  fn notify(message : String, op : UndoOp?) -> Unit {
    snack_seq += 1
    snack_message = message
    undo_op = op
  }

  fn activity_label(url : String) -> String {
    match
      find_activity(url, [
        pull_requests, issues, review_requests, assignments, mentions, subscriptions,
      ]) {
      Some(activity) => "#\{activity.number()}"
      None => "the item"
    }
  }

  // ghclient and other tools edit the same files. The app remembers what
  // it last read or wrote and reloads a file whose contents changed.
  let read_state_path = @app_paths.data_file("read-state.txt").unwrap_or("")
  let triage_path = @app_paths.data_file("triage.txt").unwrap_or("")
  let repositories_path = @app_paths.data_file("repositories.txt").unwrap_or("")
  fn read_text(path : String) -> String {
    if path == "" || !@fs.path_exists(path) {
      return ""
    }
    @fs.read_file_to_string(path, encoding="utf8") catch {
      _ => ""
    }
  }

  let mut known_read_state = read_text(read_state_path)
  let mut known_triage = read_text(triage_path)
  let mut known_repositories = read_text(repositories_path)
  fn remember_files() -> Unit {
    known_read_state = read_text(read_state_path)
    known_triage = read_text(triage_path)
    known_repositories = read_text(repositories_path)
  }

  fn save_read_markers() -> Unit {
    match @read_state_store.save_default(read_markers) {
      Ok(_) => ()
      Err(error) => println("read-state-store: save failed: \{error}")
    }
    remember_files()
  }

  fn save_triage() -> Unit {
    match persist_triage(saved_urls, muted_urls) {
      Ok(_) => ()
      Err(error) => println("triage-store: save failed: \{error}")
    }
    remember_files()
  }

  // Rows that are new or changed since they were last on screen get a
  // short highlight. The first load highlights nothing.
  fn mark_fresh(sets : Array[Array[@github_api.ActivitySummary]]) -> Unit {
    if !has_loaded {
      return
    }
    let now = imgui_now()
    for activities in sets {
      for activity in activities {
        if seen_revisions.get(activity.html_url()) !=
          Some(activity.updated_at()) {
          fresh_since.set(activity.html_url(), now)
        }
      }
    }
  }

  // Each job fetches into fresh arrays and replaces the visible data only
  // after the fetch completes, so frames rendered meanwhile never show a
  // half-loaded list.
  async fn fetch_watched(
    next_pull_requests : Array[@github_api.ActivitySummary],
    next_issues : Array[@github_api.ActivitySummary],
  ) -> Unit {
    repository_failures.clear()
    watched_incomplete.clear()
    loading_detail = "Watched repositories"
    @activity_sync.fetch_watched_activity(
      saved_tokens,
      repo_scopes,
      owner_scopes,
      model.repositories(),
      next_pull_requests,
      next_issues,
      repository_failures,
      () => loading_done += 1,
      incomplete=watched_incomplete,
    )
  }

  fn commit_watched(
    generation : Int,
    next_pull_requests : Array[@github_api.ActivitySummary],
    next_issues : Array[@github_api.ActivitySummary],
  ) -> Unit {
    if generation != active_generation {
      return
    }
    mark_fresh([next_pull_requests, next_issues])
    // A repository removed while the fetch was running stays removed.
    let watched = model.repositories()
    @activity_sync.replace_activities(
      pull_requests,
      next_pull_requests.filter(activity => {
        @domain.repository_is_watched(watched, activity.repository())
      }),
    )
    @activity_sync.replace_activities(
      issues,
      next_issues.filter(activity => {
        @domain.repository_is_watched(watched, activity.repository())
      }),
    )
    has_loaded = true
    last_synced = Some(imgui_now())
  }

  // `next` holds review requests, assignments, mentions, subscriptions,
  // and kept review requests. Returns the review request URLs to remember.
  async fn fetch_personal(
    next : Array[Array[@github_api.ActivitySummary]],
  ) -> Array[String] {
    personal_incomplete.clear()
    @activity_sync.refresh_personal_activity(
      saved_tokens,
      next[0],
      next[1],
      next[2],
      next[3],
      scope_failures,
      _ => loading_detail = "For you and watched repositories",
      () => loading_done += 1,
      incomplete=personal_incomplete,
    )
    let follow_up = @activity_sync.follow_up_review_requests(
      saved_tokens,
      repo_scopes,
      owner_scopes,
      @review_request_store.load_default().unwrap_or([]),
      next[0],
      @activity_sync.saved_logins(),
    )
    next[4].append(follow_up.pending)
    follow_up.kept_urls
  }

  fn commit_personal(
    generation : Int,
    next : Array[Array[@github_api.ActivitySummary]],
    kept_urls : Array[String],
  ) -> Unit {
    if generation != active_generation {
      return
    }
    mark_fresh(next)
    @activity_sync.replace_activities(review_requests, next[0])
    @activity_sync.replace_activities(assignments, next[1])
    @activity_sync.replace_activities(mentions, next[2])
    @activity_sync.replace_activities(subscriptions, next[3])
    @activity_sync.replace_activities(kept_review_requests, next[4])
    match @review_request_store.save_default(kept_urls) {
      Ok(_) => ()
      Err(error) => println("review-request-store: save failed: \{error}")
    }
    last_synced = Some(imgui_now())
  }

  async fn load_personal(generation : Int) -> Unit {
    let next = [[], [], [], [], []]
    let kept_urls = fetch_personal(next)
    commit_personal(generation, next, kept_urls)
  }

  async fn load_watched(generation : Int) -> Unit {
    let next_pull_requests = []
    let next_issues = []
    fetch_watched(next_pull_requests, next_issues)
    commit_watched(generation, next_pull_requests, next_issues)
  }

  async fn load_suggestions_then_watched(generation : Int) -> Unit {
    let next_suggestions = []
    let next_repo_scopes : Map[String, String] = Map([])
    let next_owner_scopes : Map[String, String] = Map([])
    @activity_sync.fetch_repository_suggestions(
      saved_tokens, next_repo_scopes, next_owner_scopes, next_suggestions, scope_failures,
    )
    if generation != active_generation {
      return
    }
    suggested_repositories.clear()
    suggested_repositories.append(next_suggestions)
    @activity_sync.replace_scopes(repo_scopes, next_repo_scopes)
    @activity_sync.replace_scopes(owner_scopes, next_owner_scopes)
    loading_done += 1
    load_watched(generation)
  }

  async fn load_everything(generation : Int) -> Unit {
    ignore(
      @async.all([
        async fn() { load_personal(generation) },
        async fn() { load_watched(generation) },
      ]),
    )
  }

  async fn reload_all(generation : Int) -> Unit {
    scope_failures.clear()
    loading_total = 1 + saved_tokens.length() + model.repositories().length()
    loading_done = 0
    loading_detail = "Accounts and repositories"
    // For you does not depend on the token assignment that suggestions
    // produce, so it runs alongside suggestions and watched repositories.
    ignore(
      @async.all([
        async fn() { load_suggestions_then_watched(generation) },
        async fn() { load_personal(generation) },
      ]),
    )
  }

  fn watch_repository(raw : String) -> Unit {
    match @domain.RepositoryRef::parse(raw) {
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
        remember_files()
        dismissed_banners.set("watch:\{repository.key()}", true)
        if model.repositories().length() == previous_count {
          notify("\{repository.key()} is already watched.", None)
        } else if saved_tokens.is_empty() {
          notify("Watching \{repository.key()}. Add a token to load it.", None)
        } else {
          pending_jobs.push(AddedRepository(repository))
        }
      }
      Err(error) => {
        notify("Enter a repository as owner/name.", None)
        println("repository-register: \{error}")
      }
    }
  }

  async fn run_job(job : FetchJob, generation : Int) -> Unit {
    loading_done = 0
    loading_total = 0
    match job {
      Startup | Credentials(_) => reload_all(generation)
      VerifyToken(scope, token) => {
        loading_detail = "Checking the token with GitHub"
        let verified = @github_api.get_authenticated_user(token)
        if generation != active_generation {
          return
        }
        match verified {
          Ok(user) =>
            match @credential_store.save_token_for(scope, token) {
              Ok(_) => {
                saved_tokens.set(scope, token)
                ignore(@credential_store.save_login_label(scope, user.login()))
                if scope == "default" {
                  authenticated_login = user.login()
                }
                broken_scopes.remove(scope)
                scope_failures.remove(scope)
                dismissed_banners.remove("token:\{scope}")
                token_state = 0
                token_close_seq += 1
                notify(
                  "Connected \{scope_label(scope)} as @\{user.login()}.",
                  None,
                )
                println("ui-action: auth.pat-saved scope=\{scope}")
                pending_jobs.push(Credentials(""))
              }
              Err(error) => {
                token_state = 2
                token_field = 1
                token_message = "The token could not be saved: \{error}"
              }
            }
          Err(error) => {
            token_state = 2
            token_field = 1
            token_message = if @github_api.classify_failure(error)
              is Unauthorized {
              "GitHub rejected this token. Check that it was copied completely and has not expired."
            } else {
              "Couldn't verify the token: \{error}"
            }
            println("github-authentication: \{error}")
          }
        }
      }
      Watched => {
        loading_total = model.repositories().length()
        load_watched(generation)
      }
      Personal => {
        loading_total = saved_tokens.length()
        scope_failures.clear()
        load_personal(generation)
      }
      Everything => {
        loading_total = saved_tokens.length() + model.repositories().length()
        scope_failures.clear()
        load_everything(generation)
      }
      RemovedRepository => load_personal(generation)
      External => {
        loading_total = saved_tokens.length() + model.repositories().length()
        load_everything(generation)
      }
      AddedRepository(repository) => {
        loading_total = 1 + saved_tokens.length()
        loading_detail = repository.key()
        let next_pull_requests = []
        let next_issues = []
        match
          @activity_sync.fetch_repository_activity(
            saved_tokens, repo_scopes, owner_scopes, repository, next_pull_requests,
            next_issues,
          ) {
          Some(error) => repository_failures.set(repository.key(), error)
          None => repository_failures.remove(repository.key())
        }
        loading_done += 1
        if generation != active_generation {
          return
        }
        if @domain.repository_is_watched(model.repositories(), repository.key()) {
          @activity_sync.replace_activities(
            pull_requests,
            @activity_sync.without_repository(pull_requests, repository.key()),
          )
          pull_requests.append(next_pull_requests)
          @activity_sync.replace_activities(
            issues,
            @activity_sync.without_repository(issues, repository.key()),
          )
          issues.append(next_issues)
        }
        load_personal(generation)
      }
      Auto => {
        loading_total = saved_tokens.length() + model.repositories().length()
        let next_pull_requests = []
        let next_issues = []
        let next_personal = [[], [], [], [], []]
        let mut kept_urls : Array[String] = []
        scope_failures.clear()
        ignore(
          @async.all([
            async fn() { fetch_watched(next_pull_requests, next_issues) },
            async fn() { kept_urls = fetch_personal(next_personal) },
          ]),
        )
        // Compare against the seen revisions before committing: every frame
        // records visible items as seen.
        let watched = model.repositories()
        let fresh : Array[(@github_api.ActivitySummary, String)] = []
        let fresh_urls : Map[String, Bool] = Map([])
        let reasons = [
          "Review requested", "Assigned", "Mentioned", "Subscribed", "Review requested",
        ]
        let candidates : Array[(@github_api.ActivitySummary, String)] = []
        for activity in next_pull_requests {
          candidates.push((activity, ""))
        }
        for activity in next_issues {
          candidates.push((activity, ""))
        }
        for index, activities in next_personal {
          for activity in activities {
            if @domain.repository_is_watched(watched, activity.repository()) {
              candidates.push((activity, reasons[index]))
            }
          }
        }
        for entry in candidates {
          let url = entry.0.html_url()
          if !muted_urls.contains(url) &&
            !fresh_urls.contains(url) &&
            seen_revisions.get(url) != Some(entry.0.updated_at()) {
            fresh_urls.set(url, true)
            fresh.push(entry)
          }
        }
        if generation != active_generation {
          return
        }
        commit_watched(generation, next_pull_requests, next_issues)
        commit_personal(generation, next_personal, kept_urls)
        println("auto-refresh: fresh=\{fresh.length()}")
        notify_fresh_activities(fresh)
      }
    }
  }

  fn apply_undo(op : UndoOp) -> Unit {
    match op {
      Restore(entries) => {
        for entry in entries {
          let (url, previous) = entry
          read_markers = match previous {
            Some(read_at) =>
              @domain.mark_activity_read(read_markers, url, read_at)
            None => @domain.mark_activity_unread(read_markers, url)
          }
        }
        save_read_markers()
      }
      Unmute(url) => {
        muted_urls.remove(url)
        save_triage()
      }
      ToggleSave(url) => {
        if saved_urls.contains(url) {
          saved_urls.remove(url)
        } else {
          saved_urls.set(url, true)
        }
        save_triage()
      }
      Rewatch(repository) => watch_repository(repository.key())
    }
    notify("Undone.", None)
    println("ui-action: undo")
  }

  fn job_timed_out(job : FetchJob) -> Unit {
    if job is VerifyToken(_, _) {
      token_state = 2
      token_field = 1
      token_message = "GitHub didn't respond in time. Try again."
    } else if job.is_modal() {
      alert_seq += 1
      alert_title = "\{job.title()} took too long"
      alert_body = "GitHub didn't finish responding within 90 seconds. The lists still show the results from the last successful refresh."
    } else {
      notify("\{job.title()} timed out.", None)
    }
  }

  // After a complete refresh, done and mute records for URLs that no list
  // holds any more (closed or out of scope) are removed so they do not pile
  // up. Saved URLs are always kept.
  fn prune_stale_records() -> Unit {
    let keep : Map[String, Bool] = Map([])
    for
      activities in [
        pull_requests, issues, review_requests, assignments, mentions, subscriptions,
        kept_review_requests,
      ] {
      for activity in activities {
        keep.set(activity.html_url(), true)
      }
    }
    for url, _ in saved_urls {
      keep.set(url, true)
    }
    let before_markers = read_markers.length()
    read_markers = @domain.prune_markers(read_markers, keep)
    let stale_muted : Array[String] = []
    for url, _ in muted_urls {
      if !keep.contains(url) {
        stale_muted.push(url)
      }
    }
    for url in stale_muted {
      muted_urls.remove(url)
    }
    if read_markers.length() != before_markers {
      save_read_markers()
    }
    if !stale_muted.is_empty() {
      save_triage()
    }
    println(
      "prune: markers \{before_markers} -> \{read_markers.length()}, muted -\{stale_muted.length()}",
    )
  }

  fn job_finished() -> Unit {
    // A rate limit pauses auto refresh until GitHub resets it.
    for failures in [scope_failures, repository_failures] {
      for _, message in failures {
        if @github_api.classify_failure(message) is RateLimited(epoch) {
          auto_paused_until_ms = epoch * 1000L
        }
      }
    }
    if !repository_failures.is_empty() || !scope_failures.is_empty() {
      // A new failure shows its banner again even if one was dismissed.
      dismissed_banners.clear()
    }
    running_job = None
    running_task = None
  }

  // Stops waiting for the running job. Its task is asked to cancel, but a
  // read stuck inside the HTTP client may keep running; its results are
  // ignored because the generation moves on.
  fn abandon_job() -> Unit {
    match running_task {
      Some(task) => task.cancel()
      None => ()
    }
    active_generation += 1
    running_job = None
    running_task = None
  }

  let mut last_auto_refresh = imgui_now()
  let mut last_control_poll = imgui_now()
  let mut last_file_poll = imgui_now()
  // GITHUB_CLIENT_PROFILE=1 logs the average time per frame spent building
  // rows (MoonBit) and rendering them (Dear ImGui), every 120 frames.
  let profiling = @sys.get_env_var("GITHUB_CLIENT_PROFILE") == Some("1")
  let mut profile_frames = 0
  let mut profile_build = 0.0
  let mut profile_render = 0.0
  let mut indexed_markers = read_markers
  let mut read_lookup = @domain.read_index(read_markers)
  @async.with_task_group(group => {
    while !@glfw.window_should_close(window) {
      @glfw.poll_events()
      let now = imgui_now()
      if control_path != "" && now - last_control_poll >= 0.5 {
        last_control_poll = now
        poll_control_commands(control_path, control_queue, [
          pull_requests, issues, review_requests, assignments, mentions, subscriptions,
        ])
      }
      for
        activities in [
          pull_requests, issues, review_requests, assignments, mentions, subscriptions,
        ] {
        for activity in activities {
          seen_revisions.set(activity.html_url(), activity.updated_at())
        }
      }
      if now - last_file_poll >= 2.0 {
        last_file_poll = now
        let read_state = read_text(read_state_path)
        if read_state != known_read_state {
          known_read_state = read_state
          match @read_state_store.decode(read_state) {
            Ok(markers) => {
              read_markers = markers
              println("store: read state changed outside the app")
            }
            Err(error) => println("store: read state reload failed: \{error}")
          }
        }
        let triage = read_text(triage_path)
        if triage != known_triage {
          known_triage = triage
          match @triage_store.decode(triage) {
            Ok(state) => {
              saved_urls.clear()
              muted_urls.clear()
              for url in state.saved {
                saved_urls.set(url, true)
              }
              for url in state.muted {
                muted_urls.set(url, true)
              }
              println("store: triage changed outside the app")
            }
            Err(error) => println("store: triage reload failed: \{error}")
          }
        }
        let repositories = read_text(repositories_path)
        if repositories != known_repositories {
          known_repositories = repositories
          match @repository_store.decode(repositories) {
            Ok(next) => {
              let previous = model.repositories()
              for repository in previous {
                if !next.any(entry => entry.key() == repository.key()) {
                  model = @domain.update(
                    model,
                    @domain.Msg::RemoveRepository(repository.key()),
                  )
                  @activity_sync.replace_activities(
                    pull_requests,
                    @activity_sync.without_repository(
                      pull_requests,
                      repository.key(),
                    ),
                  )
                  @activity_sync.replace_activities(
                    issues,
                    @activity_sync.without_repository(issues, repository.key()),
                  )
                }
              }
              let mut added = false
              for repository in next {
                if !previous.any(entry => entry.key() == repository.key()) {
                  model = @domain.update(
                    model,
                    @domain.Msg::RegisterRepository(repository),
                  )
                  added = true
                }
              }
              if added && !saved_tokens.is_empty() {
                pending_jobs.push(External)
              }
              println("store: watched repositories changed outside the app")
            }
            Err(error) => println("store: repositories reload failed: \{error}")
          }
        }
      }
      if running_job is None && !pending_jobs.is_empty() {
        let job = pending_jobs.remove(0)
        running_job = Some(job)
        loading_detail = ""
        active_generation += 1
        let generation = active_generation
        job_started_at = now
        live_tasks += 1
        running_task = Some(
          group.spawn(no_wait=true, allow_failure=true, () => {
            defer {
              live_tasks -= 1
            }
            let failed = try
              @async.with_timeout_opt(FETCH_JOB_TIMEOUT_MS, () => {
                run_job(job, generation)
              })
            catch {
              error => {
                if generation == active_generation {
                  notify("\{job.title()} failed.", None)
                }
                println("fetch-job: \{job.title()} failed: \{error}")
                true
              }
            } noraise {
              None => {
                if generation == active_generation {
                  job_timed_out(job)
                }
                true
              }
              Some(_) => false
            }
            println(
              "fetch-job: finished \{job.title()} generation=\{generation}",
            )
            // An abandoned job must not touch the state of the jobs after it.
            if generation != active_generation {
              return
            }
            if !failed &&
              repository_failures.is_empty() &&
              scope_failures.is_empty() {
              match job.success_message() {
                Some(message) => notify(message, None)
                None => ()
              }
              if job
                is (Startup | Credentials(_) | Everything | Auto | External) &&
                watched_incomplete.is_empty() &&
                personal_incomplete.is_empty() {
                prune_stale_records()
              }
            }
            job_finished()
          }),
        )
      }
      // Backstop for reads that ignore cancellation and the timeout above.
      match running_job {
        Some(job) if now - job_started_at >
          FETCH_JOB_TIMEOUT_MS.to_double() / 1000.0 + 5.0 => {
          println("fetch-job: abandoning \{job.title()} after timeout")
          abandon_job()
          job_timed_out(job)
        }
        _ => ()
      }
      let modal_job = match running_job {
        Some(job) if job.is_modal() => Some(job)
        _ =>
          for job in pending_jobs {
            if job.is_modal() {
              break Some(job)
            }
          } nobreak {
            None
          }
      }
      // The first load shows skeleton rows; once watched activity is on
      // screen, the rest of it continues in the background.
      let busy = if running_job is Some(Startup) && !has_loaded {
        3
      } else if running_job is Some(Startup) && pending_jobs.is_empty() {
        1
      } else if modal_job is Some(_) {
        2
      } else if running_job is Some(_) {
        1
      } else {
        0
      }
      let loading = match modal_job {
        None =>
          match running_job {
            Some(job) => "\{job.title()}\t\{loading_detail}"
            None => "\t"
          }
        Some(job) =>
          if running_job is Some(running) && running.is_modal() {
            "\{job.title()}\t\{safe_row_text(loading_detail)}"
          } else {
            "\{job.title()}\tWaiting for auto refresh to finish"
          }
      }
      let cancellable = match running_job {
        Some(job) => job.is_cancellable()
        None => false
      }
      let frame_started = if profiling {
        github_client_imgui_clock()
      } else {
        0.0
      }
      // Every change to the markers produces a new array, so the lookup
      // table is rebuilt only when the array itself changed.
      if !physical_equal(indexed_markers, read_markers) {
        read_lookup = @domain.read_index(read_markers)
        indexed_markers = read_markers
      }
      // Rows for the current page.
      let page = model.page()
      let filter = imgui_view_filter()
      let watched = model.repositories()
      let inbox_items = @activity_sync.watched_items(
        [pull_requests, issues],
        muted_urls,
      )
      let for_you_items = @activity_sync.personal_items(
        review_requests,
        assignments,
        mentions,
        subscriptions,
        watched,
        muted_urls,
        watched_only=true,
        kept_review_requests~,
      )
      let (rows, show_repository) = match page {
        Inbox | PullRequests | Issues =>
          (
            @domain.build_activity_rows(
              inbox_items,
              read_lookup,
              saved_urls,
              { ..filter, reason: "", },
              expanded_bundles,
              ByRepository,
            ),
            false,
          )
        ForYou =>
          (
            @domain.build_activity_rows(
              for_you_items,
              read_lookup,
              saved_urls,
              {
                ..@domain.ActivityFilter::default(),
                reason: filter.reason,
                show_done: filter.show_done,
              },
              expanded_bundles,
              Flat,
            ),
            true,
          )
        Saved =>
          (
            @domain.build_activity_rows(
              @activity_sync.saved_items(
                [
                  pull_requests, issues, review_requests, assignments, mentions,
                  subscriptions,
                ],
                saved_urls,
                muted_urls,
              ),
              read_lookup,
              saved_urls,
              { ..@domain.ActivityFilter::default(), show_done: true, },
              expanded_bundles,
              Flat,
            ),
            true,
          )
        Repositories | Settings => ([], false)
      }
      for key, since in fresh_since {
        if now - since > 3.0 {
          fresh_since.remove(key)
        }
      }
      let inbox_unread = @activity_sync.unread_count(inbox_items, read_lookup)
      let for_you_unread = @activity_sync.unread_count(
        for_you_items, read_lookup,
      )
      let header = match page {
        Inbox | PullRequests | Issues => {
          let noun = if watched.length() == 1 {
            "repository"
          } else {
            "repositories"
          }
          "\{inbox_unread} unread of \{inbox_items.length()} · \{watched.length()} watched \{noun}"
        }
        ForYou =>
          "\{for_you_unread} unread of \{for_you_items.length()} · review requests, assignments, mentions, and subscriptions in watched repositories"
        Saved => "Kept here until you remove them, even after Done"
        Repositories =>
          "Inbox and For you show activity from these repositories only."
        Settings => "Accounts and sync"
      }
      let has_data = !inbox_items.is_empty() || !for_you_items.is_empty()
      let banners = match page {
        Inbox | PullRequests | Issues | ForYou | Saved => {
          let problems = problem_banners(
            scope_failures,
            broken_scopes,
            repository_failures,
            watched.length(),
            has_data,
            dismissed_banners,
          )
          problems.append(
            incomplete_banners(
              [watched_incomplete, personal_incomplete],
              dismissed_banners,
            ),
          )
          if page is ForYou {
            problems.append(
              hidden_review_banners(
                [..review_requests, ..kept_review_requests],
                watched,
                muted_urls,
                dismissed_banners,
              ),
            )
          }
          problems
        }
        _ => []
      }
      let network_down = [scope_failures, repository_failures].any(failures => {
        failures
        .values()
        .any(message => @github_api.classify_failure(message) is Network)
      })
      let page_error = if busy == 0 && !has_data && network_down {
        "Can't reach GitHub\tThe request failed before GitHub responded. Check your network connection, then try again."
      } else {
        "\t"
      }
      let credential_problems : Map[String, String] = Map([])
      for scope, message in scope_failures {
        if @github_api.classify_failure(message) is Unauthorized {
          credential_problems.set(
            scope, "GitHub rejected this token. It may have expired or been revoked.",
          )
        }
      }
      for scope, message in broken_scopes {
        credential_problems.set(scope, message)
      }
      let has_credentials = !@credential_store.list_scopes().is_empty()
      let flags = (if has_credentials { 1 } else { 0 }) |
        (if cancellable { 2 } else { 0 })
      let rows_built = if profiling { github_client_imgui_clock() } else { 0.0 }
      let action = github_client_imgui_render(
        window,
        page.code(),
        busy,
        loading_done,
        loading_total,
        flags,
        "\{inbox_unread}\t\{for_you_unread}\t\{watched.length()}\t\{authenticated_login}\t\{data_directory}",
        "\{safe_row_text(header)}\t\{synced_label(last_synced, now)}",
        serialize_rows(rows, show_repository, fresh_since, now),
        repositories_text(watched),
        suggestions_text(
          suggested_repositories,
          watched,
          [..review_requests, ..kept_review_requests],
        ),
        credentials_text(credential_problems),
        banners_text(banners),
        loading,
        "\{snack_seq}\t\{safe_row_text(snack_message)}\t\{flag(undo_op is Some(_))}",
        "\{alert_seq}\t\{safe_row_text(alert_title)}\t\{safe_row_text(alert_body)}",
        "\{token_state}\t\{token_field}\t\{safe_row_text(token_message)}\t\{token_open_seq}\t\{token_close_seq}\t\{token_prefill}",
        page_error,
      )
      token_prefill = ""
      if profiling {
        let rendered = github_client_imgui_clock()
        profile_frames += 1
        profile_build += rows_built - frame_started
        profile_render += rendered - rows_built
        if profile_frames == 120 {
          println(
            "profile: build_ms=\{profile_build / 120.0 * 1000.0} render_ms=\{profile_render / 120.0 * 1000.0} markers=\{read_markers.length()} page=\{model.page().name()}",
          )
          profile_frames = 0
          profile_build = 0.0
          profile_render = 0.0
        }
      }
      let mut action = action
      // Commands wait while a fetch runs, as the loading dialog blocks UI
      // input; quit and cancel always go through.
      if action == 0 && !control_queue.is_empty() {
        // While busy only quit, cancel, and undo may pass the commands
        // queued before them.
        let allowed = (command : ControlCommand) => {
          busy == 0 || command.action is (99 | 27 | 26)
        }
        let index = for i, command in control_queue {
          if allowed(command) {
            break Some(i)
          }
        } nobreak {
          None
        }
        if index is Some(i) {
          let command = control_queue.remove(i)
          if command.action == 99 {
            @glfw.set_window_should_close(window, true)
          } else {
            github_client_imgui_stage(
              command.url,
              command.updated_at,
              command.repository,
              command.key,
            )
            action = command.action
          }
        }
      }
      match action {
        1 => {
          model = @domain.update(model, @domain.Msg::RequestSignIn)
          token_state = 0
          token_message = ""
          token_open_seq += 1
          println("ui-action: auth.sign-in")
        }
        2 => watch_repository(github_client_imgui_take_repository())
        3 => {
          let scope_raw = github_client_imgui_take_credential_scope()
          let token = github_client_imgui_take_token().trim().to_owned()
          match @credential_store.normalize_scope(scope_raw) {
            Err(_) => {
              token_state = 2
              token_field = 0
              token_message = "Use letters, numbers, and hyphens only, as in a GitHub URL."
            }
            Ok(scope) => {
              token_state = 1
              pending_jobs.push(VerifyToken(scope, token))
            }
          }
        }
        4 => {
          let url = github_client_imgui_take_url()
          if open_in_browser(url) {
            println("ui-action: activity.open")
          } else {
            notify("Couldn't open the link.", None)
          }
        }
        5 => {
          let key = github_client_imgui_take_selected_repository()
          match @domain.RepositoryRef::parse(key) {
            Ok(repository) => {
              model = @domain.update(model, @domain.Msg::RemoveRepository(key))
              @activity_sync.replace_activities(
                pull_requests,
                @activity_sync.without_repository(pull_requests, key),
              )
              @activity_sync.replace_activities(
                issues,
                @activity_sync.without_repository(issues, key),
              )
              repository_failures.remove(key)
              let saved_repositories = @repository_store.save_default(
                model.repositories(),
              )
              remember_files()
              match saved_repositories {
                Ok(_) => {
                  notify("Unwatched \{key}.", Some(Rewatch(repository)))
                  println("ui-action: repository.remove")
                }
                Err(error) => println("repository-store: save failed: \{error}")
              }
              pending_jobs.push(RemovedRepository)
            }
            Err(_) => ()
          }
        }
        6 => {
          let url = github_client_imgui_take_url()
          let updated_at = github_client_imgui_take_activity_updated_at()
          let previous = previous_read_at(read_markers, url)
          let label = activity_label(url)
          if @domain.activity_is_read(read_markers, url, updated_at) {
            read_markers = @domain.mark_activity_unread(read_markers, url)
            notify(
              "Moved \{label} back to the inbox.",
              Some(Restore([(url, previous)])),
            )
            println("ui-action: activity.restore")
          } else {
            read_markers = @domain.mark_activity_read(
              read_markers, url, updated_at,
            )
            notify("Marked \{label} as done.", Some(Restore([(url, previous)])))
            println("ui-action: activity.done")
          }
          save_read_markers()
        }
        22 => {
          let url = github_client_imgui_take_url()
          let label = activity_label(url)
          if saved_urls.contains(url) {
            saved_urls.remove(url)
            notify("Removed \{label} from Saved.", Some(ToggleSave(url)))
            println("ui-action: activity.unsave")
          } else {
            saved_urls.set(url, true)
            notify("Saved \{label} for later.", Some(ToggleSave(url)))
            println("ui-action: activity.save")
          }
          save_triage()
        }
        23 => {
          let url = github_client_imgui_take_url()
          muted_urls.set(url, true)
          save_triage()
          notify("Unsubscribed from \{activity_label(url)}.", Some(Unmute(url)))
          println("ui-action: activity.unsubscribe")
        }
        7 => {
          let scope = github_client_imgui_take_selected_credential()
          match @credential_store.delete_token_for(scope) {
            Ok(_) => {
              saved_tokens.remove(scope)
              broken_scopes.remove(scope)
              scope_failures.remove(scope)
              if scope == "default" {
                authenticated_login = ""
              }
              pending_jobs.push(
                Credentials("Removed the \{scope_label(scope)} token."),
              )
              println("ui-action: credential.remove scope=\{scope}")
            }
            Err(error) => {
              notify("Couldn't remove the token.", None)
              println("credential-store: delete failed: \{error}")
            }
          }
        }
        20 => {
          pending_jobs.push(Watched)
          println("ui-action: refresh.watched")
        }
        21 => {
          pending_jobs.push(Personal)
          println("ui-action: refresh.for-you")
        }
        32 => {
          pending_jobs.push(Everything)
          println("ui-action: refresh.all")
        }
        24 => {
          let key = github_client_imgui_take_key()
          if expanded_bundles.contains(key) {
            expanded_bundles.remove(key)
          } else {
            expanded_bundles.set(key, true)
          }
          println("ui-action: bundle.toggle \{key}")
        }
        25 => {
          let key = github_client_imgui_take_key()
          let entries : Array[(String, String?)] = []
          for item in inbox_items {
            if @domain.bundle_key(item.repository, item.author) == key &&
              !@domain.activity_is_read(read_markers, item.url, item.updated_at) {
              entries.push((item.url, previous_read_at(read_markers, item.url)))
              read_markers = @domain.mark_activity_read(
                read_markers,
                item.url,
                item.updated_at,
              )
            }
          }
          save_read_markers()
          notify(
            "Marked \{entries.length()} updates as done.",
            Some(Restore(entries)),
          )
          println("ui-action: bundle.done \{key}")
        }
        26 =>
          match undo_op {
            Some(op) => {
              undo_op = None
              apply_undo(op)
            }
            None => ()
          }
        27 =>
          match running_job {
            Some(job) if job.is_cancellable() => {
              abandon_job()
              notify("Refresh cancelled. Showing the previous results.", None)
              println("ui-action: fetch.cancel")
            }
            _ => ()
          }
        28 => {
          let key = github_client_imgui_take_key()
          if key == "retry" ||
            key == "repositories" ||
            key == "network" ||
            key == "forbidden" {
            dismissed_banners.clear()
            pending_jobs.push(Credentials(""))
          } else if key.has_prefix("token:") {
            model = @domain.update(
              model,
              @domain.Msg::Navigate(@domain.Page::Settings),
            )
            let scope = key[6:].to_owned()
            token_prefill = if scope == "default" { "-" } else { scope }
            token_state = 0
            token_message = ""
            token_open_seq += 1
          } else if key.has_prefix("watch:") {
            watch_repository(key[6:].to_owned())
          }
          println("ui-action: banner.action \{key}")
        }
        29 => dismissed_banners.set(github_client_imgui_take_key(), true)
        30 => token_state = 0
        31 => notify("Link copied.", None)
        10 => model = @domain.update(model, @domain.Msg::Navigate(Inbox))
        11 => model = @domain.update(model, @domain.Msg::Navigate(Repositories))
        14 => model = @domain.update(model, @domain.Msg::Navigate(Settings))
        15 => model = @domain.update(model, @domain.Msg::Navigate(ForYou))
        16 => model = @domain.update(model, @domain.Msg::Navigate(Saved))
        _ => ()
      }
      if action >= 10 && action <= 16 {
        println("ui-action: nav \{model.page().name()}")
      }
      if imgui_auto_refresh_enabled() &&
        !saved_tokens.is_empty() &&
        running_job is None &&
        pending_jobs.is_empty() &&
        @async.now() >= auto_paused_until_ms &&
        now - last_auto_refresh >= AUTO_REFRESH_SECONDS {
        last_auto_refresh = now
        pending_jobs.push(Auto)
      }
      @glfw.swap_buffers(window)
      // Yield to the async runtime so background fetches make progress.
      @async.pause()
    }
    // A job stuck in a read that ignores cancellation would keep the task
    // group, and so the process, alive after the window closes.
    if live_tasks > 0 {
      github_client_imgui_shutdown()
      @glfw.destroy_window(window)
      @glfw.terminate()
      println("github-client: stopped with a fetch still running")
      github_client_imgui_exit(0)
    }
  })
  github_client_imgui_shutdown()
  @glfw.destroy_window(window)
  @glfw.terminate()
  println("github-client: stopped")
}
