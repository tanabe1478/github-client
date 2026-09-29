# Project agent instructions

## UI and design

Repository code and documentation are the source of truth for behavior, accessibility, security, platform constraints, and visual implementation.

- Use the GitHub Primer light palette defined by the native implementation.
- Follow Material Design 3 interaction guidance: primary operations require explicit controls; do not depend on hidden gestures, row clicks, or double clicks.
- List items use explicit trailing actions, state is expressed with labels and disabled states, and destructive actions remain visually separate.
- Validate UI changes by running the native application and capturing screenshot evidence under `artifacts/`.
- Drive the app under test through the control file, never through synthetic OS input. ImGui controls do not exist in the macOS accessibility tree, so CGEvent clicks and Accessibility actions cannot reach them and they steal focus and move the user's cursor.
- Send commands with `scripts/macos/ctl.sh` (writes to `~/.config/moonbit-github-client/control.txt`), or write lines to that file directly. The app polls it ~twice per second and dispatches each line through the same action handlers as UI input. Supported commands: `nav <page>`, `open|done|save|unsub|menu <url>`, `watch|unwatch <owner/repo>`, `refresh`, `refresh-for-you`, `refresh-all`, `show-done 0|1`, `kind all|pr|issue`, `repo <owner/repo|all>`, `search [text]`, `reason <reason|all>`, `expand <owner/repo|author>`, `undo`, `cancel`, `token-dialog`, `quit`. Run `scripts/macos/ctl.sh` without arguments for descriptions.
- For scripted or AI-driven triage that does not need the window, use the `ghclient` command-line client (`docs/cli.md`): it prints JSON and a running app reloads its changes. The control file is for driving and capturing the UI.
- Capture evidence with `scripts/macos/capture-smoke.sh` (`screencapture -l`), which works on background windows without raising or focusing the app.
- Keep the screen inventory in `docs/screens.md` aligned with the implementation.
