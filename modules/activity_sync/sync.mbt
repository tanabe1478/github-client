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
/// Picks the token for a repository: an exact owner scope, then the token
/// whose accessible list holds the repository, then one that holds the
/// owner, then the default token.
pub fn resolve_token(
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
pub fn append_unique_activities(
  dst : Array[@github_api.ActivitySummary],
  items : Array[@github_api.ActivitySummary],
) -> Unit {
  for item in items {
    if !dst.any(existing => existing.html_url() == item.html_url()) {
      dst.push(item)
    }
  }
}

///|
pub fn replace_activities(
  dst : Array[@github_api.ActivitySummary],
  src : Array[@github_api.ActivitySummary],
) -> Unit {
  dst.clear()
  dst.append(src)
}

///|
pub fn replace_scopes(
  dst : Map[String, String],
  src : Map[String, String],
) -> Unit {
  dst.clear()
  for key, value in src {
    dst.set(key, value)
  }
}

///|
pub fn without_repository(
  activities : Array[@github_api.ActivitySummary],
  repository : String,
) -> Array[@github_api.ActivitySummary] {
  activities.filter(activity => activity.repository() != repository)
}

///|
/// Scopes in a stable order with the default token first.
pub fn ordered_scopes(tokens : Map[String, String]) -> Array[String] {
  let scopes : Array[String] = []
  for scope, _ in tokens {
    if scope != "default" {
      scopes.push(scope)
    }
  }
  scopes.sort()
  if tokens.contains("default") {
    scopes.insert(0, "default")
  }
  scopes
}

///|
/// Loads repository suggestions for every token. Failures are recorded per
/// scope in `failures`.
pub async fn fetch_repository_suggestions(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  suggested_repositories : Array[@github_api.RepositorySummary],
  failures : Map[String, String],
) -> Unit {
  repo_scopes.clear()
  owner_scopes.clear()
  let seen : Map[String, Bool] = Map([])
  let scopes = ordered_scopes(tokens)
  // Tokens are fetched concurrently; results merge in scope order so the
  // default token keeps priority.
  let results = @async.all(
    scopes.map(scope => {
      async fn() {
        match tokens.get(scope) {
          Some(token) => Some(@github_api.list_accessible_repositories(token))
          None => None
        }
      }
    }),
  )
  for index, scope in scopes {
    guard results[index] is Some(result) else { continue }
    match result {
      Ok(repositories) => {
        @github_api.log(
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
        failures.set(scope, error)
        @github_api.log("github-repositories: scope=\{scope} \{error}")
      }
    }
  }
}

///|
/// Personal activity for one token, merged into the four lists.
pub async fn fetch_personal_activity(
  token : String,
  login : String,
  review_requests : Array[@github_api.ActivitySummary],
  assignments : Array[@github_api.ActivitySummary],
  mentions : Array[@github_api.ActivitySummary],
  subscriptions : Array[@github_api.ActivitySummary],
  incomplete? : Map[String, Bool] = Map([]),
) -> String? {
  let errors : Array[String] = []
  let results = @async.all([
    async fn() { @github_api.search_review_requests(token, login) },
    async fn() { @github_api.search_assignments(token, login) },
    async fn() { @github_api.search_mentions(token, login) },
    async fn() { @github_api.list_subscribed_issues(token) },
  ])
  let targets = [
    (review_requests, "review requests"),
    (assignments, "assignments"),
    (mentions, "mentions"),
    (subscriptions, "subscriptions"),
  ]
  for index, result in results {
    let (target, label) = targets[index]
    match result {
      Ok(listing) => {
        append_unique_activities(target, listing.items)
        if !listing.complete {
          incomplete.set("For you: \{label}", true)
        }
      }
      Err(error) => errors.push("\{label}: \{error}")
    }
  }
  @github_api.log(
    "github-personal-activity: review-requests=\{review_requests.length()} assignments=\{assignments.length()} mentions=\{mentions.length()} subscriptions=\{subscriptions.length()}",
  )
  if errors.is_empty() {
    None
  } else {
    Some(errors.join(", "))
  }
}

///|
/// Personal activity across every token. `on_start` and `on_done` run around
/// each token so the caller can report progress; failures are recorded per
/// scope.
pub async fn refresh_personal_activity(
  tokens : Map[String, String],
  review_requests : Array[@github_api.ActivitySummary],
  assignments : Array[@github_api.ActivitySummary],
  mentions : Array[@github_api.ActivitySummary],
  subscriptions : Array[@github_api.ActivitySummary],
  failures : Map[String, String],
  on_start : (String) -> Unit,
  on_done : () -> Unit,
  incomplete? : Map[String, Bool] = Map([]),
) -> Unit {
  // Tokens are fetched concurrently. Appends happen between suspension
  // points, so the shared lists stay consistent.
  let tasks = ordered_scopes(tokens).map(scope => {
    async fn() {
      guard tokens.get(scope) is Some(token) else { return }
      on_start(scope)
      defer on_done()
      fetch_scope_activity(
        scope, token, review_requests, assignments, mentions, subscriptions, failures,
        incomplete,
      )
    }
  })
  ignore(@async.all(tasks))
}

///|
async fn fetch_scope_activity(
  scope : String,
  token : String,
  review_requests : Array[@github_api.ActivitySummary],
  assignments : Array[@github_api.ActivitySummary],
  mentions : Array[@github_api.ActivitySummary],
  subscriptions : Array[@github_api.ActivitySummary],
  failures : Map[String, String],
  incomplete : Map[String, Bool],
) -> Unit {
  let login = match @credential_store.load_login_label(scope) {
    Some(login) => login
    None =>
      match @github_api.get_authenticated_user(token) {
        Ok(user) => {
          ignore(@credential_store.save_login_label(scope, user.login()))
          user.login()
        }
        Err(error) => {
          failures.set(scope, error)
          return
        }
      }
  }
  match
    fetch_personal_activity(
      token,
      login,
      review_requests,
      assignments,
      mentions,
      subscriptions,
      incomplete~,
    ) {
    Some(error) => {
      failures.set(scope, error)
      @github_api.log("github-personal-activity: scope=\{scope} \{error}")
    }
    None => ()
  }
}

///|
pub async fn fetch_repository_activity(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  repository : @domain.RepositoryRef,
  pull_requests : Array[@github_api.ActivitySummary],
  issues : Array[@github_api.ActivitySummary],
  incomplete? : Map[String, Bool] = Map([]),
) -> String? {
  guard resolve_token(
      tokens,
      repo_scopes,
      owner_scopes,
      repository.owner(),
      repository.name(),
    )
    is Some(token) else {
    return Some("no saved token can access \{repository.owner()}")
  }
  let errors : Array[String] = []
  let mut pull_request_count = 0
  let mut issue_count = 0
  match
    @github_api.list_open_pull_requests(
      token,
      repository.owner(),
      repository.name(),
    ) {
    Ok(listing) => {
      pull_request_count = listing.items.length()
      pull_requests.append(listing.items)
      if !listing.complete {
        incomplete.set("\{repository.key()} pull requests", true)
      }
    }
    Err(error) => errors.push(error)
  }
  match
    @github_api.list_open_issues(token, repository.owner(), repository.name()) {
    Ok(listing) => {
      issue_count = listing.items.length()
      issues.append(listing.items)
      if !listing.complete {
        incomplete.set("\{repository.key()} issues", true)
      }
    }
    Err(error) => errors.push(error)
  }
  @github_api.log(
    "github-activity: \{repository.key()} pull-requests=\{pull_request_count} issues=\{issue_count}",
  )
  if errors.is_empty() {
    None
  } else {
    // Pull requests and issues usually fail for the same reason.
    Some(errors[0])
  }
}

///|
/// Open pull requests and issues for every repository, fetched
/// concurrently. Failures are recorded per repository.
pub async fn fetch_watched_activity(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  repositories : Array[@domain.RepositoryRef],
  pull_requests : Array[@github_api.ActivitySummary],
  issues : Array[@github_api.ActivitySummary],
  failures : Map[String, String],
  on_done : () -> Unit,
  incomplete? : Map[String, Bool] = Map([]),
) -> Unit {
  let tasks = repositories.map(repository => {
    async fn() {
      match
        fetch_repository_activity(
          tokens,
          repo_scopes,
          owner_scopes,
          repository,
          pull_requests,
          issues,
          incomplete~,
        ) {
        Some(error) => {
          failures.set(repository.key(), error)
          @github_api.log("github-activity: \{repository.key()}: \{error}")
        }
        None => ()
      }
      on_done()
    }
  })
  ignore(@async.all(tasks, max_concurrent=6))
}

///|
/// Splits "https://github.com/owner/name/pull/12" or ".../issues/12" into
/// the repository and number.
pub fn parse_activity_url(
  url : String,
) -> Result[(@domain.RepositoryRef, Int), String] {
  let prefix = "https://github.com/"
  guard url.has_prefix(prefix) else {
    return Err(
      "expected a https://github.com/owner/repo/pull/N or /issues/N URL",
    )
  }
  let parts = url[prefix.length():]
    .to_owned()
    .split("/")
    .to_array()
    .map(part => part.to_owned())
  guard parts.length() >= 4 &&
    parts[0] != "" &&
    parts[1] != "" &&
    (parts[2] == "pull" || parts[2] == "issues") else {
    return Err(
      "expected a https://github.com/owner/repo/pull/N or /issues/N URL",
    )
  }
  let digits = parts[3].split("#").to_array()[0].to_owned()
  let mut number = 0
  for character in digits {
    guard character >= '0' && character <= '9' else {
      return Err("the URL does not end with an issue or pull request number")
    }
    number = number * 10 + (character.to_int() - '0'.to_int())
  }
  guard number > 0 else {
    return Err("the URL does not end with an issue or pull request number")
  }
  Ok((@domain.RepositoryRef::new(parts[0], parts[1]), number))
}

///|
/// The current state of one issue or pull request, using the token that
/// `resolve_token` picks for its repository.
pub async fn fetch_activity(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  url : String,
) -> Result[@github_api.ActivitySummary, String] {
  let (repository, number) = match parse_activity_url(url) {
    Ok(parsed) => parsed
    Err(error) => return Err(error)
  }
  guard resolve_token(
      tokens,
      repo_scopes,
      owner_scopes,
      repository.owner(),
      repository.name(),
    )
    is Some(token) else {
    return Err("no saved token can access \{repository.owner()}")
  }
  @github_api.get_activity(token, repository.owner(), repository.name(), number)
}

///|
/// Logins of every saved token, used to tell whether the viewer reviewed.
pub fn saved_logins() -> Array[String] {
  let logins : Array[String] = []
  for scope in @credential_store.list_scopes() {
    match @credential_store.load_login_label(scope) {
      Some(login) if !logins.contains(login) => logins.push(login)
      _ => ()
    }
  }
  logins
}

///|
/// A review request stays until the pull request closes or the viewer
/// submits a review, even after GitHub drops a team's request because a
/// teammate reviewed.
pub fn keeps_review_request(
  open : Bool,
  reviewers : Array[String],
  logins : Array[String],
) -> Bool {
  open && !reviewers.any(reviewer => logins.contains(reviewer))
}

///|
pub(all) struct ReviewFollowUp {
  /// Pull requests GitHub no longer lists that still need the viewer.
  pending : Array[@github_api.ActivitySummary]
  /// URLs to remember for the next refresh.
  kept_urls : Array[String]
}

///|
/// Remembers every review request seen in `current` and checks the ones
/// GitHub stopped listing. A request whose pull request cannot be read for
/// a transient reason is kept and checked again next time.
pub async fn follow_up_review_requests(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  kept_urls : Array[String],
  current : Array[@github_api.ActivitySummary],
  logins : Array[String],
) -> ReviewFollowUp {
  let current_urls = current.map(activity => activity.html_url())
  let missing = kept_urls.filter(url => !current_urls.contains(url))
  let checks = @async.all(
    missing.map(url => {
      async fn() -> (String, Bool, @github_api.ActivitySummary?) {
        guard parse_activity_url(url) is Ok((repository, number)) else {
          return (url, false, None)
        }
        guard resolve_token(
            tokens,
            repo_scopes,
            owner_scopes,
            repository.owner(),
            repository.name(),
          )
          is Some(token) else {
          return (url, true, None)
        }
        match
          @github_api.get_pull_request_state(
            token,
            repository.owner(),
            repository.name(),
            number,
          ) {
          Ok((activity, open)) => {
            if !open {
              return (url, false, None)
            }
            match
              @github_api.list_review_authors(
                token,
                repository.owner(),
                repository.name(),
                number,
              ) {
              Ok(reviewers) =>
                if keeps_review_request(open, reviewers, logins) {
                  (url, true, Some(activity))
                } else {
                  (url, false, None)
                }
              Err(error) => {
                @github_api.log("review-follow-up: \{url}: \{error}")
                (url, true, None)
              }
            }
          }
          Err(error) => {
            @github_api.log("review-follow-up: \{url}: \{error}")
            // A pull request that no longer exists or is out of reach is
            // dropped; other failures are retried next time.
            let keep = !(@github_api.classify_failure(error) is NotFound)
            (url, keep, None)
          }
        }
      }
    }),
    max_concurrent=6,
  )
  let dropped = checks.filter(check => !check.1).map(check => check.0)
  let next = kept_urls.filter(url => !dropped.contains(url))
  for url in current_urls {
    if !next.contains(url) {
      next.push(url)
    }
  }
  let pending : Array[@github_api.ActivitySummary] = []
  for check in checks {
    match check.2 {
      Some(activity) => pending.push(activity)
      None => ()
    }
  }
  { pending, kept_urls: next, }
}

///|
/// How far back review comments are read for mentions.
pub const REVIEW_MENTION_DAYS : Int = 30

///|
/// Midnight UTC `days` days before `now_ms` (milliseconds since the Unix
/// epoch), as GitHub's ISO 8601 `since` parameter.
pub fn utc_days_ago(now_ms : Int64, days : Int) -> String {
  let day = (now_ms / 86_400_000L).to_int() - days
  // Civil-from-days (Howard Hinnant), valid for dates after 1970.
  let z = day + 719468
  let era = z / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = yoe + era * 400 + (if m <= 2 { 1 } else { 0 })
  fn pad(value : Int) -> String {
    if value < 10 {
      "0\{value}"
    } else {
      value.to_string()
    }
  }

  "\{y}-\{pad(m)}-\{pad(d)}T00:00:00Z"
}

///|
/// Open pull requests in `repositories` whose review comments mention one
/// of `logins`, appended to `mentions`. GitHub's mention filter misses
/// these. Failures are returned per repository.
pub async fn fetch_review_comment_mentions(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  repositories : Array[@domain.RepositoryRef],
  logins : Array[String],
  since : String,
  mentions : Array[@github_api.ActivitySummary],
  incomplete? : Map[String, Bool] = Map([]),
) -> Map[String, String] {
  let failures : Map[String, String] = Map([])
  if logins.is_empty() {
    return failures
  }
  let tasks = repositories.map(repository => {
    async fn() -> Array[@github_api.ActivitySummary] {
      let owner = repository.owner()
      let name = repository.name()
      guard resolve_token(tokens, repo_scopes, owner_scopes, owner, name)
        is Some(token) else {
        return []
      }
      let listing = match
        @github_api.list_review_comment_mentions(
          token, owner, name, since, logins,
        ) {
        Ok(listing) => listing
        Err(error) => {
          failures.set(repository.key(), error)
          @github_api.log(
            "review-comment-mentions: \{repository.key()}: \{error}",
          )
          return []
        }
      }
      if !listing.complete {
        incomplete.set(
          "For you: review comment mentions in \{repository.key()}",
          true,
        )
      }
      let found : Array[@github_api.ActivitySummary] = []
      for number in listing.numbers {
        match @github_api.get_pull_request_state(token, owner, name, number) {
          Ok((activity, true)) => found.push(activity)
          Ok((_, false)) => ()
          Err(error) =>
            @github_api.log(
              "review-comment-mentions: \{repository.key()}#\{number}: \{error}",
            )
        }
      }
      found
    }
  })
  let results = @async.all(tasks, max_concurrent=6)
  for found in results {
    append_unique_activities(mentions, found)
  }
  @github_api.log("review-comment-mentions: mentions=\{mentions.length()}")
  failures
}
