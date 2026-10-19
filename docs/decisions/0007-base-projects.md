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
- Watch中のリポジトリは、Repositoriesの行の「Base project」の切り替えでも登録と削除ができる。Watchした依存先や自分のリポジトリの依存も読みたいとき、別の画面で名前を入れ直さずに済むようにする。登録先は同じ`settings.txt`である。
- GitHubのURL（`https://github.com/owner/name`）を貼ってもよい。
- ディレクトリを指定すると、その下のGitリポジトリを探し（`.git/config`のGitHubの`origin`）、見つかったリポジトリをすべて登録する。ディレクトリ自体は登録しない。複数のリポジトリをまとめて置いたフォルダを、一度に登録するための入口である。
- 登録内容は`settings.txt`に書く（`base.repository = owner/name`を1行ずつ）。人やAIが直接編集でき、アプリは外での変更を読み直す（ADR 0004と同じ方針）。
- 読むにはtokenにContentsの読み取り権限が要る。

### 読み取るもの

npm、pnpm、Gradle、Maven、GitHub Actions、Terraformを対象にする。既定branchのファイル一覧を1回取り（Gitのtree API）、下のファイルを深さを問わず読む。`node_modules`、`build`、`target`、`.terraform`などの生成物と、`test`、`fixtures`、`examples`などのテスト用のディレクトリは除く。浅いものから最大150ファイルまでにする。

エコシステムは、依存からGitHubのリポジトリが分かるものを優先する。このアプリはWatchしたGitHubのリポジトリのリリースを結び付けるためである。GitHub Actions（`uses: owner/repo@v4`）とTerraformのprovider（`hashicorp/aws`は`hashicorp/terraform-provider-aws`）は、外部のregistryに問い合わせずにリポジトリが決まる。npmとMavenは公開registryから引く（「依存のリポジトリの解決」）。Dockerのimageとpipは、リポジトリとの対応に対応表か外部への問い合わせが要るため、後の段階にする。

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
| ルートの`.sdkmanrc`、`.java-version`、`.tool-versions`、`mise.toml` | JavaとNode.jsの版 |
| `.node-version`、`.nvmrc` | Node.jsの版（`22`のような系列の指定も読む） |
| `.github/workflows/*.yml`、`action.yml` | `uses:`のactionをowner/repoと版で。commitに固定したものは、後ろのコメント（`# v4.2.2`）を版とする。ローカルのaction、Docker image、branchの指定は除く |
| `terraform.tf`、`versions.tf`、`providers.tf` | `required_version`（`hashicorp/terraform`として）と、`required_providers`のproviderをGitHubのリポジトリ名と制約で。`module`は読まない |
| `.terraform.lock.hcl` | providerの確定した版 |
| `src/main/resources/application*.yml`、`.yaml`、`.properties` | Springの設定のkey（`spring.jpa.open-in-view`の形） |

設定ファイルの値は読み込まない（credentialが入りうるため）。

### BOM

版を書かない依存は、BOM（版の一覧を持つpom）が版を決める。Spring Bootのプラグインかparentがあれば、その版の`org.springframework.boot:spring-boot-dependencies`を読む。名前が`-bom`か`-dependencies`で終わり、版を書いたライブラリもBOMとして読む（1プロジェクトに最大5つ）。

- BOMはMaven Centralから取る（`repo1.maven.org`）。送るのはBOMの公開の座標と版だけで、tokenとプロジェクトの内容は送らない。公開された版は変わらないので、アプリの実行中は結果を保つ。
- 版を書かない依存は、BOMにその依存があればその版、なければBOMが同じgroupのBOMをimportしていればその版にする（`spring-session-bom`など）。
- 既知のパッケージ（Spring Frameworkなど）はBOMの版をそのまま使う。BOM自身のgroup（Spring Bootのstarter群）は足さない。
- BOMがimportするBOM（`jackson-bom`など）の中はたどらない。BOMが取れないときは、その依存は版なしのままにする。

GitHubで改名や移動されたリポジトリは、旧名に301が返る。転送先（`/repositories/<id>`）から新しい名前を引き、Settingsに「Use new name」を出す。押すと`settings.txt`の名前を置き換える。黙って新しい名前で読むことはしない。`settings.txt`と画面の名前が食い違うためである。

対象のファイルがないリポジトリは読み取りの失敗として扱わない。Settingsでは、ほかのエコシステムはまだ読まないことを灰色で示し、どのリリースとも関連付けない。赤字で示すのは、tokenや権限がない、改名されたなど、読めなかったときだけにする。

lockfile（`pnpm-lock.yaml`、`package-lock.json`、`gradle.lockfile`）、SBOM、ほかのエコシステムは後の段階にする。GitHubの依存グラフ（SBOM API）は、GradleのプロジェクトではGitHub Actionsしか載っていないことがあり（dependency submissionが要る）、ここでは使わない。

### 依存のリポジトリの解決

npmとMavenの依存は、名前からはGitHubのリポジトリが分からない。Dependabotと同じく、公開registryにあるパッケージの情報から引く。規則はdependabot-coreの`maven/shared/shared_metadata_finder.rb`と`npm_and_yarn/metadata_finder.rb`に合わせる。

- Maven: 依存のpomを、`<url>`、`<scm><url>`、`<issueManagement><url>`の順に見て、最初にソースのhost（GitHub、GitLab、Bitbucket）を指すものを使う。なければ、pomのどこかにあるGitHubのURLのうち、リポジトリ名がartifactIdで終わるものを使う。`${scm.github.url}`のようなプロパティは、そのpomのpropertiesとフィールドで展開する。
- 見つからなければ親のpomをたどる。Dependabotは1段だけたどり、見つかったリポジトリの名前がartifactIdで終わるときだけ採用する。ここではそれに加えて、依存と同じgroupの親は何段でもたどり、そのリポジトリを採用する（5段まで）。AWS SDK（`software.amazon.awssdk:dynamodb`→`services`→`aws-sdk-java-pom`）とFlywayは、Dependabotでもリポジトリが見つからず、PRにリンクがないためである。groupの違う親（会社共通の親pomなど）は、別のプロジェクトのリポジトリを指しうるので、名前の一致がなければ採用しない。
- pomはMaven Centralから取る。Gradleのプロジェクトは、Maven Centralにないものを Gradle Plugin Portal（`plugins.gradle.org/m2`）から取る。Gradleのプラグインは、markerのpom（`<id>.gradle.plugin`）が指すライブラリから引く。
- npm: `registry.npmjs.org/<name>/latest`の`repository`、`homepage`、`bugs`の順に見る。`owner/name`と`github:owner/name`の短い書き方も読む。Dependabotは最新版になければ古い版も見るが、パッケージの全版の情報は大きいため、最新版だけにする。
- 送るのは公開パッケージの名前と版だけで、tokenとプロジェクトの内容は送らない。プロジェクト自身のgroup（Gradleの`group = "..."`、pomの`<groupId>`）は送らない。npmは、`.npmrc`がほかのregistryに送るパッケージ（`@scope:registry=`と`registry=`）を送らない。会社の中継（`npm.acme.example`など）は公開npmと同じパッケージを返すが、アプリからは中継か非公開のregistryかを区別できない。利用者が`settings.txt`の`npm.public_mirror`で中継と指定したregistryのパッケージだけをnpmjsに問い合わせる。Settingsのカードの「It mirrors npm」と`ghclient npm-mirror-add`からも指定できる。
- リポジトリを引いたら、GitHubのリリースがあるかを1件だけ取って確かめる（`/releases?per_page=1`）。DefinitelyTypedやApacheのcommonsのように、タグだけでリリースのないリポジトリは、Watchしても何も届かない。pomが見つからないリポジトリ（非公開か削除済み）を指すものは捨てる。改名されたものは新しい名前にする。
- 結果はアプリの実行中だけ保つ。公開されたpomと版の情報は変わらない。

### 依存するリポジトリのWatch

ベースプロジェクトを追加して読み終えたら、まだWatchしていない依存先のリポジトリを「Watch what your base projects use」で一覧にし、選んだものをWatchできるようにする。SettingsのBase projectsのカードの「Suggest watches」からも開ける。

- 候補は、GitHub Actions、Terraformのprovider、Terraform本体、既知の対応表のパッケージ（pnpm、npm、Node.js、yarn、Spring Boot、Spring Framework、Gradle）と、registryからリポジトリが分かったnpmとMavenの依存にする。1つのリポジトリが複数の依存を出すとき（AWS SDKのservice clientなど）は1件にまとめる。
- リリースのあるものを先に、使っているプロジェクトの多い順に並べ、プロジェクトごとの版を添える。registryで分かった依存は、パッケージ名も添える（DefinitelyTypedは多くの`@types`を出すため）。リリースのないものは最後に「No GitHub releases」と示す。最初はどれも選ばない。数が多く、選ばずにWatchすると通知が増えるためである。
- Watchしたリポジトリはリリースだけを取り込む（Pull requests、Issues、For youはオフ）。1回の取得でまとめて読む。
- リリースのない依存は、Watchの代わりにregistryの版をReleasesに出す（ADR 0008）。
- `ghclient watch-candidates`が同じ候補を出す（`released`でリリースの有無）。AIエージェントは`ghclient watch <owner/name> --kinds releases`でWatchする。

### 関連の判定

項目（Releasesの行と、Watch中の依存先のissue・PR）ごとに、ベースプロジェクトごとの関連を求める。

決定論的な規則（毎回の取得で計算し直す）:

| ラベル | 条件 |
|---|---|
| Major update | プロジェクトが使う版より新しく、メジャーバージョンが上がっている |
| Newer than in use | プロジェクトが使う版より新しく、同じメジャーバージョン。範囲で指定していて、その範囲に入らない新しい版（Terraformの`~> 1.10.0`に対する1.16.5）も含む |
| In use | プロジェクトがこの版かそれより新しい版を使っているか、範囲がこの版を許す。表示はするが、関連には数えない。範囲は`^`、`~`、`>=`、Terraformの`~>`（`~> 5.0`は5の中、`~> 1.8.0`は1.8の中）、系列の指定（`v4`、`22`）を解釈する |
| Uses a setting | リリースノートやissueの本文に、プロジェクトの設定ファイルにあるkeyが出てくる。コードスパン（`` `key` ``）のほか、ドットを2つ以上含む語（`spring.threads.virtual.enabled`）も地の文から拾う。まとまり（`spring.security.oauth2`）はその下のkeyにも一致する。同じ語は、いくつのファイルとkeyに当たっても1つのラベルにする |
| Mentions the project | issueやPRが、プロジェクトのリポジトリ名かパッケージ名に触れている |

セキュリティ勧告（使っている版が影響範囲に入る）は、使うAPIを確かめてから後の段階で足す。

リリースとパッケージの対応は、まずWatch中のリポジトリ名とパッケージ名の既知の対応（`pnpm/pnpm`→`pnpm`、`npm/cli`→`npm`、`spring-projects/spring-boot`→`org.springframework.boot`、`gradle/gradle`→`gradle`）から始める。Mavenのgroupに対応するものは、そのidのプラグインとgroupのライブラリすべてに一致する（Spring Bootのプラグインと`spring-boot-starter-*`）。対応表にないリポジトリは、リポジトリ名と同じパッケージ名、またはartifact名に一致させる。registryで引いたリポジトリが同じ依存にも一致させる（`getsentry/sentry-java`のリリースと`io.sentry:sentry-logback`）。ラベルの版はタグのとおりに出す（`4.2.0-M2`）。

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

1. リポジトリのベースプロジェクトとディレクトリからの一括登録、改名への追従、依存するリポジトリのWatchの候補（registryでのリポジトリの解決を含む）、npm、pnpm、Gradle、Maven、GitHub Actions、Terraformのファイル（下位のディレクトリを含む）とJavaとNode.jsの版とSpringの設定の読み取り、BOMによる版の解決、決定論的な規則、Releasesでの表示と絞り込み、Settingsのカード。
2. AIの判断の記録（`ghclient`のコマンド）、根拠の確認、表示。
3. lockfileとSBOMの読み取り（推移的な依存）。
4. セキュリティ勧告、Terraformのmodule、Dockerのimageとpipなどほかのエコシステム。

## 検討した案

- アプリの中でAIを呼ぶ: APIキーの管理と、非公開リポジトリの内容を外部に送るかの判断がアプリに入る。AIエージェントがCLIで操作する方針（ADR 0004）にも合わない。不採用。
- AIの判断だけで関連を決める: コスト、再現性、裏付けの面で弱い。決定論的な規則で候補を絞り、AIは規則で判断できない部分だけを補う。
- ベースプロジェクトを1つに限る: 利用者は複数のプロジェクトを持つ。複数にし、ラベルにプロジェクト名を出す。
- GitHubの依存グラフ（SBOM API）で依存を得る: Dependabotと同じ情報で、推移的な依存も入る。しかしGradleのプロジェクトでは、dependency submissionを設定していないとGitHub Actionsしか載らなかった。build fileを読む方式にし、SBOMは段階3で併用を考える。
- BOMをSpring BootのGitHubのリポジトリ（タグのbuild script）から読む: 外部のhostが増えないが、Gradleで書かれた版の定義を解析する必要があり、書き方が版ごとに変わる。公開されたpomの方が安定しているため、Maven Centralから読む。
- 依存のリポジトリをDependabotのPRの本文から拾う（「Bumps [x](https://github.com/...)」）: registryに問い合わせずに済むが、ベースプロジェクトのPRを読む権限が別に要り、更新のあった依存しか分からない。AWS SDKのようにリンクのないPRもある。不採用。
- 依存のリポジトリをdeps.dev（Googleの依存の情報サービス）で引く: npmとMavenを1つのAPIで引けるが、送り先がパッケージの公開registryではなくGoogleになる。不採用。
- Dependabotの規則のとおり、親のpomを1段だけたどる: AWS SDKとFlywayのリポジトリが見つからない。同じgroupの親に限って何段でもたどる。
- `.npmrc`の`registry=`の上書きは、すべて公開npmの中継とみなす: 設定が要らないが、既定のregistryに非公開のパッケージを置いている場合にその名前がnpmjsに送られる。利用者が中継と指定したものだけにする。
- ディレクトリをベースプロジェクトとして直接読む: 外部に何も送らずに済むが、端末ごとに結果が変わり、ラベルの名前もリポジトリと結びつかない。一度は設計したが、利用者の判断でリポジトリ指定を基本にし、ディレクトリはリポジトリを見つける入口だけにした。

## Consequences

### Positive

- 関係のないリリースが隠れ、自分のどのプロジェクトに関係するかが行ごとにわかる。
- どの端末から見ても、同じリポジトリの内容で判定できる。

### Negative

- lockfileを読まないため、推移的な依存は判定できない。BOMがimportするBOMの中（`jackson-bom`が決めるJacksonの版など）もたどらない。
- push前の変更は判定に入らない。
- tokenにContentsの読み取り権限を足す必要がある。
- ベースプロジェクトごとに、読み直すたびにファイル一覧と、読むファイルの数だけrequestが要る（ETagで変化がなければ304）。BOMの分だけMaven Centralへのrequestが増える。依存のリポジトリの解決で、依存の数だけMaven Central、Gradle Plugin Portal、npm registryへのrequestと、依存先のリポジトリの数だけGitHubへのrequestが増える（実行中は結果を保つ）。
- AIの判断を出すには、AIエージェントを別に動かす必要がある。
- プロジェクトが多いと、行が縦に長くなる。
