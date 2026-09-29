///|
pub fn activity_item(
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
pub fn watched_items(
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
pub fn personal_items(
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
pub fn saved_items(
  activity_sets : Array[Array[@github_api.ActivitySummary]],
  saved : Map[String, Bool],
  muted : Map[String, Bool],
) -> Array[@domain.ActivityItem] {
  watched_items(activity_sets, muted).filter(item => saved.contains(item.url))
}

///|
pub fn unread_count(
  items : Array[@domain.ActivityItem],
  markers : Array[@domain.ReadMarker],
) -> Int {
  items
  .filter(item => !@domain.activity_is_read(markers, item.url, item.updated_at))
  .length()
}
