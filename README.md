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
- Rendering: Kagura native renderer / `wgpu-native`
- UI core: `LING71671/moon-egui`をネイティブ描画へ接続するアダプター
- GitHub API: `mizchi/github`
- Async runtime: `moonbitlang/async`
- Secure token storage: `moonbit-community/proton_safe_storage`
- Open external URLs: `moonbit-community/proton_shell`
- Packaging: `moonbit-community/proton_package`

構成はWindows上での最小スパイクを通して確定します。
