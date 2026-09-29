///|
/// Text fields travel to the bridge as tab-separated lines.
fn safe_row_text(value : String) -> String {
  value
  .replace_all(old="\r", new=" ")
  .replace_all(old="\n", new=" ")
  .replace_all(old="\t", new=" ")
}

///|
fn flag(value : Bool) -> String {
  if value {
    "1"
  } else {
    "0"
  }
}

///|
fn activity_item(
  activity : @github_api.ActivitySummary,
  reasons : Array[String],
) -> @domain.ActivityItem {
  {
    url: activity.html_url(),
    repository: activity.repository(),
    number: activity.number(),
    title: activity.title(),
    author: activity.author(),
    updated_at: activity.updated_at(),
    kind: match activity.kind() {
      PullRequest => PullRequest
      Issue => Issue
    },
    draft: activity.is_draft(),
    reasons,
  }
}

///|
fn watched_items(
  activity_sets : Array[Array[@github_api.ActivitySummary]],
  muted : Map[String, Bool],
) -> Array[@domain.ActivityItem] {
  let items : Array[@domain.ActivityItem] = []
  let seen : Map[String, Bool] = Map([])
  for activities in activity_sets {
    for activity in activities {
      let url = activity.html_url()
      if muted.contains(url) || seen.contains(url) {
        continue
      }
      seen.set(url, true)
      items.push(activity_item(activity, []))
    }
  }
  items
}

///|
/// Personal items merged across the four sources, each with the reasons it
/// is included. `watched_only` drops items outside the watched set.
fn personal_items(
  review_requests : Array[@github_api.ActivitySummary],
  assignments : Array[@github_api.ActivitySummary],
  mentions : Array[@github_api.ActivitySummary],
  subscriptions : Array[@github_api.ActivitySummary],
  watched : Array[@domain.RepositoryRef],
  muted : Map[String, Bool],
  watched_only~ : Bool,
) -> Array[@domain.ActivityItem] {
  let items : Array[@domain.ActivityItem] = []
  let indices : Map[String, Int] = Map([])
  let sources = [
    (review_requests, "Review requested"),
    (assignments, "Assigned"),
    (mentions, "Mentioned"),
    (subscriptions, "Subscribed"),
  ]
  for source in sources {
    let (activities, reason) = source
    for activity in activities {
      let url = activity.html_url()
      if muted.contains(url) ||
        (
          watched_only &&
          !@domain.repository_is_watched(watched, activity.repository())
        ) {
        continue
      }
      match indices.get(url) {
        Some(index) =>
          if !items[index].reasons.contains(reason) {
            items[index].reasons.push(reason)
          }
        None => {
          indices.set(url, items.length())
          items.push(activity_item(activity, [reason]))
        }
      }
    }
  }
  items
}

///|
fn saved_items(
  activity_sets : Array[Array[@github_api.ActivitySummary]],
  saved : Map[String, Bool],
  muted : Map[String, Bool],
) -> Array[@domain.ActivityItem] {
  watched_items(activity_sets, muted).filter(item => saved.contains(item.url))
}

///|
fn unread_count(
  items : Array[@domain.ActivityItem],
  markers : Array[@domain.ReadMarker],
) -> Int {
  items
  .filter(item => !@domain.activity_is_read(markers, item.url, item.updated_at))
  .length()
}

///|
/// Serializes rows for the bridge. Item lines:
/// I url repo number kind draft title author date updated_at read saved
/// reasons nested show_repo fresh_age
fn serialize_rows(
  rows : Array[@domain.ActivityRow],
  show_repository : Bool,
  fresh_since : Map[String, Double],
  now : Double,
) -> String {
  rows
  .map(row => {
    match row {
      GroupHeader(repository) => "G\t\{repository}"
      Item(item, read~, saved~, nested~) => {
        let kind = if item.kind is PullRequest { "pr" } else { "issue" }
        let fresh_age = match fresh_since.get(item.url) {
          Some(since) => (now - since).to_string()
          None => "-1"
        }
        [
          "I",
          item.url,
          item.repository,
          item.number.to_string(),
          kind,
          flag(item.draft),
          safe_row_text(item.title),
          item.author,
          @domain.short_date(item.updated_at),
          item.updated_at,
          flag(read),
          flag(saved),
          item.reasons.join(","),
          flag(nested),
          flag(show_repository),
          fresh_age,
        ].join("\t")
      }
      Bundle(key~, repository~, author~, items~, expanded~, unread~) => {
        let summary = items
          .map(item => @domain.dependency_update_summary(item.title))
          .join(", ")
        [
          "B",
          key,
          repository,
          author,
          items.length().to_string(),
          safe_row_text(summary),
          flag(expanded),
          unread.to_string(),
        ].join("\t")
      }
    }
  })
  .join("\n")
}

///|
fn repositories_text(repositories : Array[@domain.RepositoryRef]) -> String {
  repositories.map(repository => repository.key()).join("\n")
}

///|
/// Suggestions with review requests for the viewer are listed first.
fn suggestions_text(
  suggestions : Array[@github_api.RepositorySummary],
  watched : Array[@domain.RepositoryRef],
  review_requests : Array[@github_api.ActivitySummary],
) -> String {
  let review_counts : Map[String, Int] = Map([])
  for activity in review_requests {
    let key = activity.repository().to_lower()
    review_counts.set(key, review_counts.get(key).unwrap_or(0) + 1)
  }
  let rows = suggestions.map(repository => {
    let name = repository.full_name()
    let reviews = review_counts.get(name.to_lower()).unwrap_or(0)
    (
      reviews,
      [
        name,
        flag(repository.is_private()),
        flag(repository.is_archived()),
        flag(@domain.repository_is_watched(watched, name)),
        reviews.to_string(),
      ].join("\t"),
    )
  })
  let with_reviews = rows.filter(row => row.0 > 0)
  let others = rows.filter(row => row.0 == 0)
  with_reviews.append(others)
  with_reviews.map(row => row.1).join("\n")
}

///|
fn credentials_text(problems : Map[String, String]) -> String {
  @credential_store.list_scopes()
  .map(scope => {
    let login = @credential_store.load_login_label(scope).unwrap_or("")
    let problem = problems.get(scope).unwrap_or("")
    "\{scope}\t\{login}\t\{safe_row_text(problem)}"
  })
  .join("\n")
}

///|
fn synced_label(last_synced : Double?, now : Double) -> String {
  match last_synced {
    None => "Not synced yet"
    Some(time) => {
      let seconds = now - time
      if seconds < 60.0 {
        "Synced just now"
      } else if seconds < 3600.0 {
        "Synced \{(seconds / 60.0).to_int()} min ago"
      } else {
        "Synced \{(seconds / 3600.0).to_int()} h ago"
      }
    }
  }
}

///|
priv struct Banner {
  kind : String
  key : String
  title : String
  body : String
  action : String
}

///|
fn banners_text(banners : Array[Banner]) -> String {
  banners
  .map(banner => {
    [
      banner.kind,
      banner.key,
      safe_row_text(banner.title),
      safe_row_text(banner.body),
      banner.action,
    ].join("\t")
  })
  .join("\n")
}

///|
fn scope_label(scope : String) -> String {
  if scope == "default" {
    "default"
  } else {
    scope
  }
}

///|
fn failure_reason(message : String) -> String {
  match @github_api.classify_failure(message) {
    NotFound => "not found or not accessible with its token"
    Unauthorized => "the token was rejected"
    Forbidden | RateLimited(_) => "access was denied"
    Network => "GitHub could not be reached"
    Other => message
  }
}

///|
/// Banners describing the last fetches: token problems per account, rate
/// limits, network failures, and repositories that failed.
fn problem_banners(
  scope_failures : Map[String, String],
  broken_scopes : Map[String, String],
  repository_failures : Map[String, String],
  watched_count : Int,
  has_data : Bool,
  dismissed : Map[String, Bool],
) -> Array[Banner] {
  let banners : Array[Banner] = []
  for scope, message in broken_scopes {
    banners.push({
      kind: "danger",
      key: "token:\{scope}",
      title: "Couldn't read the \{scope_label(scope)} token from the Keychain.",
      body: "Add it again to keep loading its repositories.",
      action: "Replace token",
    })
    ignore(message)
  }
  let mut rate_reset : Int64? = None
  let mut network = false
  let mut forbidden = false
  let all_failures : Array[String] = []
  for _, message in scope_failures {
    all_failures.push(message)
  }
  for _, message in repository_failures {
    all_failures.push(message)
  }
  for message in all_failures {
    match @github_api.classify_failure(message) {
      RateLimited(epoch) => rate_reset = Some(epoch)
      Network => network = true
      Forbidden => forbidden = true
      _ => ()
    }
  }
  for scope, message in scope_failures {
    if @github_api.classify_failure(message) is Unauthorized {
      banners.push({
        kind: "danger",
        key: "token:\{scope}",
        title: "GitHub rejected the \{scope_label(scope)} token.",
        body: "It may have expired or been revoked. Activity that uses it is not updating.",
        action: "Replace token",
      })
    }
  }
  match rate_reset {
    Some(epoch) =>
      banners.push({
        kind: "warning",
        key: "rate-limit",
        title: "GitHub API rate limit reached.",
        body: "Auto refresh pauses and retries at \{github_client_imgui_format_clock(epoch)}.",
        action: "",
      })
    None =>
      if forbidden {
        banners.push({
          kind: "warning",
          key: "forbidden",
          title: "GitHub denied some requests.",
          body: "A token may lack access, or the rate limit was reached.",
          action: "Retry",
        })
      }
  }
  if network && has_data {
    banners.push({
      kind: "warning",
      key: "network",
      title: "Can't reach GitHub.",
      body: "Showing results from the last successful refresh.",
      action: "Retry",
    })
  }
  let failed : Array[String] = []
  for repository, message in repository_failures {
    match @github_api.classify_failure(message) {
      Network | RateLimited(_) | Unauthorized => ()
      _ => failed.push("\{repository}: \{failure_reason(message)}")
    }
  }
  if !failed.is_empty() {
    let noun = if watched_count == 1 { "repository" } else { "repositories" }
    banners.push({
      kind: "warning",
      key: "repositories",
      title: "\{failed.length()} of \{watched_count} \{noun} couldn't be refreshed.",
      body: failed.join("; ") + ". Other results are up to date.",
      action: "Retry",
    })
  }
  banners.filter(banner => !dismissed.contains(banner.key))
}

///|
/// Review requests in repositories the viewer does not watch.
fn hidden_review_banners(
  review_requests : Array[@github_api.ActivitySummary],
  watched : Array[@domain.RepositoryRef],
  muted : Map[String, Bool],
  dismissed : Map[String, Bool],
) -> Array[Banner] {
  let items = review_requests
    .filter(activity => !muted.contains(activity.html_url()))
    .map(activity => activity_item(activity, ["Review requested"]))
  @domain.unwatched_repositories(items, watched)
  .map(entry => {
    let (repository, count) = entry
    let noun = if count == 1 {
      "1 review request is"
    } else {
      "\{count} review requests are"
    }
    {
      kind: "info",
      key: "watch:\{repository}",
      title: "\{noun} hidden because \{repository} is not watched.",
      body: "",
      action: "Watch repository",
    }
  })
  .filter(banner => !dismissed.contains(banner.key))
}
