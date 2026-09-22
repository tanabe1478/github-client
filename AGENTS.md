# Project agent instructions

## UI and design

Repository code and documentation are the source of truth for behavior, accessibility, security, platform constraints, and visual implementation.

- Use the GitHub Primer light palette defined by the native implementation.
- Follow Material Design 3 interaction guidance: primary operations require explicit controls; do not depend on hidden gestures, row clicks, or double clicks.
- List items use explicit trailing actions, state is expressed with labels and disabled states, and destructive actions remain visually separate.
- Validate UI changes by running the native application and capturing screenshot evidence under `artifacts/`.
- Keep the screen inventory in `docs/screens.md` aligned with the implementation.
