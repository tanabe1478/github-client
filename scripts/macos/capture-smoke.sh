#!/usr/bin/env bash
# Captures the MoonBit GitHub Client window without disturbing the user.
# Navigation and actions are sent through the app's control file
# (see scripts/macos/ctl.sh); the window is never raised or focused and the
# cursor is never moved. Screenshots use `screencapture -l`, which works on
# background and occluded windows.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="$REPO_ROOT/artifacts/macos/inbox.png"
PAGE=""
CMDS=()
CONTROL_FILE="$HOME/.config/moonbit-github-client/control.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output|-o)
      OUTPUT="$2"
      shift 2
      ;;
    --page|-p)
      PAGE="$2"
      shift 2
      ;;
    --cmd)
      CMDS+=("$2")
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

NAV_COMMAND=""
case "$PAGE" in
  "") ;;
  Inbox) NAV_COMMAND="nav inbox" ;;
  ForYou|foryou) NAV_COMMAND="nav for-you" ;;
  Saved) NAV_COMMAND="nav saved" ;;
  PullRequests) NAV_COMMAND="nav pull-requests" ;;
  Issues) NAV_COMMAND="nav issues" ;;
  Repositories) NAV_COMMAND="nav repositories" ;;
  Settings) NAV_COMMAND="nav settings" ;;
  *)
    echo "unknown page: $PAGE (Inbox|ForYou|Saved|PullRequests|Issues|Repositories|Settings)" >&2
    exit 2
    ;;
esac

if ! pgrep -f "github_client\\.exe|MoonBit GitHub Client\\.app/Contents/MacOS/github-client" > /dev/null; then
  echo "github_client is not running. Start it with scripts/macos/run.sh or the installed app." >&2
  exit 1
fi

WINDOW_ID="$(swift -e '
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
  let name = w[kCGWindowName as String] as? String ?? ""
  if name.hasPrefix("MoonBit GitHub Client"),
     let id = w[kCGWindowNumber as String] as? Int {
    print(id)
    break
  }
}' 2>/dev/null | head -n 1)"

if [[ -z "$WINDOW_ID" ]]; then
  echo "Could not find the MoonBit GitHub Client window." >&2
  exit 1
fi

send_control() {
  # The app consumes and deletes the file on each poll (~0.5s). Wait for the
  # previous file to be consumed so sequential commands are not overwritten.
  printf '%s\n' "$1" > "$CONTROL_FILE"
  for _ in $(seq 40); do
    [[ ! -f "$CONTROL_FILE" ]] && return 0
    sleep 0.25
  done
}

if [[ ${#CMDS[@]} -gt 0 ]]; then
  for cmd in "${CMDS[@]}"; do
    send_control "$cmd"
  done
fi
if [[ -n "$NAV_COMMAND" ]]; then
  send_control "$NAV_COMMAND"
fi

# Give the app a few frames to dispatch the queued actions and repaint.
sleep 1
mkdir -p "$(dirname "$OUTPUT")"
screencapture -o -x -l "$WINDOW_ID" "$OUTPUT"
echo "captured: $OUTPUT"
