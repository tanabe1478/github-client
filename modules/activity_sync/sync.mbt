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
      Ok(items) => append_unique_activities(target, items)
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
      token, login, review_requests, assignments, mentions, subscriptions,
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
    Ok(items) => {
      pull_request_count = items.length()
      pull_requests.append(items)
    }
    Err(error) => errors.push(error)
  }
  match
    @github_api.list_open_issues(token, repository.owner(), repository.name()) {
    Ok(items) => {
      issue_count = items.length()
      issues.append(items)
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
) -> Unit {
  let tasks = repositories.map(repository => {
    async fn() {
      match
        fetch_repository_activity(
          tokens, repo_scopes, owner_scopes, repository, pull_requests, issues,
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
