///|
/// A parsed command line.
priv struct Invocation {
  command : String
  arguments : Array[String]
  json : Bool
  verbose : Bool
  all : Bool
  kind : String
  repository : String
  query : String
  reason : String
  /// `watch` only: the kinds to bring in and the release notification;
  /// empty keeps them.
  kinds : String
  release_notify : String
  /// `releases` only: keep releases related to a base project, optionally
  /// one project.
  related : Bool
  project : String
}

///|
let usage : String =
  #|usage: ghclient <command> [arguments] [options]
  #|
  #|Activity, fetched from GitHub on every call:
  #|  inbox      open pull requests and issues in watched repositories
  #|             --kind all|pr|issue  --repo OWNER/NAME  --query TEXT  --all
  #|  for-you    review requests, assignments, mentions, and subscriptions
  #|             in watched repositories   --reason REASON  --all
  #|  releases   releases of watched repositories that choose them
  #|             --repo OWNER/NAME  --query TEXT  --all
  #|             --related  --project OWNER/NAME   (base projects)
  #|  saved      items saved for later
  #|
  #|Triage, stored locally (a running app picks the change up):
  #|  done <url>...      mark done at the item's current revision
  #|  undone <url>...    move back to the inbox
  #|  save <url>...      save for later        unsave <url>...
  #|  mute <url>...      hide everywhere       unmute <url>...
  #|
  #|Repositories and accounts:
  #|  repos                    watched repositories and what each brings in
  #|  watch <owner/name>...    start watching, or change what it brings in
  #|             --kinds pull-requests,issues,releases,for-you
  #|             --release-notify all|major-minor|major|off
  #|  unwatch <owner/name>...  stop watching
  #|  accounts                 saved tokens (scope and login, never the token)
  #|  projects                 base projects and what each uses
  #|  project-add <owner/name|directory>...
  #|                           add base projects; a directory adds every
  #|                           GitHub repository found under it
  #|  project-remove <owner/name>...
  #|  watch-candidates         repositories the base projects depend on and
  #|                           you do not watch; watch them with
  #|                           watch <owner/name> --kinds releases
  #|  npm-mirror-add <url>...  treat an npm registry as a mirror of the public
  #|                           one, so packages a base project gets from it
  #|                           are looked up on registry.npmjs.org
  #|  npm-mirror-remove <url>...
  #|
  #|Options:
  #|  --json   print JSON on stdout
  #|  --all    include done items in activity lists
  #|  --verbose  print each GitHub request on stderr
  #|  --help   show this help
  #|
  #|Reasons: "Review requested", "Assigned", "Mentioned", "Subscribed".
  #|Exit codes: 0 success, 1 failure, 2 usage error, 3 finished but some
  #|GitHub requests failed (see "errors" in the JSON output).
  #|

///|
let commands : Array[String] = [
  "inbox", "for-you", "releases", "saved", "done", "undone", "save", "unsave", "mute",
  "unmute", "repos", "watch", "unwatch", "accounts", "projects", "project-add", "project-remove",
  "watch-candidates", "npm-mirror-add", "npm-mirror-remove", "help",
]

///|
/// Commands that act on one or more arguments.
let commands_with_arguments : Array[String] = [
  "done", "undone", "save", "unsave", "mute", "unmute", "watch", "unwatch", "project-add",
  "project-remove", "npm-mirror-add", "npm-mirror-remove",
]

///|
fn parse_invocation(args : Array[String]) -> Result[Invocation, String] {
  let positional : Array[String] = []
  let mut json = false
  let mut verbose = false
  let mut all = false
  let mut kind = "all"
  let mut repository = ""
  let mut query = ""
  let mut reason = ""
  let mut kinds = ""
  let mut release_notify = ""
  let mut related = false
  let mut project = ""
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    let value = fn() -> Result[String, String] {
      if index + 1 < args.length() {
        index += 1
        Ok(args[index])
      } else {
        Err("\{arg} needs a value")
      }
    }
    match arg {
      "--json" => json = true
      "--verbose" => verbose = true
      "--all" => all = true
      "--help" | "-h" => return Ok(help_invocation())
      "--kind" =>
        match value() {
          Ok("all" | "pr" | "issue" as chosen) => kind = chosen
          Ok(other) =>
            return Err("--kind must be all, pr, or issue, not \{other}")
          Err(error) => return Err(error)
        }
      "--repo" =>
        match value() {
          Ok(chosen) => repository = chosen
          Err(error) => return Err(error)
        }
      "--query" =>
        match value() {
          Ok(chosen) => query = chosen
          Err(error) => return Err(error)
        }
      "--reason" =>
        match value() {
          Ok(
            "Review requested"
            | "Assigned"
            | "Mentioned"
            | "Subscribed" as chosen
          ) => reason = chosen
          Ok(other) => return Err("unknown reason: \{other}")
          Err(error) => return Err(error)
        }
      "--related" => related = true
      "--project" =>
        match value() {
          Ok(chosen) => project = chosen
          Err(error) => return Err(error)
        }
      "--kinds" =>
        match value() {
          Ok(chosen) =>
            match @domain.WatchOptions::default().with_kinds(chosen) {
              Ok(_) => kinds = chosen
              Err(error) => return Err(error)
            }
          Err(error) => return Err(error)
        }
      "--release-notify" =>
        match value() {
          Ok(chosen) =>
            if @domain.ReleaseNotify::parse(chosen) is Some(_) {
              release_notify = chosen
            } else {
              return Err(
                "--release-notify must be all, major-minor, major, or off, not \{chosen}",
              )
            }
          Err(error) => return Err(error)
        }
      _ =>
        if arg.has_prefix("--") {
          return Err("unknown option: \{arg}")
        } else {
          positional.push(arg)
        }
    }
    index += 1
  }
  guard positional.length() > 0 else { return Ok(help_invocation()) }
  let command = positional[0]
  guard commands.contains(command) else {
    return Err("unknown command: \{command}")
  }
  let arguments = positional[1:].to_owned()
  if commands_with_arguments.contains(command) && arguments.is_empty() {
    return Err("\{command} needs at least one argument")
  }
  if !commands_with_arguments.contains(command) && !arguments.is_empty() {
    return Err("\{command} takes no arguments")
  }
  if (kinds != "" || release_notify != "") && command != "watch" {
    return Err("--kinds and --release-notify apply to watch only")
  }
  if (related || project != "") && command != "releases" {
    return Err("--related and --project apply to releases only")
  }
  Ok({
    command,
    arguments,
    json,
    verbose,
    all,
    kind,
    repository,
    query,
    reason,
    kinds,
    release_notify,
    related,
    project,
  })
}

///|
fn help_invocation() -> Invocation {
  {
    command: "help",
    arguments: [],
    json: false,
    verbose: false,
    all: false,
    kind: "all",
    repository: "",
    query: "",
    reason: "",
    kinds: "",
    release_notify: "",
    related: false,
    project: "",
  }
}

///|
fn Invocation::filter(self : Invocation) -> @domain.ActivityFilter {
  {
    kind: match self.kind {
      "pr" => PullRequestsOnly
      "issue" => IssuesOnly
      _ => AllKinds
    },
    repository: self.repository,
    query: self.query,
    reason: self.reason,
    show_done: self.all,
  }
}
