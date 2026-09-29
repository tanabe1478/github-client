///|
priv struct ControlCommand {
  action : Int
  url : String
  updated_at : String
  repository : String
  key : String
}

///|
fn control_command(action : Int) -> ControlCommand {
  { action, url: "", updated_at: "", repository: "", key: "", }
}

///|
fn find_activity(
  url : String,
  activity_sets : Array[Array[@github_api.ActivitySummary]],
) -> @github_api.ActivitySummary? {
  for activities in activity_sets {
    for activity in activities {
      if activity.html_url() == url {
        return Some(activity)
      }
    }
  }
  None
}

///|
/// Reads the control file, deletes it, and queues each command. Commands
/// that only change view state apply at once.
fn poll_control_commands(
  control_path : String,
  queue : Array[ControlCommand],
  activity_sets : Array[Array[@github_api.ActivitySummary]],
) -> Unit {
  if !@fs.path_exists(control_path) {
    return
  }
  let source = @fs.read_file_to_string(control_path, encoding="utf8") catch {
    _ => return
  }
  @fs.remove_file(control_path) catch {
    _ => ()
  }
  for
    raw_line in source.replace_all(old="\r\n", new="\n").split("\n").to_array() {
    let line = raw_line.trim().to_owned()
    if line == "" {
      continue
    }
    let parts = line.split(" ").to_array().map(part => part.to_owned())
    let argument = if parts.length() > 1 { parts[1] } else { "" }
    let rest = match line.find(" ") {
      Some(index) => line[index + 1:].trim().to_owned()
      None => ""
    }
    match parts[0] {
      "open" if argument != "" =>
        queue.push({ ..control_command(4), url: argument, })
      "done" if argument != "" =>
        match find_activity(argument, activity_sets) {
          Some(activity) =>
            queue.push({
              ..control_command(6),
              url: argument,
              updated_at: activity.updated_at(),
            })
          None => println("control: done target not found: \{argument}")
        }
      "save" if argument != "" =>
        queue.push({ ..control_command(22), url: argument, })
      "unsub" | "unsubscribe" if argument != "" =>
        queue.push({ ..control_command(23), url: argument, })
      "nav" => {
        let action = match argument {
          "inbox" => 10
          "repositories" => 11
          "settings" => 14
          "for-you" => 15
          "saved" => 16
          "pull-requests" => {
            github_client_imgui_set_view_kind(1)
            10
          }
          "issues" => {
            github_client_imgui_set_view_kind(2)
            10
          }
          _ => 0
        }
        if action != 0 {
          queue.push(control_command(action))
        }
      }
      "watch" if argument != "" =>
        queue.push({ ..control_command(2), repository: argument, })
      "unwatch" if argument != "" =>
        queue.push({ ..control_command(5), repository: argument, })
      "refresh" => queue.push(control_command(20))
      "refresh-for-you" => queue.push(control_command(21))
      "refresh-all" => queue.push(control_command(32))
      "show-done" =>
        github_client_imgui_set_show_done(if argument == "0" { 0 } else { 1 })
      "kind" =>
        github_client_imgui_set_view_kind(
          match argument {
            "pr" | "pull-requests" => 1
            "issue" | "issues" => 2
            _ => 0
          },
        )
      "repo" =>
        github_client_imgui_set_view_repository(
          if argument == "all" {
            ""
          } else {
            argument
          },
        )
      "search" => github_client_imgui_set_view_query(rest)
      "reason" =>
        github_client_imgui_set_view_reason(
          if rest == "all" {
            ""
          } else {
            rest
          },
        )
      "expand" if rest != "" =>
        queue.push({ ..control_command(24), key: rest, })
      "menu" if argument != "" =>
        match find_activity(argument, activity_sets) {
          Some(activity) =>
            github_client_imgui_open_row_menu(argument, activity.repository())
          None => println("control: menu target not found: \{argument}")
        }
      "undo" => queue.push(control_command(26))
      "cancel" => queue.push(control_command(27))
      "token-dialog" => queue.push(control_command(1))
      "quit" => queue.push(control_command(99))
      _ => println("control: unknown command \{line}")
    }
  }
}
