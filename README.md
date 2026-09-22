# github-client

MoonBitで実装するネイティブデスクトップ向けGitHubクライアントです。

このプロジェクトでは、WebViewを主UIにせず、GLFWとネイティブ描画を使う構成に挑戦します。最初の対象OSはWindowsです。

## Status

GLFWを製品window hostとして採用し、OpenGL 3 + Dear ImGuiを接続する方針です。選定理由は[ADR 0001](docs/decisions/0001-glfw-ui-stack.md)、調査全体は[技術調査](docs/technical-research.md)を参照してください。

## Related repositories

- [`tanabe1478/glfw-mbt`](https://github.com/tanabe1478/glfw-mbt) — Windows向け修正を蓄積するfork
- [`mizchi/glfw-mbt`](https://github.com/mizchi/glfw-mbt) — upstream

## Stack

- Window/input: [`tanabe1478/glfw-mbt`](https://github.com/tanabe1478/glfw-mbt)
- GUI: Dear ImGui公式GLFW backend（GitHub Primer light paletteを基準にした独自theme）
- Native renderer: OpenGL 3（初期経路）
- UI verification: Pure MoonBit state test + application semantic registry + screenshot
- GitHub API: 必要なREST endpointだけを`github_api/`へ実装
- Async runtime: `moonbitlang/async`
- Secure token storage: `moonbit-community/proton_safe_storage`
- Open external URLs: `moonbit-community/proton_shell`
- Packaging: `moonbit-community/proton_package`

登録repository、mention、dependency activityの関連付けは[Product scope](docs/product-scope.md)、依存方向は[Module boundaries](docs/module-boundaries.md)を参照してください。

Kaguraはゲームエンジンなので採用しません。特定作者に寄せず、MoonBitコミュニティ全体のパッケージを比較します。

## Figma design integration

Figma、Claude Code、Codex、PiはFigma公式Remote MCPを共通endpointとして使用します。repository側のcanonical bindingは`design/figma.json`、design tokenは`design/tokens.json`です。

```powershell
node scripts/design/check-figma-config.cjs
```

初期設定とsource-of-truthの運用は[`docs/design-workflow.md`](docs/design-workflow.md)、画面一覧は[`docs/screens.md`](docs/screens.md)を参照してください。manifestの`partial`はFigma fileがbound済みで、未同期screenが残っている状態です。

## Modules

- `modules/domain`: Pureなproduct modelとrelevance rule
- `modules/github_api`: 最小GitHub API surface
- `modules/app_paths`: OS別application data path
- `modules/credential_store`: DPAPI/KeychainによるPAT暗号化保存
- `modules/repository_store`: 登録repositoryのfilesystem persistence
- `cmd/github_client`: desktop composition root

module間の循環参照は禁止し、依存方向は[Module boundaries](docs/module-boundaries.md)で固定します。

## Windows bootstrap

前提条件はLLVM、Visual Studio Build Tools、vcpkg版GLFWです。

```powershell
winget install --id LLVM.LLVM -e
$env:VCPKG_ROOT = "$HOME\vcpkg"
& "$env:VCPKG_ROOT\vcpkg.exe" install glfw3:x64-windows-static
.\scripts\windows\run.ps1
```

ビルドのみの場合は`.\scripts\windows\run.ps1 -BuildOnly`を使用します。GitHub Primer風themeを含む実画面をartifactとして確認できます。

```powershell
.\scripts\windows\run.ps1 -BuildOnly
.\scripts\windows\capture-smoke.ps1
.\scripts\windows\interaction-smoke.ps1
```

`interaction-smoke.ps1`は実際のWindows windowを起動し、画面を撮影して`Sign in to GitHub`をクリックし、MoonBit側の状態更新と操作後のscreenshotを検証します。
