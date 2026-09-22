# github-client

MoonBitで実装するネイティブデスクトップ向けGitHubクライアントです。

このプロジェクトでは、WebViewを主UIにせず、GLFWとネイティブ描画を使う構成に挑戦します。最初の対象OSはWindowsです。

## Status

技術検証中です。現在の候補構成と調査結果は[技術調査](docs/technical-research.md)を参照してください。

## Related repositories

- [`tanabe1478/glfw-mbt`](https://github.com/tanabe1478/glfw-mbt) — Windows向け修正を蓄積するfork
- [`mizchi/glfw-mbt`](https://github.com/mizchi/glfw-mbt) — upstream

## Tentative stack

- Window/input: `mizchi/glfw`
- UI core: `moonbitstack/moonegui`
- Native renderer: 調査・実装中（Skia / NanoVGを比較）
- GitHub API: `mizchi/github`
- Async runtime: `moonbitlang/async`
- Secure token storage: `moonbit-community/proton_safe_storage`
- Open external URLs: `moonbit-community/proton_shell`
- Packaging: `moonbit-community/proton_package`

Kaguraはゲームエンジンなので採用しません。特定作者に寄せず、MoonBitコミュニティ全体のパッケージを比較します。

## Windows bootstrap

前提条件はLLVM、Visual Studio Build Tools、vcpkg版GLFWです。

```powershell
winget install --id LLVM.LLVM -e
$env:VCPKG_ROOT = "$HOME\vcpkg"
& "$env:VCPKG_ROOT\vcpkg.exe" install glfw3:x64-windows-static
.\scripts\windows\run.ps1
```

ビルドのみの場合は`.\scripts\windows\run.ps1 -BuildOnly`を使用します。
