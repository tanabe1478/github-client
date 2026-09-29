///|
/// A failed GitHub request: the token scope or repository it concerns.
priv struct FetchError {
  source : String
  message : String
}

///|
priv struct Session {
  tokens : Map[String, String]
  repo_scopes : Map[String, String]
  owner_scopes : Map[String, String]
  mut scopes_loaded : Bool
  errors : Array[FetchError]
  incomplete : Map[String, Bool]
}

///|
#borrow(text)
extern "C" fn eprintln(text : String) -> Unit = "ghclient_eprintln"

///|
fn print_error(message : String) -> Unit {
  eprintln("ghclient: \{message}")
}

///|
fn kind_name(kind : @domain.InboxItemKind) -> String {
  match kind {
    PullRequest => "pull_request"
    Issue => "issue"
  }
}

///|
fn item_json(item : @domain.ActivityItem, read : Bool, saved : Bool) -> Json {
  {
    "url": item.url.to_json(),
    "repository": item.repository.to_json(),
    "number": item.number.to_json(),
    "kind": kind_name(item.kind).to_json(),
    "draft": item.draft.to_json(),
    "title": item.title.to_json(),
    "author": item.author.to_json(),
    "updated_at": item.updated_at.to_json(),
    "read": read.to_json(),
    "saved": saved.to_json(),
    "reasons": item.reasons.to_json(),
  }
}

///|
fn errors_json(errors : Array[FetchError]) -> Json {
  errors
  .map(error => {
    let json : Json = {
      "source": error.source.to_json(),
      "message": error.message.to_json(),
    }
    json
  })
  .to_json()
}

///|
fn item_line(item : @domain.ActivityItem, read : Bool, saved : Bool) -> String {
  let state = if read { "done  " } else { "unread" }
  let kind = if item.kind is PullRequest { "PR   " } else { "Issue" }
  let labels : Array[String] = []
  if item.draft {
    labels.push("draft")
  }
  if saved {
    labels.push("saved")
  }
  for reason in item.reasons {
    labels.push(reason)
  }
  let suffix = if labels.is_empty() { "" } else { "  [\{labels.join(", ")}]" }
  "\{state}  \{kind}  \{item.repository}#\{item.number}  \{item.title}  @\{item.author}  \{@domain.short_date(item.updated_at)}\{suffix}\n    \{item.url}"
}

///|
fn load_session() -> (Session, Array[FetchError]) {
  let tokens : Map[String, String] = Map([])
  let problems : Array[FetchError] = []
  for scope in @credential_store.list_scopes() {
    match @credential_store.load_token_for(scope) {
      Ok(Some(token)) => tokens.set(scope, token)
      Ok(None) => ()
      Err(error) =>
        problems.push({
          source: "token:\{scope}",
          message: "could not read the token: \{error}",
        })
    }
  }
  (
    {
      tokens,
      repo_scopes: Map([]),
      owner_scopes: Map([]),
      scopes_loaded: false,
      errors: problems.copy(),
      incomplete: Map([]),
    },
    problems,
  )
}

///|
/// Loads which token can reach which repository. This is slow (every
/// token's repository list), so it runs only when a request failed with
/// the token picked by owner scope or the default token.
async fn Session::load_scopes(self : Session) -> Unit {
  if self.scopes_loaded || self.tokens.length() < 2 {
    return
  }
  self.scopes_loaded = true
  let failures : Map[String, String] = Map([])
  @activity_sync.fetch_repository_suggestions(
    self.tokens,
    self.repo_scopes,
    self.owner_scopes,
    [],
    failures,
  )
  for scope, message in failures {
    self.errors.push({ source: "token:\{scope}", message, })
  }
}

///|
fn retryable(message : String) -> Bool {
  @github_api.classify_failure(message) is (NotFound | Unauthorized | Forbidden)
}

///|
async fn Session::fetch_watched(
  self : Session,
  repositories : Array[@domain.RepositoryRef],
) -> Array[@github_api.ActivitySummary] {
  let pull_requests = []
  let issues = []
  let failures : Map[String, String] = Map([])
  @activity_sync.fetch_watched_activity(
    self.tokens,
    self.repo_scopes,
    self.owner_scopes,
    repositories,
    pull_requests,
    issues,
    failures,
    () => (),
    incomplete=self.incomplete,
  )
  let retry = repositories.filter(repository => {
    failures.get(repository.key()).map(retryable).unwrap_or(false)
  })
  if !retry.is_empty() && !self.scopes_loaded && self.tokens.length() > 1 {
    self.load_scopes()
    for repository in retry {
      failures.remove(repository.key())
    }
    @activity_sync.fetch_watched_activity(
      self.tokens,
      self.repo_scopes,
      self.owner_scopes,
      retry,
      pull_requests,
      issues,
      failures,
      () => (),
      incomplete=self.incomplete,
    )
  }
  for repository, message in failures {
    self.errors.push({ source: repository, message, })
  }
  pull_requests.append(issues)
  pull_requests
}

///|
async fn Session::fetch_personal(
  self : Session,
) -> Array[Array[@github_api.ActivitySummary]] {
  let lists = [[], [], [], []]
  let failures : Map[String, String] = Map([])
  @activity_sync.refresh_personal_activity(
    self.tokens,
    lists[0],
    lists[1],
    lists[2],
    lists[3],
    failures,
    _ => (),
    () => (),
    incomplete=self.incomplete,
  )
  for scope, message in failures {
    self.errors.push({ source: "token:\{scope}", message, })
  }
  lists
}

///|
async fn Session::fetch_activity(
  self : Session,
  url : String,
) -> Result[@github_api.ActivitySummary, String] {
  match
    @activity_sync.fetch_activity(
      self.tokens,
      self.repo_scopes,
      self.owner_scopes,
      url,
    ) {
    Err(message) if retryable(message) &&
      !self.scopes_loaded &&
      self.tokens.length() > 1 => {
      self.load_scopes()
      @activity_sync.fetch_activity(
        self.tokens,
        self.repo_scopes,
        self.owner_scopes,
        url,
      )
    }
    result => result
  }
}

///|
fn load_triage() -> (Map[String, Bool], Map[String, Bool]) {
  let saved : Map[String, Bool] = Map([])
  let muted : Map[String, Bool] = Map([])
  match @triage_store.load_default() {
    Ok(state) => {
      for url in state.saved {
        saved.set(url, true)
      }
      for url in state.muted {
        muted.set(url, true)
      }
    }
    Err(_) => ()
  }
  (saved, muted)
}

///|
fn save_triage(
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
fn load_markers() -> Array[@domain.ReadMarker] {
  @read_state_store.load_default().unwrap_or([])
}

///|
fn load_repositories() -> Array[@domain.RepositoryRef] {
  @repository_store.load_default().unwrap_or([])
}

///|
/// Prints a list of items and returns the exit code.
fn print_items(
  invocation : Invocation,
  items : Array[@domain.ActivityItem],
  markers : Array[@domain.ReadMarker],
  saved : Map[String, Bool],
  errors : Array[FetchError],
  incomplete? : Map[String, Bool] = Map([]),
) -> Int {
  let warnings : Array[String] = []
  for name, _ in incomplete {
    warnings.push(
      "\{name} hit the page limit; only the newest items are included",
    )
  }
  let filter = invocation.filter()
  let index = @domain.read_index(markers)
  let visible = items.filter(item => {
    @domain.matches_filter(
      item,
      filter,
      @domain.is_read_in(index, item.url, item.updated_at),
    )
  })
  visible.sort_by((a, b) => b.updated_at.compare(a.updated_at))
  if invocation.json {
    let json : Json = {
      "items": visible
      .map(item => {
        item_json(
          item,
          @domain.is_read_in(index, item.url, item.updated_at),
          saved.contains(item.url),
        )
      })
      .to_json(),
      "errors": errors_json(errors),
      "warnings": warnings.to_json(),
    }
    println(json.stringify())
  } else {
    for warning in warnings {
      println("warning: \{warning}")
    }
    for item in visible {
      println(
        item_line(
          item,
          @domain.is_read_in(index, item.url, item.updated_at),
          saved.contains(item.url),
        ),
      )
    }
    if visible.is_empty() {
      println("No items.")
    }
    for error in errors {
      println("error: \{error.source}: \{error.message}")
    }
  }
  if errors.is_empty() {
    0
  } else {
    3
  }
}

///|
/// Prints the outcome of a command that changes local state, one result per
/// argument, and returns the exit code.
fn print_results(
  invocation : Invocation,
  results : Array[(String, Result[String, String])],
) -> Int {
  if invocation.json {
    let json : Json = {
      "results": results
      .map(entry => {
        let (target, result) = entry
        let json : Json = match result {
          Ok(state) =>
            {
              "target": target.to_json(),
              "ok": true.to_json(),
              "state": state.to_json(),
            }
          Err(message) =>
            {
              "target": target.to_json(),
              "ok": false.to_json(),
              "error": message.to_json(),
            }
        }
        json
      })
      .to_json(),
    }
    println(json.stringify())
  } else {
    for entry in results {
      match entry.1 {
        Ok(state) => println("\{entry.0}: \{state}")
        Err(message) => println("\{entry.0}: error: \{message}")
      }
    }
  }
  if results.all(entry => entry.1 is Ok(_)) {
    0
  } else {
    1
  }
}

///|
async fn run(invocation : Invocation) -> Int {
  match invocation.command {
    "help" => {
      println(usage.trim_end(chars="\n"))
      0
    }
    "inbox" => {
      let (session, _) = load_session()
      if session.tokens.is_empty() {
        print_error("no token is saved; add one in the app first")
        return 1
      }
      let (saved, muted) = load_triage()
      let activities = session.fetch_watched(load_repositories())
      print_items(
        invocation,
        @activity_sync.watched_items([activities], muted),
        load_markers(),
        saved,
        session.errors,
        incomplete=session.incomplete,
      )
    }
    "for-you" => {
      let (session, _) = load_session()
      if session.tokens.is_empty() {
        print_error("no token is saved; add one in the app first")
        return 1
      }
      let (saved, muted) = load_triage()
      let lists = session.fetch_personal()
      // Keep review requests GitHub dropped after a teammate reviewed for
      // the team, until the viewer reviews too; the app does the same.
      let follow_up = @activity_sync.follow_up_review_requests(
        session.tokens,
        session.repo_scopes,
        session.owner_scopes,
        @review_request_store.load_default().unwrap_or([]),
        lists[0],
        @activity_sync.saved_logins(),
      )
      match @review_request_store.save_default(follow_up.kept_urls) {
        Ok(_) => ()
        Err(error) =>
          session.errors.push({ source: "review-requests", message: error, })
      }
      let items = @activity_sync.personal_items(
        lists[0],
        lists[1],
        lists[2],
        lists[3],
        load_repositories(),
        muted,
        watched_only=true,
        kept_review_requests=follow_up.pending,
      )
      print_items(
        invocation,
        items,
        load_markers(),
        saved,
        session.errors,
        incomplete=session.incomplete,
      )
    }
    "saved" => {
      let (session, _) = load_session()
      let (saved, muted) = load_triage()
      let urls : Array[String] = []
      for url, _ in saved {
        if !muted.contains(url) {
          urls.push(url)
        }
      }
      let fetched = @async.all(
        urls.map(url => async fn() { (url, session.fetch_activity(url)) }),
        max_concurrent=6,
      )
      let items : Array[@domain.ActivityItem] = []
      for entry in fetched {
        match entry.1 {
          Ok(activity) => items.push(@activity_sync.activity_item(activity, []))
          Err(message) => session.errors.push({ source: entry.0, message, })
        }
      }
      print_items(
        { ..invocation, all: true, },
        items,
        load_markers(),
        saved,
        session.errors,
      )
    }
    "done" => {
      let (session, _) = load_session()
      let mut markers = load_markers()
      let results : Array[(String, Result[String, String])] = []
      for url in invocation.arguments {
        match session.fetch_activity(url) {
          Ok(activity) => {
            markers = @domain.mark_activity_read(
              markers,
              activity.html_url(),
              activity.updated_at(),
            )
            results.push((url, Ok("done")))
          }
          Err(message) => results.push((url, Err(message)))
        }
      }
      match @read_state_store.save_default(markers) {
        Ok(_) => print_results(invocation, results)
        Err(error) => {
          print_error("could not save the done state: \{error}")
          1
        }
      }
    }
    "undone" => {
      let mut markers = load_markers()
      let results : Array[(String, Result[String, String])] = []
      for url in invocation.arguments {
        match @activity_sync.parse_activity_url(url) {
          Ok(_) => {
            markers = @domain.mark_activity_unread(markers, url)
            results.push((url, Ok("unread")))
          }
          Err(message) => results.push((url, Err(message)))
        }
      }
      match @read_state_store.save_default(markers) {
        Ok(_) => print_results(invocation, results)
        Err(error) => {
          print_error("could not save the done state: \{error}")
          1
        }
      }
    }
    "save" | "unsave" | "mute" | "unmute" => {
      let (saved, muted) = load_triage()
      let results : Array[(String, Result[String, String])] = []
      for url in invocation.arguments {
        match @activity_sync.parse_activity_url(url) {
          Ok(_) => {
            let state = match invocation.command {
              "save" => {
                saved.set(url, true)
                "saved"
              }
              "unsave" => {
                saved.remove(url)
                "not saved"
              }
              "mute" => {
                muted.set(url, true)
                "muted"
              }
              _ => {
                muted.remove(url)
                "not muted"
              }
            }
            results.push((url, Ok(state)))
          }
          Err(message) => results.push((url, Err(message)))
        }
      }
      match save_triage(saved, muted) {
        Ok(_) => print_results(invocation, results)
        Err(error) => {
          print_error("could not save: \{error}")
          1
        }
      }
    }
    "repos" => {
      let repositories = load_repositories()
      if invocation.json {
        let json : Json = {
          "repositories": repositories
          .map(repository => repository.key())
          .to_json(),
        }
        println(json.stringify())
      } else {
        for repository in repositories {
          println(repository.key())
        }
      }
      0
    }
    "watch" | "unwatch" => {
      let mut model = @domain.Model::new()
      for repository in load_repositories() {
        model = @domain.update(model, RegisterRepository(repository))
      }
      let results : Array[(String, Result[String, String])] = []
      for raw in invocation.arguments {
        match @domain.RepositoryRef::parse(raw) {
          Ok(repository) =>
            if invocation.command == "watch" {
              model = @domain.update(model, RegisterRepository(repository))
              results.push((repository.key(), Ok("watched")))
            } else {
              model = @domain.update(model, RemoveRepository(repository.key()))
              results.push((repository.key(), Ok("not watched")))
            }
          Err(message) => results.push((raw, Err(message)))
        }
      }
      match @repository_store.save_default(model.repositories()) {
        Ok(_) => print_results(invocation, results)
        Err(error) => {
          print_error("could not save: \{error}")
          1
        }
      }
    }
    "accounts" => {
      let (_, problems) = load_session()
      let scopes = @credential_store.list_scopes()
      if invocation.json {
        let json : Json = {
          "accounts": scopes
          .map(scope => {
            let json : Json = {
              "scope": scope.to_json(),
              "login": @credential_store.load_login_label(scope)
              .unwrap_or("")
              .to_json(),
            }
            json
          })
          .to_json(),
          "errors": errors_json(problems),
        }
        println(json.stringify())
      } else {
        for scope in scopes {
          let login = @credential_store.load_login_label(scope).unwrap_or("")
          println("\{scope}  @\{login}")
        }
        for problem in problems {
          println("error: \{problem.source}: \{problem.message}")
        }
      }
      if problems.is_empty() {
        0
      } else {
        3
      }
    }
    _ => 2
  }
}

///|
async fn main {
  let args = @env.args()
  let invocation = match parse_invocation(args[1:].to_owned()) {
    Ok(invocation) => invocation
    Err(message) => {
      print_error("\{message}\nRun ghclient --help for usage.")
      @sys.exit(2)
      return
    }
  }
  // stdout carries only the command's output; diagnostics go to stderr on
  // request.
  @github_api.set_logger(fn(message) {
    if invocation.verbose {
      eprintln(message)
    }
  })
  @sys.exit(run(invocation))
}
