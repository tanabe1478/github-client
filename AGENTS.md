# Project agent instructions

## UI and design

Repository code and documentation are the source of truth for behavior, accessibility, security, platform constraints, and visual implementation.

- Use the GitHub Primer light palette defined by the native implementation.
- Follow Material Design 3 interaction guidance: primary operations require explicit controls; do not depend on hidden gestures, row clicks, or double clicks.
- List items use explicit trailing actions, state is expressed with labels and disabled states, and destructive actions remain visually separate.
- Validate UI changes by running the native application and capturing screenshot evidence under `artifacts/`.
- Drive the app under test through the control file, never through synthetic OS input. ImGui controls do not exist in the macOS accessibility tree, so CGEvent clicks and Accessibility actions cannot reach them and they steal focus and move the user's cursor.
- Send commands with `scripts/macos/ctl.sh` (writes to `~/.config/moonbit-github-client/control.txt`), or write lines to that file directly. The app polls it ~twice per second and dispatches each line through the same action handlers as UI input. Supported commands: `nav <page>`, `open|done|save|unsub <url>`, `watch <owner/repo>`, `refresh`, `refresh-for-you`, `show-done 0|1`, `quit`.
- Capture evidence with `scripts/macos/capture-smoke.sh` (`screencapture -l`), which works on background windows without raising or focusing the app.
- Keep the screen inventory in `docs/screens.md` aligned with the implementation.
