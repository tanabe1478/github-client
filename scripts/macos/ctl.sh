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
  nav <page>            inbox|for-you|saved|pull-requests|issues|repositories|settings
  watch <owner/repo>    register a watched repository
  refresh               refresh watched and personal activity
  refresh-for-you       refresh personal activity only
  show-done 0|1         toggle the "Show done" filter
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
  open|done|save|unsub|unsubscribe|nav|watch)
    if [[ $# -lt 2 ]]; then
      echo "$1 requires an argument" >&2
      usage
    fi
    ;;
  refresh|refresh-for-you|quit)
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
