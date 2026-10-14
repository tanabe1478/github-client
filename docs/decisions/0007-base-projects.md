# ADR 0007: ベースプロジェクトを基準に、Watchした項目との関連を出す

- Status: Accepted
- Date: 2026-10-13

## Context

ADR 0006でリリースを受け取れるようになった。しかし、どのリリースが自分のどのプロジェクトに関係するかはわからない。pnpmのようにほぼ毎日リリースするリポジトリでは、関係のないものに埋もれる。

利用者の提案は、基準となるプロジェクト（ベースプロジェクト）を設定し、Watchした項目それぞれとの関連を導くことだった。ベースプロジェクトは関連を判断する前提になり、決定論的な判断の材料にもなる。

画面のゴールはClaude Designのcanvas「GitHub Client Redesign」の「Goal: base projects and related releases」の段に描いた（ADR 0005）。

## Decision

### ベースプロジェクト

- ベースプロジェクトはGitHubのリポジトリ（`owner/name`）で指定する。中身はGitHub APIで読む（push済みの既定branch）。
- 複数を登録できる。Settingsの一番上の「Base projects」カードで追加、Rescan、削除する。
- GitHubのURL（`https://github.com/owner/name`）を貼ってもよい。
- ディレクトリを指定すると、その下のGitリポジトリを探し（`.git/config`のGitHubの`origin`）、見つかったリポジトリをすべて登録する。ディレクトリ自体は登録しない。複数のリポジトリをまとめて置いたフォルダを、一度に登録するための入口である。
- 登録内容は`settings.txt`に書く（`base.repository = owner/name`を1行ずつ）。人やAIが直接編集でき、アプリは外での変更を読み直す（ADR 0004と同じ方針）。
- 読むにはtokenにContentsの読み取り権限が要る。

### 読み取るもの

npm、pnpm、Gradle、Mavenを対象にする。既定branchのファイル一覧を1回取り（Gitのtree API）、下のファイルを深さを問わず読む。`node_modules`、`build`、`target`などの生成物と、`test`、`fixtures`、`examples`などのテスト用のディレクトリは除く。浅いものから最大80ファイルまでにする。

| ファイル | 読み取る内容 |
|---|---|
| `package.json` | `packageManager`（例: `pnpm@11.4.0`）、`engines`、`dependencies`と`devDependencies`の名前と範囲、最上位の`name`（パッケージ名） |
| `.npmrc` | 設定のkey |
| `pnpm-workspace.yaml` | 最上位の設定のkey |
| `gradle/*.versions.toml` | バージョンカタログの`[libraries]`（`group:artifact`と版）と`[plugins]`（idと版）。`version.ref`は`[versions]`から解決する |
| `gradle/wrapper/gradle-wrapper.properties` | Gradle本体の版（`distributionUrl`） |
| `build.gradle(.kts)`、`settings.gradle(.kts)`、`buildSrc`と`build-logic`のconvention plugin | 版を書いたプラグイン（`id("org.springframework.boot") version "3.4.2"`）、`"group:artifact:version"`の依存、版を書かない依存（`implementation("group:artifact")`）、Javaの版（`JavaLanguageVersion.of(21)`、`jvmToolchain(21)`、`JavaVersion.VERSION_21`） |
| `pom.xml` | `parent`（`spring-boot-starter-parent`など）、Javaの版（`java.version`、`maven.compiler.release`など）、`dependency`と`plugin`。`${...}`は`properties`から解決する |
| ルートの`gradle.properties` | 設定のkey |
| ルートの`.sdkmanrc`、`.java-version`、`.tool-versions` | Javaの版 |
| `src/main/resources/application*.yml`、`.yaml`、`.properties` | Springの設定のkey（`spring.jpa.open-in-view`の形） |

設定ファイルの値は読み込まない（credentialが入りうるため）。

### BOM

版を書かない依存は、BOM（版の一覧を持つpom）が版を決める。Spring Bootのプラグインかparentがあれば、その版の`org.springframework.boot:spring-boot-dependencies`を読む。名前が`-bom`か`-dependencies`で終わり、版を書いたライブラリもBOMとして読む（1プロジェクトに最大5つ）。

- BOMはMaven Centralから取る（`repo1.maven.org`）。送るのはBOMの公開の座標と版だけで、tokenとプロジェクトの内容は送らない。公開された版は変わらないので、アプリの実行中は結果を保つ。
- 版を書かない依存は、BOMにその依存があればその版、なければBOMが同じgroupのBOMをimportしていればその版にする（`spring-session-bom`など）。
- 既知のパッケージ（Spring Frameworkなど）はBOMの版をそのまま使う。BOM自身のgroup（Spring Bootのstarter群）は足さない。
- BOMがimportするBOM（`jackson-bom`など）の中はたどらない。BOMが取れないときは、その依存は版なしのままにする。

対象のファイルがないリポジトリは読み取りの失敗として扱わない。Settingsでは、ほかのエコシステムはまだ読まないことを灰色で示し、どのリリースとも関連付けない。赤字で示すのは、tokenや権限がない、改名されたなど、読めなかったときだけにする。

lockfile（`pnpm-lock.yaml`、`package-lock.json`、`gradle.lockfile`）、SBOM、ほかのエコシステムは後の段階にする。GitHubの依存グラフ（SBOM API）は、GradleのプロジェクトではGitHub Actionsしか載っていないことがあり（dependency submissionが要る）、ここでは使わない。

### 関連の判定

項目（Releasesの行と、Watch中の依存先のissue・PR）ごとに、ベースプロジェクトごとの関連を求める。

決定論的な規則（毎回の取得で計算し直す）:

| ラベル | 条件 |
|---|---|
| Major update | プロジェクトが使う版より新しく、メジャーバージョンが上がっている |
| Newer than in use | プロジェクトが使う版より新しく、同じメジャーバージョン |
| In use | プロジェクトがこの版かそれより新しい版を使っている。表示はするが、関連には数えない |
| Uses a setting | リリースノートやissueの本文に、プロジェクトの設定ファイルにあるkeyが出てくる。コードスパン（`` `key` ``）のほか、ドットを2つ以上含む語（`spring.threads.virtual.enabled`）も地の文から拾う。まとまり（`spring.security.oauth2`）はその下のkeyにも一致する。同じ語は、いくつのファイルとkeyに当たっても1つのラベルにする |
| Mentions the project | issueやPRが、プロジェクトのリポジトリ名かパッケージ名に触れている |

セキュリティ勧告（使っている版が影響範囲に入る）は、使うAPIを確かめてから後の段階で足す。

リリースとパッケージの対応は、まずWatch中のリポジトリ名とパッケージ名の既知の対応（`pnpm/pnpm`→`pnpm`、`npm/cli`→`npm`、`spring-projects/spring-boot`→`org.springframework.boot`、`gradle/gradle`→`gradle`）から始める。Mavenのgroupに対応するものは、そのidのプラグインとgroupのライブラリすべてに一致する（Spring Bootのプラグインと`spring-boot-starter-*`）。対応表にないリポジトリは、リポジトリ名と同じパッケージ名、またはartifact名に一致させる。npm registryの`repository`欄での解決は後の段階にする。ラベルの版はタグのとおりに出す（`4.2.0-M2`）。

### AIによる判断

- アプリはAIを呼ばない。AIエージェントが`ghclient`で候補と前提（リリースノート、プロジェクトから読み取った内容）を取り出し、判断を`ghclient`で記録する。記録は`relations.txt`などのファイルに置き、アプリが読み直して表示する。
- 記録する内容は型で決める。対象の項目、プロジェクト、影響の有無、理由の短い文、根拠（ファイルと行、または本文の引用）、確信度（0から1）。
- 根拠は決定論的に確かめる。挙げたファイルと行が存在し、引用した文字列が実際にあるときだけラベルを出す。確かめられない判断は表示しない。
- AIのラベルは点線の枠とAIの印で、規則のラベルと見分けられるようにする。
- 判断は、対象の項目かプロジェクトの読み取り内容が変わるまで保つ。

AIにはJev、Claudeなどを選べるようにし、アプリとファイルの形式はどのAIかに依存しない。

### 表示

- Releasesの行に、プロジェクトごとに1つずつラベルを付ける（例: 「acme/web · pnpm 11.4.0 → 12.12.0 · Major update」）。
- ツールバーに、プロジェクトでの絞り込みと「Related only」を足す。「Related only」は最初からオンにする。オンのときは、隠した件数を1行で出す。
- 行の情報ボタンで「なぜ関係があるか」を開き、規則とAIの根拠を一覧にする。
- Watch中の依存先のissueとPRにも同じラベルを付ける。
- ベースプロジェクトがないときは、Releasesに追加を促す空の状態を出す。

## 段階

1. リポジトリのベースプロジェクトとディレクトリからの一括登録、npm、pnpm、Gradle、Mavenのファイル（下位のディレクトリを含む）とJavaの版とSpringの設定の読み取り、BOMによる版の解決、決定論的な規則、Releasesでの表示と絞り込み、Settingsのカード。
2. AIの判断の記録（`ghclient`のコマンド）、根拠の確認、表示。
3. lockfileとSBOMの読み取り（推移的な依存）。
4. セキュリティ勧告、npm registryとMaven Centralでのパッケージとリポジトリの対応、ほかのエコシステム。

## 検討した案

- アプリの中でAIを呼ぶ: APIキーの管理と、非公開リポジトリの内容を外部に送るかの判断がアプリに入る。AIエージェントがCLIで操作する方針（ADR 0004）にも合わない。不採用。
- AIの判断だけで関連を決める: コスト、再現性、裏付けの面で弱い。決定論的な規則で候補を絞り、AIは規則で判断できない部分だけを補う。
- ベースプロジェクトを1つに限る: 利用者は複数のプロジェクトを持つ。複数にし、ラベルにプロジェクト名を出す。
- GitHubの依存グラフ（SBOM API）で依存を得る: Dependabotと同じ情報で、推移的な依存も入る。しかしGradleのプロジェクトでは、dependency submissionを設定していないとGitHub Actionsしか載らなかった。build fileを読む方式にし、SBOMは段階3で併用を考える。
- BOMをSpring BootのGitHubのリポジトリ（タグのbuild script）から読む: 外部のhostが増えないが、Gradleで書かれた版の定義を解析する必要があり、書き方が版ごとに変わる。公開されたpomの方が安定しているため、Maven Centralから読む。
- ディレクトリをベースプロジェクトとして直接読む: 外部に何も送らずに済むが、端末ごとに結果が変わり、ラベルの名前もリポジトリと結びつかない。一度は設計したが、利用者の判断でリポジトリ指定を基本にし、ディレクトリはリポジトリを見つける入口だけにした。

## Consequences

### Positive

- 関係のないリリースが隠れ、自分のどのプロジェクトに関係するかが行ごとにわかる。
- どの端末から見ても、同じリポジトリの内容で判定できる。

### Negative

- lockfileを読まないため、推移的な依存は判定できない。BOMがimportするBOMの中（`jackson-bom`が決めるJacksonの版など）もたどらない。
- push前の変更は判定に入らない。
- tokenにContentsの読み取り権限を足す必要がある。
- ベースプロジェクトごとに、読み直すたびにファイル一覧と、読むファイルの数だけrequestが要る（ETagで変化がなければ304）。BOMの分だけMaven Centralへのrequestが増える。
- AIの判断を出すには、AIエージェントを別に動かす必要がある。
- プロジェクトが多いと、行が縦に長くなる。
