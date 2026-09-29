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
  #|  saved      items saved for later
  #|
  #|Triage, stored locally (a running app picks the change up):
  #|  done <url>...      mark done at the item's current revision
  #|  undone <url>...    move back to the inbox
  #|  save <url>...      save for later        unsave <url>...
  #|  mute <url>...      hide everywhere       unmute <url>...
  #|
  #|Repositories and accounts:
  #|  repos                    watched repositories
  #|  watch <owner/name>...    start watching
  #|  unwatch <owner/name>...  stop watching
  #|  accounts                 saved tokens (scope and login, never the token)
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
  "inbox", "for-you", "saved", "done", "undone", "save", "unsave", "mute", "unmute",
  "repos", "watch", "unwatch", "accounts", "help",
]

///|
/// Commands that act on one or more arguments.
let commands_with_arguments : Array[String] = [
  "done", "undone", "save", "unsave", "mute", "unmute", "watch", "unwatch",
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
