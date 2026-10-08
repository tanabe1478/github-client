# ADR 0001: GLFW + Dear ImGuiを製品UI基盤にする

- Status: Accepted（一部を置き換え。末尾の「2026-10-08 時点の改訂」を参照）
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
- Visual design: GitHub Primerを基準にしたspacing、surface、color、typography
- Verification: state test、application semantic registry、draw/screenshot smoke

最初はOpenGL 3で統合面を小さくする。Windows固有の描画安定性が必要になった場合は、GLFWを維持したままD3D11 backendを比較する。

## Why Dear ImGui

- GLFWとの公式backendと広い実績がある。
- table、scroll、tree、tab、popup、multiline inputなどGitHubクライアントに必要な部品が揃う。
- moonegui + 独自rendererより、描画・入力adapterの新規実装範囲が小さい。
- アプリ向けC ABIに限定すればMoonBit bindingを小さく保てる。

## Visual design

Dear ImGuiのdefault skinは使用せず、GitHub Primer light themeを基準に一貫したthemeを適用する。neutral canvas、dark header、subtle border、blue link、green primary action、8px系spacing、明確なtypography hierarchyを共通部品として提供する。

## Interaction design rules

色はGitHub Primerを基準にし、操作設計はMaterial Design 3のcomponent guidanceに従う。

- 主要操作はlabel付きbuttonとして常に見えるようにし、row click、double click、hoverだけに隠さない。
- list itemは情報表示を主目的とし、項目単位の操作はtrailing actionへ置く。
- 現在の状態は`Watched`などのlabelとdisabled stateで示す。
- 破壊的な操作はprimary actionと色・位置を分ける。監視解除はデータを削除せず再追加可能なため、確認dialogではなく即時feedbackを返す。
- action後は状態変化と結果messageを同じ画面で確認できるようにする。
- keyboard focus、十分なtarget size、stable semantic IDを各actionに持たせる。

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

## 2026-10-08 時点の改訂

GLFW + OpenGL 3 + Dear ImGui、薄いC ABI bridge、product ruleをMoonBit側に置く構成は維持している。以下は上の記述から変わった点である。上の本文は決定当時の記録として残す。

### 対象OS

Windowsに加えてmacOSを対象にした（bb81c54）。macOSではKeychainでtokenを暗号化し、libglfwを同梱したapp bundleをad hoc署名で作る（`scripts/macos/package-app.sh`）。Developer ID署名はしていない。

### Semantic verificationは実装せず、control fileに置き換えた

stable ID、role、valueを登録するapplication semantic registryは実装していない。テストと自動操作は、control file（`~/.config/moonbit-github-client/control.txt`）に`nav`、`done`、`watch`などのコマンドを書き、UI入力と同じhandlerで処理する方式にした。

理由: Dear ImGuiのcontrolはmacOSのaccessibility treeに存在しないため、CGEventのclickやAccessibility actionでは操作できない。合成したOS入力はfocusとcursorを奪い、利用者の作業を妨げる（`AGENTS.md`）。画面の証跡は`screencapture -l`でbackgroundのwindowから撮る（`scripts/macos/capture-smoke.sh`）。windowを使わない操作はCLIの`ghclient`で行う（`docs/cli.md`）。

Dear ImGuiの各controlには`##activity.open`のような安定したIDを付けているが、外部から参照する仕組みはない。

Windowsの`scripts/windows/interaction-smoke.ps1`は、まだ画面座標へのclick（`mouse_event`）で操作しており、control file方式に移っていない。

### Visual design

「dark header」は採用していない。現在の画面はGitHub Primer lightの配色で、明るいnavigation railと1つの作業領域からなる（19e1a27、626cfe2）。画面設計はClaude Designのcanvas「GitHub Client Redesign」に置き、実装はそれに沿う。各画面と状態の仕様は`docs/screens.md`にある。Figmaでの設計管理は一度導入したが外した（52b27c4、028a170）。外した理由は記録がない。

### Acceptance stepsの状況

| 手順 | 状況 |
|---|---|
| 1. OpenGL core contextとbuffer swap | 完了 |
| 2. Dear ImGuiの表示 | 完了 |
| 3. 日本語fontとIME入力 | 日本語fontはWindows（Meiryo）とmacOS（ヒラギノ角ゴシック）で読み込んでいる。IME入力は未確認。IMEを扱う独自のコードはない |
| 4. stable IDによるsemantic action | 実施しない。control fileに置き換えた |
| 5. repository listのclipとscroll | 完了。画面外の行は描画を省く |
| 6. screenshotとsemantic snapshotのCI artifact化 | 未実施。CIがない |

### D3D11 backend

比較していない。OpenGL 3で問題が出た記録もない。
