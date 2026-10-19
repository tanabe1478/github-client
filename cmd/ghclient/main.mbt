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
    Release => "release"
  }
}

///|
fn relation_json(relation : @domain.Relation) -> Json {
  {
    "project": relation.project.to_json(),
    "kind": relation.kind.name().to_json(),
    "label": relation.label.to_json(),
    "related": relation.counts().to_json(),
    "evidence": relation.evidence.to_json(),
  }
}

///|
fn item_json(
  item : @domain.ActivityItem,
  read : Bool,
  saved : Bool,
  relations? : Array[@domain.Relation]? = None,
) -> Json {
  let json : Json = {
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
  // The object's map is shared, so setting fields changes `json`.
  match json {
    Object(fields) if item.kind is Release => {
      fields.set("tag", item.tag.to_json())
      fields.set("summary", item.summary.to_json())
      fields.set("prerelease", item.prerelease.to_json())
      match relations {
        Some(found) =>
          fields.set("relations", found.map(relation_json).to_json())
        None => ()
      }
    }
    _ => ()
  }
  json
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
  let (kind, number) = match item.kind {
    PullRequest => ("PR   ", "#\{item.number}")
    Issue => ("Issue", "#\{item.number}")
    Release => ("Rel  ", " \{item.tag}")
  }
  let labels : Array[String] = []
  if item.draft {
    labels.push("draft")
  }
  if item.prerelease {
    labels.push("pre-release")
  }
  if saved {
    labels.push("saved")
  }
  for reason in item.reasons {
    labels.push(reason)
  }
  let suffix = if labels.is_empty() { "" } else { "  [\{labels.join(", ")}]" }
  let title = if item.summary == "" {
    item.title
  } else {
    "\{item.title}  \{item.summary}"
  }
  "\{state}  \{kind}  \{item.repository}\{number}  \{title}  @\{item.author}  \{@domain.short_date(item.updated_at)}\{suffix}\n    \{item.url}"
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
/// The kinds `options` chooses for `repositories`: pull requests and issues
/// together, and releases.
async fn Session::fetch_watched(
  self : Session,
  repositories : Array[@domain.RepositoryRef],
  options : Map[String, @domain.WatchOptions],
) -> (Array[@github_api.ActivitySummary], Array[@github_api.ActivitySummary]) {
  let pull_requests = []
  let issues = []
  let releases = []
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
    options~,
    releases~,
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
      options~,
      releases~,
    )
  }
  for repository, message in failures {
    self.errors.push({ source: repository, message, })
  }
  pull_requests.append(issues)
  (pull_requests, releases)
}

///|
async fn Session::fetch_personal(
  self : Session,
) -> Array[Array[@github_api.ActivitySummary]] {
  let lists = [[], [], [], []]
  let failures : Map[String, String] = Map([])
  let settings = match @settings_store.load_default() {
    Ok(settings) => settings
    Err(message) => {
      self.errors.push({ source: "settings", message, })
      @settings_store.default_settings()
    }
  }
  let since = @activity_sync.utc_days_ago(@async.now(), settings.mention_days)
  let closed_mentions = @activity_sync.closed_mentions(
    since,
    merged=settings.include_merged_mentions,
    closed=settings.include_closed_mentions,
  )
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
    closed_mentions~,
  )
  for scope, message in failures {
    self.errors.push({ source: "token:\{scope}", message, })
  }
  let mention_failures = @activity_sync.fetch_review_comment_mentions(
    self.tokens,
    self.repo_scopes,
    self.owner_scopes,
    for_you_repositories(),
    @activity_sync.saved_logins(),
    since,
    lists[2],
    incomplete=self.incomplete,
    closed_mentions~,
  )
  for repository, message in mention_failures {
    self.errors.push({ source: repository, message, })
  }
  lists
}

///|
/// Base projects from settings.txt, read from GitHub. When a token cannot
/// reach one and more tokens are saved, the token assignment is loaded and
/// it is read again.
async fn Session::fetch_profiles(
  self : Session,
) -> Array[@domain.ProjectProfile] {
  let settings = load_settings_or_default()
  let repositories = settings.base_repositories
  let profiles = @activity_sync.fetch_project_profiles(
    self.tokens,
    self.repo_scopes,
    self.owner_scopes,
    repositories,
    npm_mirrors=settings.npm_mirrors,
  )
  let retry = profiles.any(profile => {
    profile.problem.has_prefix("The token can't") ||
    profile.problem.has_prefix("No saved token") ||
    profile.problem.has_prefix("Couldn't read the repository")
  })
  if retry && !self.scopes_loaded && self.tokens.length() > 1 {
    self.load_scopes()
    return @activity_sync.fetch_project_profiles(
      self.tokens,
      self.repo_scopes,
      self.owner_scopes,
      repositories,
      npm_mirrors=settings.npm_mirrors,
    )
  }
  profiles
}

///|
fn load_settings_or_default() -> @settings_store.Settings {
  @settings_store.load_default().unwrap_or(@settings_store.default_settings())
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
fn load_watch_entries() -> (
  Array[@domain.RepositoryRef],
  Map[String, @domain.WatchOptions],
) {
  @repository_store.load_default_entries().unwrap_or(([], Map([])))
}

///|
/// Watched repositories whose options include For you.
fn for_you_repositories() -> Array[@domain.RepositoryRef] {
  let (repositories, options) = load_watch_entries()
  @domain.for_you_repositories(repositories, options)
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
  relations? : Map[String, Array[@domain.Relation]]? = None,
) -> Int {
  let warnings : Array[String] = []
  for name, _ in incomplete {
    warnings.push(
      "\{name} hit the page limit; only the newest items are included",
    )
  }
  let filter = invocation.filter()
  let index = @domain.read_index(markers)
  let related_of = (item : @domain.ActivityItem) => {
    relations
    .map(map => map.get(item.url).unwrap_or([]))
    .unwrap_or([])
    // With --project, only that project's relations are shown.
    .filter(relation => {
      invocation.project == "" || relation.project == invocation.project
    })
  }
  let visible = items.filter(item => {
    @domain.matches_filter(
      item,
      filter,
      @domain.is_read_in(index, item.url, item.updated_at),
    ) &&
    (
    // --project implies --related for that project.
      !(invocation.related || invocation.project != "") ||
      related_of(item).any(relation => {
        relation.counts() &&
        (invocation.project == "" || relation.project == invocation.project)
      })
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
          relations=relations.map(_ => related_of(item)),
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
      for relation in related_of(item) {
        println("    \{relation.project} · \{relation.label}")
      }
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
      let (repositories, options) = load_watch_entries()
      // Releases have their own command.
      let without_releases : Map[String, @domain.WatchOptions] = Map([])
      for repository in repositories {
        let key = repository.key()
        without_releases.set(key, {
          ..@domain.watch_options_for(options, key),
          releases: false,
        })
      }
      let (activities, _) = session.fetch_watched(
        repositories, without_releases,
      )
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
        for_you_repositories(),
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
    "releases" => {
      let (session, _) = load_session()
      if session.tokens.is_empty() {
        print_error("no token is saved; add one in the app first")
        return 1
      }
      let (saved, muted) = load_triage()
      let (repositories, options) = load_watch_entries()
      let chosen = repositories.filter(repository => {
        @domain.watch_options_for(options, repository.key()).releases
      })
      let releases_only : Map[String, @domain.WatchOptions] = Map([])
      for repository in chosen {
        releases_only.set(repository.key(), {
          ..@domain.watch_options_for(options, repository.key()),
          pull_requests: false,
          issues: false,
        })
      }
      let (_, releases) = session.fetch_watched(chosen, releases_only)
      let profiles = session.fetch_profiles()
      // New versions of dependencies that have no GitHub releases to watch
      // (ADR 0008).
      releases.append(
        @activity_sync.fetch_registry_releases(
          session.tokens,
          session.repo_scopes,
          session.owner_scopes,
          profiles,
        ),
      )
      let relations : Map[String, Array[@domain.Relation]] = Map([])
      for release in releases {
        relations.set(
          release.html_url(),
          @domain.release_relations(
            release.repository(),
            release.tag(),
            release.notes(),
            profiles,
          ),
        )
      }
      print_items(
        invocation,
        @activity_sync.watched_items([releases], muted),
        load_markers(),
        saved,
        session.errors,
        relations=Some(relations),
      )
    }
    "watch-candidates" => {
      let (session, _) = load_session()
      let profiles = session.fetch_profiles()
      let (watched, _) = load_watch_entries()
      let candidates = @domain.watch_candidates(
        profiles,
        watched.map(repository => repository.key()),
      )
      if invocation.json {
        let json : Json = {
          "candidates": candidates
          .map(candidate => {
            let json : Json = {
              "repository": candidate.repository.to_json(),
              "projects": candidate.projects.to_json(),
              "uses": candidate.uses.to_json(),
              "released": candidate.released.to_json(),
            }
            json
          })
          .to_json(),
        }
        println(json.stringify())
      } else {
        if candidates.is_empty() {
          println("Every repository the base projects depend on is watched.")
        }
        for candidate in candidates {
          let note = if candidate.released {
            ""
          } else {
            "  no GitHub releases"
          }
          println(
            "\{candidate.repository}  (\{candidate.uses.join(", ")})\{note}",
          )
        }
      }
      0
    }
    "projects" => {
      let settings = load_settings_or_default()
      let (session, _) = load_session()
      let profiles = session.fetch_profiles()
      if invocation.json {
        let json : Json = {
          "projects": profiles
          .map(profile => {
            let json : Json = {
              "repository": profile.name.to_json(),
              "package_name": profile.package_name.to_json(),
              "tools": profile.tools
              .map(tool => {
                let json : Json = {
                  "name": tool.name.to_json(),
                  "version": tool.version.to_json(),
                  "exact": tool.exact.to_json(),
                  "source": tool.source.to_json(),
                }
                json
              })
              .to_json(),
              "settings": profile.settings
              .map(setting => {
                let json : Json = {
                  "key": setting.key.to_json(),
                  "file": setting.file.to_json(),
                }
                json
              })
              .to_json(),
              "files": profile.files.to_json(),
              "dependency_count": profile.dependency_count.to_json(),
              "managed": profile.managed.to_json(),
              "moved_to": profile.moved_to.to_json(),
              "sources": profile.sources
              .map(source => {
                let json : Json = {
                  "name": source.name.to_json(),
                  "repository": source.repository.to_json(),
                  "host": source.host.to_json(),
                }
                json
              })
              .to_json(),
              "unreleased": profile.unreleased.to_json(),
              "npm_registry": profile.npm_registry.to_json(),
              "followed": profile.followed
              .map(followed => {
                let json : Json = {
                  "name": followed.name.to_json(),
                  "ecosystem": followed.ecosystem.to_json(),
                  "source_host": followed.source_host.to_json(),
                  "source_repository": followed.source_repository.to_json(),
                }
                json
              })
              .to_json(),
              "problem": profile.problem.to_json(),
            }
            json
          })
          .to_json(),
        }
        println(json.stringify())
      } else {
        if profiles.is_empty() {
          println("No base projects. Add one with ghclient project-add.")
        }
        for profile in profiles {
          println(profile.name)
          if profile.problem != "" {
            println("  problem: \{profile.problem}")
          } else if profile.tools.is_empty() &&
            profile.settings.is_empty() &&
            profile.dependency_count == 0 {
            println(
              "  nothing this app reads (npm, Gradle, Maven, GitHub Actions, Terraform) was found",
            )
          }
          if profile.moved_to != "" {
            println(
              "  now \{profile.moved_to}: ghclient project-remove \{profile.name} && ghclient project-add \{profile.moved_to}",
            )
          }
          for headline in @domain.headline_tools(profile) {
            println("  \{headline}")
          }
          if profile.npm_registry != "" &&
            !settings.npm_mirrors.contains(profile.npm_registry) {
            println(
              "  npm packages come from \{profile.npm_registry}; to look up their repositories: ghclient npm-mirror-add \{profile.npm_registry}",
            )
          }
          println(
            "  \{profile.dependency_count} dependencies · \{profile.settings.length()} settings in \{setting_files(profile)} files · \{profile.files.length()} files read",
          )
        }
      }
      if profiles.any(profile => profile.problem != "") {
        3
      } else {
        0
      }
    }
    "project-add" | "project-remove" => {
      let settings = load_settings_or_default()
      let repositories = settings.base_repositories.copy()
      let results : Array[(String, Result[String, String])] = []
      for argument in invocation.arguments {
        let raw = @project_reader.repository_input(argument)
        if invocation.command == "project-remove" {
          if repositories.contains(raw) {
            repositories.retain(repository => repository != raw)
            results.push((raw, Ok("removed")))
          } else {
            results.push((raw, Err("not a base project")))
          }
          continue
        }
        // A directory that exists adds the repositories found under it;
        // anything else is read as owner/name.
        let directory = @project_reader.expand_home(raw)
        if @project_reader.is_directory(directory) {
          match @project_reader.discover_repositories(raw) {
            Ok(found) => {
              let added = found.filter(name => !repositories.contains(name))
              repositories.append(added)
              results.push(
                (
                  raw,
                  Ok(
                    "added \{added.length()} of \{found.length()} repositories found: \{found.join(", ")}",
                  ),
                ),
              )
            }
            Err(message) => results.push((raw, Err(message)))
          }
        } else {
          match @domain.RepositoryRef::parse(raw) {
            Ok(reference) => {
              let key = reference.key()
              if repositories.contains(key) {
                results.push((key, Ok("already a base project")))
              } else {
                repositories.push(key)
                results.push((key, Ok("added")))
              }
            }
            Err(_) =>
              results.push(
                (raw, Err("not an existing directory or owner/name")),
              )
          }
        }
      }
      match
        @settings_store.save_default({
          ..settings,
          base_repositories: repositories,
        }) {
        Ok(_) => print_results(invocation, results)
        Err(error) => {
          print_error("could not save settings: \{error}")
          1
        }
      }
    }
    "npm-mirror-add" | "npm-mirror-remove" => {
      let settings = load_settings_or_default()
      let mirrors = settings.npm_mirrors.copy()
      let results : Array[(String, Result[String, String])] = []
      for argument in invocation.arguments {
        let url = @project_reader.registry_key(argument)
        if !url.has_prefix("https://") && !url.has_prefix("http://") {
          results.push((argument, Err("not a URL")))
        } else if invocation.command == "npm-mirror-remove" {
          if mirrors.contains(url) {
            mirrors.retain(mirror => mirror != url)
            results.push((url, Ok("removed")))
          } else {
            results.push((url, Err("not an npm mirror")))
          }
        } else if mirrors.contains(url) {
          results.push((url, Ok("already an npm mirror")))
        } else {
          mirrors.push(url)
          results.push((url, Ok("added")))
        }
      }
      match
        @settings_store.save_default({ ..settings, npm_mirrors: mirrors, }) {
        Ok(_) => print_results(invocation, results)
        Err(error) => {
          print_error("could not save settings: \{error}")
          1
        }
      }
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
        match @activity_sync.is_activity_url(url) {
          true => {
            markers = @domain.mark_activity_unread(markers, url)
            results.push((url, Ok("unread")))
          }
          false =>
            results.push(
              (
                url,
                Err(
                  "expected a https://github.com/owner/repo/pull/N, /issues/N, or /releases/tag/TAG URL",
                ),
              ),
            )
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
        match @activity_sync.is_activity_url(url) {
          true => {
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
          false =>
            results.push(
              (
                url,
                Err(
                  "expected a https://github.com/owner/repo/pull/N, /issues/N, or /releases/tag/TAG URL",
                ),
              ),
            )
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
      let (repositories, options) = load_watch_entries()
      if invocation.json {
        let json : Json = {
          "repositories": repositories
          .map(repository => repository.key())
          .to_json(),
          "options": repositories
          .map(repository => {
            let entry = @domain.watch_options_for(options, repository.key())
            let kinds = entry.kinds_text()
            let json : Json = {
              "repository": repository.key().to_json(),
              "kinds": (if kinds == "" {
                []
              } else {
                kinds.split(",").map(kind => kind.to_owned()).to_array()
              }).to_json(),
              "release_notify": entry.release_notify.name().to_json(),
            }
            json
          })
          .to_json(),
        }
        println(json.stringify())
      } else {
        for repository in repositories {
          let entry = @domain.watch_options_for(options, repository.key())
          let releases = if entry.releases {
            "  releases=\{entry.release_notify.name()}"
          } else {
            ""
          }
          println("\{repository.key()}  \{entry.kinds_text()}\{releases}")
        }
      }
      0
    }
    "watch" | "unwatch" => {
      let mut model = @domain.Model::new()
      let (repositories, options) = load_watch_entries()
      for repository in repositories {
        model = @domain.update(model, RegisterRepository(repository))
      }
      let results : Array[(String, Result[String, String])] = []
      for raw in invocation.arguments {
        match @domain.RepositoryRef::parse(raw) {
          Ok(repository) =>
            if invocation.command == "watch" {
              model = @domain.update(model, RegisterRepository(repository))
              let key = repository.key()
              let mut entry = @domain.watch_options_for(options, key)
              if invocation.kinds != "" {
                // Validated while parsing the options.
                entry = entry.with_kinds(invocation.kinds).unwrap_or(entry)
              }
              match @domain.ReleaseNotify::parse(invocation.release_notify) {
                Some(level) => entry = { ..entry, release_notify: level, }
                None => ()
              }
              options.set(key, entry)
              results.push(
                (
                  key,
                  Ok(
                    "watched: \{entry.kinds_text()}, releases=\{entry.release_notify.name()}",
                  ),
                ),
              )
            } else {
              model = @domain.update(model, RemoveRepository(repository.key()))
              results.push((repository.key(), Ok("not watched")))
            }
          Err(message) => results.push((raw, Err(message)))
        }
      }
      match @repository_store.save_default(model.repositories(), options) {
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

///|
/// How many files a profile's settings come from.
fn setting_files(profile : @domain.ProjectProfile) -> Int {
  let files : Array[String] = []
  for setting in profile.settings {
    if !files.contains(setting.file) {
      files.push(setting.file)
    }
  }
  files.length()
}
