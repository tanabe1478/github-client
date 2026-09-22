# MoonBitデスクトップGitHubクライアント 技術調査

## 目的と前提

- MoonBitのnative targetで実装する。
- WebViewを主UIとせず、`mizchi/glfw`をウィンドウ・入力層として利用する。
- 最初にWindowsを動作対象とする。
- GLFW周辺で一般化できる修正が見つかった場合は、forkに蓄積してupstreamへのcontributionを検討する。

調査はMooncakesの公開パッケージ、各リポジトリのREADME・manifest・実装・CIを対象に行った。以下の「検証済み」は各upstreamが示す範囲であり、このプロジェクトのWindows実機検証は別途行う。

## 結論

現時点の第一候補は次の構成。

| 関心 | 採用候補 | 判断 |
|---|---|---|
| Window/input | [`mizchi/glfw`](https://github.com/mizchi/glfw-mbt) | 採用。Windows runtime smokeは実機で成功 |
| GUI | [Dear ImGui](https://github.com/ocornut/imgui) | 採用。公式GLFW/OpenGL backendと一般環境での豊富な実績を優先 |
| Native rendering | OpenGL 3 | 採用。GLFWがcontext lifecycleを直接提供し、最初の統合範囲が小さい |
| GitHub REST API | アプリ内の最小client | 採用。必要なendpointとresponse型だけを実装する |
| 一般HTTP | [`oboard/reqbest`](https://github.com/oboard/reqbest) | GitHub APIクライアントで足りない認証等の補助候補 |
| JSON | `moonbitlang/core/json` | 採用 |
| OAuth | GitHub Device Flowを小さく実装 | 既存OAuth2ライブラリにはDevice Flowがない |
| Token保護 | `moonbit-community/proton_safe_storage` | 採用候補。Windows DPAPI対応済み |
| Browser起動 | `moonbit-community/proton_shell` | 採用候補 |
| 配布 | `moonbit-community/proton_package` | 採用候補。Windows app/zip/NSISを生成可能 |

Kaguraは調査対象には含めるが採用しない。ゲームエンジンのruntimeをデスクトップアプリの土台にするのではなく、GUI coreとrenderer/window hostを明示的に分離する。

最大の未解決点はDear ImGuiのC++ APIをMoonBitへ漏らさない薄いC ABI bridge、日本語IME、application semantic registryである。選定理由は[ADR 0001](decisions/0001-glfw-ui-stack.md)に記録した。

---

## 1. 描画・UI層

### 1.1 `mizchi/glfw`

MoonBit native向けGLFWバインディング。ウィンドウ、キーボード、マウス、スクロール、ゲームパッド、DPI、fullscreenを提供する。

Windowsについて確認できたこと:

- upstream CIにWindowsジョブがある。
- `vcpkg`の`glfw3:x64-windows-static`を使用してcheck/build/runtime smokeを実行する。
- Windowsのタッチ入力は現状no-op。
- consumer側にGLFWのlink flagsが必要。
- CIはMoonBitが追加する`-lm`に対し、ダミーの`m.lib`を作るworkaroundを持つ。
- ローカルforkは [`tanabe1478/glfw-mbt`](https://github.com/tanabe1478/glfw-mbt)。
- Windows 11実機で初期化、window作成、event poll、破棄までのruntime smokeに成功した。
- 非ASCII titleが`?`へ置換される問題をforkの`windows/unicode-window-title`でUTF-8変換へ修正した。upstream PRはもう少し利用実績をためてから判断する。

注意点:

- GLFWは描画APIとGUI toolkitを提供しない。
- `create_window`は`GLFW_NO_API`で作成されるため、WebGPU等のsurfaceを接続する必要がある。
- 現時点の公開APIからはWin32 `HWND`を直接取得できない。

### 1.2 MoonBitコミュニティ全体のGUI候補

#### `moonbitstack/moonegui`

Rust eguiに着想を得たPure MoonBitのimmediate-mode GUI。

- GUI coreは同期的でhost loopを所有しないため、GLFW loopへ組み込みやすい。
- backend契約はtext measurement 3操作とdraw 9操作に限定されている。
- button、label、checkbox、radio、slider、text edit、layout、focus、hit testがある。
- recording backendと177件のtestを持つ。
- native backend、画像、data table、virtual list、複数windowはまだない。

recording backendは魅力的だが、native renderer、table、virtual list、日本語text/IMEまで新規統合する範囲が大きい。GLFWを維持する構成ではDear ImGuiを優先し、mooneguiは不採用とする。

#### Dear ImGui

GLFWと組み合わせるGUIとして一般環境で最も実績が多い候補。公式の`imgui_impl_glfw`と`imgui_impl_opengl3`を利用し、MoonBitからはアプリ向けの薄いC ABIを呼ぶ。

- table、scroll、tree、tab、popup、multiline inputが揃う。
- 最初はOpenGL 3 core profileで統合し、必要ならWindows向けD3D11を比較する。
- MoonBit向け既存bindingの成熟度には依存せず、Dear ImGui本体と公式backendをversion固定する。
- MoUI相当のsemantics/accessibilityはないため、stable ID、role、value、actionを記録するapplication semantic registryを実装する。
- 日本語font、IME、accessibilityは個別の受け入れ試験が必要。

#### `wzzc-dev/MoUI`

MoonBitコミュニティで最も包括的な宣言的GUI候補。

- TEA型のProgram/Effect/Subscription、豊富なdesktop widget、table、virtual list、text/IME、semantics/accessibilityを持つ。
- Windowsをcommitted platformとし、Skia rendererと専用Win32 hostがある。
- GLFW backendは存在せず、desktopではMoUI自身のwindow lifecycleを使う。
- GLFWを外せるなら非常に有力だが、今回のGLFW検証目的とは競合する。

semantic observation/actionの設計はapplication semantic registryの参考にする。一方、Windows実Skia buildでC/C++標準flagの競合がありfirst frameが未検証であることと、GLFW資産を製品経路で活用する判断から不採用とする。

#### `NoahLiu/moonbit-libyue`

libyue C++の包括的binding。

- Windows 10/11実機対応、Linux複数desktop対応、macOS CI build対応。
- 55 native widgets、57 themed components、text input、table、tree、dialog、clipboard、tray等を持つ。
- 完成度の高い通常のdesktop GUIを最短で作る選択肢。
- libyueがwindow/event/renderingを所有するためGLFWとは併用しない。

製品完成を最優先するなら有力だが、GLFWベースという技術目標から今回は採用しない。

#### その他

- `tonyfettes/gtk`: GTK4 binding。Linuxには強いがWindows-firstと相性が悪い。
- `KeqingMoe/qt`: Qt Widgets binding。現時点ではmacOSのみを明示的にsupport。
- `LING71671/moon-egui`: widget数は多いが、browser/game向けでnative backendはplanned。
- `wzzc-dev/imgui`: 初期のsimple bindingで、公開source/repository情報と実績が薄い。
- WebView系（Proton、MoonView、Lepus、Orbit）: desktop frameworkとして有力だが、native self-rendered UIという目標から外す。

### 1.3 `mizchi/kagura`

GLFW + wgpu-nativeのWindows surface bridge実装は参考になる。ただしゲームエンジンであり、desktop widget/IME/accessibilityを主責務にしないため採用しない。

### 1.4 `Milky2018/wgpu_mbt`

wgpu-native C APIのMoonBitバインディング。Windows/macOS/Linux向けAPIを持つ。

- Windows headless Vulkanとsurface descriptorの契約テストはCIにある。
- 実際の`HWND`を使ったpresentはupstreamでも未検証扱い。
- 低レベルで自由度は高いが、renderer、font atlas、widget描画をすべてこちらで構築する必要がある。

判断:

- Kagura rendererが利用困難な場合の第二候補。
- 最初から直接使うより、統合済みのKaguraで技術リスクを減らす。

### 1.5 `LING71671/moon-egui`

Pure MoonBitのimmediate-mode GUI。headless coreが描画から分離されている。

既存機能:

- button、checkbox、text edit、code editor、table、virtual list、tree、tabs、scroll area、dialog、menu、splitter等。
- 入力を受け、`Rect`、`Text`、`Line`、`Clip`等の`DrawCmd`列を生成する。
- 348件のheadless testを掲げている。

制約:

- 公式native backendは未実装。
- 現在のhost rendererはCanvas/WebGL中心。
- IME、clipboard、OS key mapping、font metricsをnative環境へ接続する必要がある。
- GitHubクライアントでは日本語入力が重要なので、ASCII text inputだけで完了とはしない。

判断:

- widget・layout・focusを一から作るより有望。
- `DrawCmd -> Kagura DrawTrianglesCommand`変換、font atlas、clip、入力変換を小さなadapter packageとして実装する。
- adapterが汎用化できれば、moon-eguiまたはKaguraへのcontribution候補になる。

### 1.6 その他の選択肢

- `tonyfettes/raylib` + `raygui`: Windowsを含む実績が比較的多くGUIもあるが、raylibがwindow/render loopを所有するためGLFWを検証する本プロジェクトの目的とずれる。
- Dear ImGui binding: `wzzc-dev/imgui`があるが初期版で利用例中心。MoonBit-nativeなUI改修余地はmoon-eguiの方が大きい。
- Proton / MoonView / WebView bindings: MoonBitのデスクトップアプリとしては強力で、WebView2によるUI、IPC、packagingまで存在する。ただしGLFW + native renderingという今回の挑戦から外れるため主経路には採用しない。

---

## 2. HTTP・JSON・GitHub API層

### 2.1 アプリ内の最小GitHub client

`mizchi/github`の包括的SDKには依存しない。このプロダクトは登録repositoryを中心とした関連activity inboxであり、必要なendpointが限定されるためである。

初期API surface:

- authenticated user
- notifications
- 登録repository情報
- 登録repositoryのopen issue / pull request
- dependency graph SBOM

endpoint pathとresponse型を`github_api/`へ追加し、pagination、rate limit、ETag、conditional requestも利用する機能に必要な範囲だけ実装する。詳細は[Product scope](product-scope.md)を参照する。

### 2.2 `oboard/reqbest`

MoonBit nativeのasync HTTP client。

- HTTP/1.1対応。HTTP/2/3はexperimental。
- TLS、streaming、timeout、compression、JSON response helperを持つ。
- JavaScript targetではFetchを利用する。

判断:

- 最小GitHub clientのHTTP transport候補。
- Device Flowを含め、接続poolを二重化せず同じtransportへ統一する。
- 実装前に`moonbitlang/async/http`を直接使う場合との差を小さな接続spikeで比較する。

### 2.3 JSON

標準の`moonbitlang/core/json`とderiveを使用する。GitHub API clientも同系統を使用しており、別parserを導入する理由はない。

### 2.4 非同期処理

GitHub clientのHTTP処理には`moonbitlang/async`を利用する。GLFWはmain thread上のpoll/render loopを要求するため、次をスパイクで確認する。

- async mainの中でGLFW event loopを駆動できるか。
- 毎frame cooperative yieldしてnetwork taskを進められるか。
- GPU/GLFW操作をmain threadに固定できるか。
- UI state更新をmessage queue経由にできるか。

---

## 3. 認証とtokenの安全な保存

### 3.1 GitHub認証方式

デスクトップアプリにはGitHub Device Flowが適している。

予定フロー:

1. Device code endpointへclient IDを送る。
2. `user_code`と`verification_uri`をUI表示する。
3. `proton_shell`でsystem browserを開く。
4. intervalと`slow_down`を守ってtoken endpointをpollする。
5. tokenをOS-backed storageで暗号化する。

GitHub OAuth App側でDevice Flowの有効化が必要。client IDの提供方法と、開発用/配布用OAuth Appの分離は別途決める。

初期スパイクではPAT入力も残し、API/rendering検証をOAuth App登録から分離する。

### 3.2 `ryota0624/oauth2`

Authorization Code + PKCE、Client Credentials、Refresh Token、OIDCを提供する。ただし:

- alpha表記。
- Device Authorization GrantはTODO。
- GitHub provider exampleもTODO。
- callbackを受けるloopback HTTP serverやbrowser起動は別途必要。

判断:

- GitHub Device Flowには直接採用しない。
- URL encoding、CSRF/PKCE等の実装参考にはなる。

### 3.3 `moonbit-community/proton_safe_storage`

native MoonBit向けのOS-backed safe storage。

- Windows: DPAPI `CryptProtectData` / `CryptUnprotectData`
- macOS: Keychainに鍵を保存しCommonCryptoで暗号化
- Linux: Secret Service未実装のためunsupported。平文fallbackはしない
- API: `is_available`、`encrypt_string`、`decrypt_string`

重要: このライブラリは暗号化された文字列を返す。暗号文そのものを設定ファイル等へ永続化する処理はアプリ側で実装する。

判断:

- Windows MVPに採用する。
- 保存ファイルにはtokenの平文、認証header、debug dumpを出さない。
- log redactionのtestを用意する。

### 3.4 周辺native機能

Protonの独立sys packageはProton runtimeを全面採用しなくても利用できる。

- `moonbit-community/proton_shell`: URLをsystem browserで開く
- `moonbit-community/proton_clipboard`: device code、URL、issue本文等のclipboard操作
- `moonbit-community/proton_notification`: desktop notification（後続候補）

---

## 4. Windowsビルド・配布

### 4.1 開発ビルド

想定依存:

- MoonBit native toolchain
- clang
- GLFW (`vcpkg`, static tripletを第一候補)
- wgpu-native library/header
- Windows system libraries

既知の論点:

- MoonBit packageのlink flagsはconsumerへ伝播しないため、最終`is-main` packageに集約する。
- GLFW upstream CIの`m.lib` workaroundがローカルでも必要か確認する。
- static/dynamicのどちらで配布するかを固定し、DLLの取りこぼしを避ける。
- wgpu backendはD3D12を第一候補とし、adapter/device/surface/presentをWindows実機で確認する。

### 4.2 `moonbit-community/proton_package`

既にビルド済みの任意の実行ファイルをpackagingする汎用CLI/library。Proton/CEF専用ではない。

対応形式:

- Windows: app directory、zip、NSIS
- macOS: app、zip、dmg
- Linux: AppImage

Windowsではcurrent-user/per-machine/bothのNSIS install mode、payload、shortcut、URL scheme、icon埋め込みを扱える。

判断:

- Windows配布の第一候補。
- GLFW/wgpuのDLL、font、icon等をpayloadとして含める。
- 最初はportable zip、次にNSIS installerを作る。

### 4.3 CIとrelease

予定:

1. Windows runnerで`moon check`とpure logic test。
2. native executable build。
3. 可視windowを開くsmoke testはself-hosted/manualも併用。
4. portable zipをartifact化。
5. 安定後にNSIS、code signing、自動更新を検討。

`proton_updater`も存在するが、初期MVPの範囲外とする。

---

## 実装スパイクの順序

1. **Window smoke**: forkした`glfw-mbt`でWindows windowを作成・終了する。**完了**
2. **OpenGL context smoke**: GLFW windowでOpenGL 3 contextを作りbuffer swapする。
3. **Dear ImGui smoke**: 公式GLFW/OpenGL backendでdemo、button、scroll、text inputを描画する。
4. **Semantic smoke**: stable IDでbuttonを操作し、stateとsemantic snapshotを検証する。
5. **Async smoke**: 描画を止めずに最小GitHub clientでauthenticated userを取得する。
6. **Auth storage smoke**: PATをDPAPIで暗号化・再読込・削除する。
7. **Vertical slice**: repository listを取得し、Dear ImGui tableとして表示する。
8. **Package smoke**: portable zipを別のWindows環境で起動する。

この順序なら、GLFW、WebGPU、UI、async runtime、TLS、secure storage、packagingの失敗点を分離できる。

## 参考リンク

- https://github.com/mizchi/glfw-mbt
- https://github.com/moonbitstack/moonegui
- https://github.com/wzzc-dev/MoUI
- https://github.com/lb091188/moonbit-libyue
- https://github.com/moonbit-community/wgpu-mbt
- https://github.com/LING71671/moon-egui
- https://github.com/oboard/reqbest
- https://github.com/ryota0624/moonbit_oauth2
- https://github.com/moonbit-community/proton/tree/main/sys/safe_storage
- https://github.com/moonbit-community/proton/tree/main/package
