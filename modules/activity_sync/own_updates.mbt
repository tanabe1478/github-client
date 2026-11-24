///|
/// Seconds since the Unix epoch for GitHub's `YYYY-MM-DDTHH:MM:SSZ`.
fn utc_seconds(value : String) -> Int64? {
  let digits : Array[Int] = []
  for character in value {
    if character >= '0' && character <= '9' && digits.length() < 14 {
      digits.push(character.to_int() - '0'.to_int())
    }
  }
  guard digits.length() == 14 else { return None }
  fn number(from : Int, count : Int) -> Int {
    let mut total = 0
    for index = from; index < from + count; index = index + 1 {
      total = total * 10 + digits[index]
    }
    total
  }

  let year = number(0, 4)
  let month = number(4, 2)
  let day = number(6, 2)
  // Days-from-civil (Howard Hinnant), the inverse of utc_days_ago.
  let y = if month <= 2 { year - 1 } else { year }
  let era = y / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  let days = era * 146097 + doe - 719468
  Some(
    days.to_int64() * 86400L +
    (number(8, 2) * 3600 + number(10, 2) * 60 + number(12, 2)).to_int64(),
  )
}

///|
/// GitHub can move `updated_at` a few seconds away from the event that
/// caused it.
const UPDATE_SLACK_SECONDS : Int64 = 5L

///|
/// Whether every change after `since` on an item updated at `updated_at`
/// was made by one of `logins`, so a notification would only repeat the
/// viewer's own action back to them. `since` is the revision last seen;
/// without one the item is new, and it counts as the viewer's only when
/// the viewer opened it. An update that no listed change explains, or a
/// change by an unknown user, is never the viewer's own.
pub fn changed_only_by(
  entries : Array[@github_api.TimelineEntry],
  since : String?,
  author : String,
  updated_at : String,
  logins : Array[String],
) -> Bool {
  let changes = match since {
    Some(seen) => entries.filter(entry => entry.at > seen)
    None => {
      if !logins.contains(author) {
        return false
      }
      entries
    }
  }
  if changes.any(entry => entry.actor == "" || !logins.contains(entry.actor)) {
    return false
  }
  if changes.is_empty() {
    return since is None
  }
  let mut latest = changes[0].at
  for entry in changes {
    if entry.at > latest {
      latest = entry.at
    }
  }
  match (utc_seconds(updated_at), utc_seconds(latest)) {
    (Some(updated), Some(changed)) => updated <= changed + UPDATE_SLACK_SECONDS
    _ => false
  }
}

///|
/// Reads the timeline of an issue or pull request and tells whether its
/// latest update is the viewer's own (see `changed_only_by`). Commits are
/// attributed through the pull request's commit list. Anything that cannot
/// be read counts as not the viewer's, so the update still notifies.
pub async fn updated_only_by(
  tokens : Map[String, String],
  repo_scopes : Map[String, String],
  owner_scopes : Map[String, String],
  activity : @github_api.ActivitySummary,
  since : String?,
  logins : Array[String],
) -> Bool {
  if logins.is_empty() || activity.kind() is Release {
    return false
  }
  let url = activity.html_url()
  guard parse_activity_url(url) is Ok((repository, number)) else {
    return false
  }
  guard resolve_token(
      tokens,
      repo_scopes,
      owner_scopes,
      repository.owner(),
      repository.name(),
    )
    is Some(token) else {
    return false
  }
  let entries = match
    @github_api.list_timeline(
      token,
      repository.owner(),
      repository.name(),
      number,
    ) {
    Ok((entries, true)) => entries
    Ok((_, false)) => return false
    Err(error) => {
      @github_api.log("own-update: \{url}: \{error}")
      return false
    }
  }
  let unattributed = entries.any(entry => {
    entry.commit != "" &&
    (match since {
      Some(seen) => entry.at > seen
      None => true
    })
  })
  if unattributed && activity.kind() is PullRequest {
    match
      @github_api.list_pull_request_commit_authors(
        token,
        repository.owner(),
        repository.name(),
        number,
      ) {
      Ok(authors) =>
        for index, entry in entries {
          if entry.commit != "" {
            entries[index] = {
              ..entry,
              actor: authors.get(entry.commit).unwrap_or(""),
            }
          }
        }
      Err(error) => {
        @github_api.log("own-update: \{url}: \{error}")
        return false
      }
    }
  }
  changed_only_by(
    entries,
    since,
    activity.author(),
    activity.updated_at(),
    logins,
  )
}
