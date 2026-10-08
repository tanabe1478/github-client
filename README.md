# github-client

English | [日本語](README.ja.md)

A native desktop GitHub client written in MoonBit. Instead of a WebView, it renders its own UI with GLFW, OpenGL 3, and Dear ImGui. It runs on Windows and macOS.

The app is an activity inbox for the repositories you choose to watch, not a general GitHub client: open pull requests and issues in those repositories, plus the review requests, assignments, mentions, and subscriptions that involve you there.

## Status

GLFW hosts the window and Dear ImGui draws the UI on OpenGL 3. The reasons for this stack are in [ADR 0001](docs/decisions/0001-glfw-ui-stack.md) (Japanese), and the wider survey is in the [technical research](docs/technical-research.md) (Japanese).

## Related repositories

- [`tanabe1478/glfw-mbt`](https://github.com/tanabe1478/glfw-mbt) — fork that collects fixes for Windows
- [`mizchi/glfw-mbt`](https://github.com/mizchi/glfw-mbt) — upstream

## Stack

- Window and input: [`tanabe1478/glfw-mbt`](https://github.com/tanabe1478/glfw-mbt)
- GUI: the official Dear ImGui GLFW backend, with a custom theme based on the GitHub Primer light palette
- Renderer: OpenGL 3
- UI verification: pure MoonBit state tests, screenshots, and a control file for driving the app
- GitHub API: only the REST endpoints the product needs, in `modules/github_api`
- Async runtime: `moonbitlang/async`
- Secure token storage: `moonbit-community/proton_safe_storage`
- Opening external URLs: `moonbit-community/proton_shell`
- Packaging: `moonbit-community/proton_package`

How watched repositories, mentions, and dependency activity relate is described in the [product scope](docs/product-scope.md) (Japanese), the dependency direction between modules in the [module boundaries](docs/module-boundaries.md) (Japanese), and a comparison with Jasper in the [Jasper feature gap analysis](docs/jasper-feature-gap.md).

## Screens

The screens were designed on a Claude Design canvas, "GitHub Client Redesign", and the native implementation follows it. The images below are renders of the canvas artboards. They differ from the implementation in details such as fonts, spacing, and counts; screenshots of the implementation are kept under `artifacts/`.

| Inbox | For you |
|---|---|
| ![Inbox](docs/images/design/inbox.png) | ![For you](docs/images/design/for-you.png) |

- Inbox lists open pull requests and issues of watched repositories, grouped by repository. It filters by kind, repository, and text, and folds updates from dependency bots into one row.
- For you lists review requests (including requests to your teams), assignments, mentions, and subscriptions, each with chips that say why it is there, and filters by reason. A banner points out review requests hidden in repositories you do not watch.
- Every row has visible buttons: `Open`, `Done`, Save, and More actions (Copy link, Show only this repository, Unsubscribe). Done, Save, and Unsubscribe can be undone from the snackbar.

| Repositories | Settings |
|---|---|
| ![Repositories](docs/images/design/repositories.png) | ![Settings](docs/images/design/settings.png) |

| Row states and feedback | Loading |
|---|---|
| ![Row states](docs/images/design/row-states.png) | ![Loading](docs/images/design/loading.png) |

![Errors](docs/images/design/errors.png)

- Loading: skeleton rows on first launch, a dialog with progress and Cancel for manual refreshes, and a non-blocking progress bar for auto refresh.
- Errors: a rejected token (401), a rate limit (403), repositories that failed, GitHub being unreachable, and timeouts are each shown with the cause and a button that fixes it.

Every screen and state is specified in [`docs/screens.md`](docs/screens.md). `scripts/design/render-design.cjs` regenerates the images from the canvas artboards.

## Done, Save, and Unsubscribe

Done means "I have seen it as it is now". Unsubscribe means "never show me this item again".

| | Done | Unsubscribe |
|---|---|---|
| Right away | Hidden (visible with Show done) | Hidden from every list, Saved included |
| After the item changes on GitHub | Unread and listed again | Stays hidden |
| Notifications | Yes, on the next change | Never |
| Undo | Show done, then `Move to inbox` | The snackbar's `Undo`, or `ghclient unmute <url>`; no screen lists unsubscribed items |
| Effect on GitHub | None | None; your GitHub subscription stays as it is |

Save keeps an item in Saved whether it is done or not.

For an item you will handle later, Save it and then mark it Done. It leaves Inbox and For you, stays in Saved until you unsave it, and comes back as unread if anything changes on GitHub. If you only want to hear about it when it moves, Done alone is enough. Keep Unsubscribe for items you never need to see again.

## Modules

- `modules/domain`: pure product model and relevance rules
- `modules/github_api`: the minimal GitHub API surface
- `modules/activity_sync`: fetching GitHub activity (concurrent requests, token selection) and turning it into domain items; shared by the app and the CLI
- `modules/app_paths`: per-OS application data paths
- `modules/credential_store`: personal access tokens encrypted with DPAPI or the Keychain, for a default token and owner or organization scopes
- `modules/repository_store`: watched repositories on disk
- `modules/read_state_store`: done state of activities on disk
- `modules/triage_store`: saved and muted activities on disk
- `modules/review_request_store`: review requests kept until you review, even after GitHub drops a team's request
- `cmd/github_client`: desktop composition root
- `cmd/ghclient`: command-line client

Modules must not depend on each other in cycles; the allowed directions are fixed in the [module boundaries](docs/module-boundaries.md) (Japanese).

## Command-line client

`ghclient` uses the app's tokens and data without opening a window. It lists activity as JSON and changes done, saved, muted, and watched state, for scripts and AI agents. A running app reloads the changes within about two seconds.

```sh
./scripts/macos/install-cli.sh
ghclient inbox --kind pr --json
ghclient done https://github.com/owner/repo/pull/123
```

Commands and the JSON format are in [`docs/cli.md`](docs/cli.md).

## Windows bootstrap

Prerequisites are LLVM, Visual Studio Build Tools, and GLFW from vcpkg.

```powershell
winget install --id LLVM.LLVM -e
$env:VCPKG_ROOT = "$HOME\vcpkg"
& "$env:VCPKG_ROOT\vcpkg.exe" install glfw3:x64-windows-static
.\scripts\windows\run.ps1
```

`.\scripts\windows\run.ps1 -BuildOnly` only builds. Done state is saved to `%LOCALAPPDATA%\MoonBitGitHubClient\read-state.txt`.

```powershell
.\scripts\windows\run.ps1 -BuildOnly
.\scripts\windows\capture-smoke.ps1
.\scripts\windows\capture-smoke.ps1 -Page ForYou -Output artifacts\for-you\for-you.png
.\scripts\windows\interaction-smoke.ps1
```

`interaction-smoke.ps1` opens a real Windows window and checks Settings navigation and the screenshot after the interaction.

## macOS bootstrap

Prerequisites are the Xcode Command Line Tools, GLFW from Homebrew, and mise. The MoonBit toolchain is pinned in `mise.toml`, and `mise install` sets up the toolchain and its core library.

```sh
xcode-select --install
brew install glfw
git submodule update --init
./scripts/macos/run.sh
```

`./scripts/macos/run.sh --build-only` only builds. Done state is saved to `~/.config/moonbit-github-client/read-state.txt`.

```sh
./scripts/macos/run.sh --build-only
./scripts/macos/capture-smoke.sh --page Settings --output artifacts/macos/settings.png
```

`capture-smoke.sh` navigates through the control file and captures the window with `screencapture -l`. It never raises the window or moves focus or the cursor, so it does not disturb the app you are using. It needs only the screen recording permission.

### Control file

A running app checks `~/.config/moonbit-github-client/control.txt` about twice a second and runs each command through the same handlers as UI input, then deletes the file. Commands left before the app starts are discarded. `scripts/macos/ctl.sh` writes the commands.

```sh
./scripts/macos/ctl.sh nav for-you
./scripts/macos/ctl.sh save https://github.com/owner/repo/pull/123
./scripts/macos/ctl.sh done https://github.com/owner/repo/issues/123
./scripts/macos/ctl.sh unsub https://github.com/owner/repo/pull/123
./scripts/macos/ctl.sh open https://github.com/owner/repo/pull/123
./scripts/macos/ctl.sh refresh
./scripts/macos/ctl.sh quit
```

Run `./scripts/macos/ctl.sh` without arguments to list every command. `capture-smoke.sh --cmd 'save <url>'` sends a command before capturing. Dear ImGui controls are not in the OS accessibility tree, so the control file is the deterministic way to drive the UI.

## macOS app bundle

`./scripts/macos/package-app.sh` makes a release build and installs it to `/Applications` as `MoonBit GitHub Client.app`. The bundle includes libglfw and is signed ad hoc. Set `INSTALL_DIR` to install elsewhere.

```sh
./scripts/macos/package-app.sh
INSTALL_DIR=~/Applications ./scripts/macos/package-app.sh
```

An ad hoc signature runs on this machine, but Gatekeeper blocks it on others. Distribution needs a Developer ID signature.
