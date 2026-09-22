# ADR 0001: GLFW + Dear ImGuiを製品UI基盤にする

- Status: Accepted
- Date: 2026-09-22

## Context

このプロジェクトでは、Windows対応を追加した`tanabe1478/glfw-mbt`の資産を製品経路で活用し、WebViewを主UIにしない。候補にはMoUI + SkiaとGLFWベースの構成があった。

MoUIはsemantic observation/actionを標準提供する一方、Windows実Skia buildでC/C++標準flagの競合を確認し、first frameまで到達していない。GLFWはWindows window/event loopとUnicode titleまで実機検証済みだが、rendererとGUIは別途必要になる。

## Decision

次の構成を採用する。

- Window/input: `tanabe1478/glfw-mbt`
- Renderer: OpenGL 3 core profile
- GUI: Dear ImGui本体、`imgui_impl_glfw`、`imgui_impl_opengl3`
- MoonBit境界: Dear ImGuiのC++型を公開しない薄いC ABI bridge
- Application state: Pure MoonBitのModel/update
- Verification: state test、application semantic registry、draw/screenshot smoke

最初はOpenGL 3で統合面を小さくする。Windows固有の描画安定性が必要になった場合は、GLFWを維持したままD3D11 backendを比較する。

## Why Dear ImGui

- GLFWとの公式backendと広い実績がある。
- table、scroll、tree、tab、popup、multiline inputなどGitHubクライアントに必要な部品が揃う。
- moonegui + 独自rendererより、描画・入力adapterの新規実装範囲が小さい。
- アプリ向けC ABIに限定すればMoonBit bindingを小さく保てる。

## Semantic verification

Dear ImGuiにはMoUI相当のsemantic treeがないため、widget wrapperが描画と同時に次の情報を登録する。

- stable ID（例: `auth.sign-in`、`repositories.list`）
- role、label、value、enabled/focused state
- 利用可能なaction

テストは画面座標ではなくstable IDへactionを送り、Pure MoonBit stateとsemantic snapshotを確認する。pixel screenshotは補完証跡として利用する。

## Consequences

### Positive

- GLFW forkのWindows修正と今後の改善を直接利用できる。
- 一般に実績の多いGLFW + Dear ImGui構成へ寄せられる。
- MoUI Windows/Skiaのbuild成熟度に依存しない。

### Negative

- semantics、accessibility、IMEの統合はプロジェクト側の責任になる。
- Dear ImGuiはOS native widgetではない。
- GUI bridgeとDear ImGui source/versionを保守する必要がある。

## Acceptance steps

1. GLFW forkでOpenGL core contextを作りbuffer swapする。
2. Dear ImGui demo windowを表示する。
3. 日本語fontとIME入力を確認する。
4. stable ID付きbuttonをsemantic actionで操作する。
5. repository listをtable/clip/scroll付きで表示する。
6. screenshotとsemantic snapshotをCI artifact化する。
