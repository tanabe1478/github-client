///|
/// Which releases of a watched repository post a notification.
pub(all) enum ReleaseNotify {
  AllReleases
  MajorAndMinor
  MajorOnly
  NoReleases
} derive(Eq, Debug)

///|
/// The name used in `repositories.txt`, the control file, and ghclient.
pub fn ReleaseNotify::name(self : ReleaseNotify) -> String {
  match self {
    AllReleases => "all"
    MajorAndMinor => "major-minor"
    MajorOnly => "major"
    NoReleases => "off"
  }
}

///|
pub fn ReleaseNotify::parse(value : String) -> ReleaseNotify? {
  match value {
    "all" => Some(AllReleases)
    "major-minor" => Some(MajorAndMinor)
    "major" => Some(MajorOnly)
    "off" => Some(NoReleases)
    _ => None
  }
}

///|
/// What a watched repository brings into the lists.
pub(all) struct WatchOptions {
  pull_requests : Bool
  issues : Bool
  releases : Bool
  for_you : Bool
  release_notify : ReleaseNotify
} derive(Eq, Debug)

///|
/// Pull requests, issues, and For you: what watching meant before the
/// options existed.
pub fn WatchOptions::default() -> WatchOptions {
  {
    pull_requests: true,
    issues: true,
    releases: false,
    for_you: true,
    release_notify: MajorAndMinor,
  }
}

///|
pub let watch_kind_names : Array[String] = [
  "pull-requests", "issues", "releases", "for-you",
]

///|
/// The chosen kinds, comma separated in `watch_kind_names` order.
pub fn WatchOptions::kinds_text(self : WatchOptions) -> String {
  let kinds : Array[String] = []
  if self.pull_requests {
    kinds.push("pull-requests")
  }
  if self.issues {
    kinds.push("issues")
  }
  if self.releases {
    kinds.push("releases")
  }
  if self.for_you {
    kinds.push("for-you")
  }
  kinds.join(",")
}

///|
/// Options with the kinds in `text` (comma separated names from
/// `watch_kind_names`), keeping the release notification.
pub fn WatchOptions::with_kinds(
  self : WatchOptions,
  text : String,
) -> Result[WatchOptions, String] {
  let mut options = {
    ..self,
    pull_requests: false,
    issues: false,
    releases: false,
    for_you: false,
  }
  for raw in text.split(",") {
    let kind = raw.trim().to_owned()
    options = match kind {
      "" => options
      "pull-requests" => { ..options, pull_requests: true, }
      "issues" => { ..options, issues: true, }
      "releases" => { ..options, releases: true, }
      "for-you" => { ..options, for_you: true, }
      _ =>
        return Err("unknown kind \{kind}; use \{watch_kind_names.join(", ")}")
    }
  }
  Ok(options)
}

///|
/// Options with one kind switched on or off.
pub fn WatchOptions::toggle(self : WatchOptions, kind : String) -> WatchOptions {
  match kind {
    "pull-requests" => { ..self, pull_requests: !self.pull_requests, }
    "issues" => { ..self, issues: !self.issues, }
    "releases" => { ..self, releases: !self.releases, }
    "for-you" => { ..self, for_you: !self.for_you, }
    _ => self
  }
}

///|
/// The options stored for `key`, or the defaults.
pub fn watch_options_for(
  options : Map[String, WatchOptions],
  key : String,
) -> WatchOptions {
  options.get(key).unwrap_or(WatchOptions::default())
}

///|
/// Watched repositories whose options include For you.
pub fn for_you_repositories(
  repositories : Array[RepositoryRef],
  options : Map[String, WatchOptions],
) -> Array[RepositoryRef] {
  repositories.filter(repository => {
    watch_options_for(options, repository.key()).for_you
  })
}

///|
pub(all) enum ReleaseLevel {
  Major
  Minor
  Patch
} derive(Eq, Debug)

///|
/// The level of a release from its tag: `x.0.0` is major, `x.y.0` minor,
/// anything else patch. A tag without a version number counts as minor, so
/// the default notification does not miss it.
pub fn release_level(tag : String) -> ReleaseLevel {
  // Skip a prefix such as "v" or "pnpm@".
  let numbers : Array[Int] = []
  let mut current = -1
  for character in tag {
    if character >= '0' && character <= '9' {
      let digit = character.to_int() - '0'.to_int()
      current = if current < 0 { digit } else { current * 10 + digit }
    } else if current >= 0 {
      numbers.push(current)
      current = -1
      if character != '.' || numbers.length() == 3 {
        break
      }
    }
  }
  if current >= 0 && numbers.length() < 3 {
    numbers.push(current)
  }
  guard numbers.length() >= 2 else { return Minor }
  let minor = numbers[1]
  let patch = if numbers.length() >= 3 { numbers[2] } else { 0 }
  if minor == 0 && patch == 0 {
    Major
  } else if patch == 0 {
    Minor
  } else {
    Patch
  }
}

///|
/// Whether a release posts a notification. Pre-releases notify only when
/// every release does.
pub fn ReleaseNotify::notifies(
  self : ReleaseNotify,
  level : ReleaseLevel,
  prerelease~ : Bool,
) -> Bool {
  match self {
    AllReleases => true
    NoReleases => false
    _ if prerelease => false
    MajorAndMinor => level is (Major | Minor)
    MajorOnly => level is Major
  }
}

///|
/// Whether `next` chooses a kind that `self` did not, so the repository
/// needs a fetch.
pub fn WatchOptions::gains(self : WatchOptions, next : WatchOptions) -> Bool {
  (next.pull_requests && !self.pull_requests) ||
  (next.issues && !self.issues) ||
  (next.releases && !self.releases) ||
  (next.for_you && !self.for_you)
}
