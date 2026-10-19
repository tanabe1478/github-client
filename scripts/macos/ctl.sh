#!/usr/bin/env bash
# Sends a command to a running MoonBit GitHub Client through its control file.
# The app polls ~/.config/moonbit-github-client/control.txt about twice per
# second and dispatches each line through the same action handlers the UI uses.
# Commands run in the background: the window is not raised, focus is not
# stolen, and the mouse cursor is not moved.
set -euo pipefail

CONTROL_FILE="$HOME/.config/moonbit-github-client/control.txt"

usage() {
  cat >&2 <<'EOF'
usage: ctl.sh <command> [args...]

commands:
  open <url>            open the activity URL in the browser
  done <url>            mark the activity done / restore it to the inbox
  save <url>            save / unsave the activity
  unsub <url>           mute the activity locally (no GitHub API call)
  nav <page>            inbox|for-you|releases|saved|pull-requests|issues|repositories|settings
  watch <owner/repo>    register a watched repository
  unwatch <owner/repo>  stop watching a repository
  watch-kinds <owner/repo> <kinds>
                        what a watched repository brings in, comma separated:
                        pull-requests,issues,releases,for-you
  release-notify <owner/repo> all|major-minor|major|off
                        which releases of a watched repository notify
  watch-base <owner/repo>
                        toggle whether a watched repository is a base
                        project whose dependencies are read
  project-add <owner/name|url|directory>
                        add base projects; a directory adds every
                        GitHub repository found in it
  project-remove <owner/name>
                        remove a base project
  project-rescan        read every base project again
  npm-mirror-add <url>  treat a base project's npm registry as a mirror of
                        npm, so its packages are looked up on npm
  npm-mirror-remove <url>
                        stop treating it as a mirror
  suggest-watches       open "Watch what your base projects use"
  suggest-watch <owner/name,...|all>
                        watch suggested repositories for their releases
  project-follow <owner/name>
                        use the new name of a renamed base project
  related-only 0|1      Releases "Related only" filter
  project <owner/name|all>
                        Releases base project filter
  why <release url>     open "Why it is related" for a release row
  refresh               refresh watched activity
  refresh-for-you       refresh personal activity only
  refresh-all           refresh watched and personal activity
  auto-refresh          run the auto refresh now; it posts notifications
  notification-test     post a sample notification, to check how the app
                        posts them
  show-done 0|1         toggle the "Show done" filter
  kind all|pr|issue     Inbox kind filter
  repo <owner/repo|all> Inbox repository filter
  search [text]         Inbox text filter (empty clears it)
  reason <reason|all>   For you reason filter, e.g. "reason Review requested"
  expand <key>          show or hide a dependency bundle (owner/repo|author)
  menu <url>            open the More actions menu for a row
  undo                  undo the last action shown in the snackbar
  cancel                cancel the running refresh
  token-dialog          open the personal access token dialog
  quit                  close the app

examples:
  ctl.sh nav for-you
  ctl.sh save https://github.com/owner/repo/pull/123
  ctl.sh done https://github.com/owner/repo/issues/123
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

case "$1" in
  open|done|save|unsub|unsubscribe|nav|watch|unwatch|watch-base|kind|repo|reason|expand|menu|project-add|project-remove|project-follow|npm-mirror-add|npm-mirror-remove|suggest-watch|related-only|project|why)
    if [[ $# -lt 2 ]]; then
      echo "$1 requires an argument" >&2
      usage
    fi
    ;;
  watch-kinds|release-notify)
    if [[ $# -lt 3 ]]; then
      echo "$1 requires a repository and a value" >&2
      usage
    fi
    ;;
  refresh|refresh-for-you|refresh-all|auto-refresh|notification-test|undo|cancel|token-dialog|search|quit|project-rescan|suggest-watches)
    ;;
  show-done)
    ;;
  *)
    echo "unknown command: $1" >&2
    usage
    ;;
esac

# One invocation writes one line. Repeat calls to queue more commands; each
# file is consumed and removed by the app on its next poll.
printf '%s\n' "$*" > "$CONTROL_FILE"
echo "queued: $*"
