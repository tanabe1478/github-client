# ADR 0008: GitHubのリリースで追えない依存は、registryの版をReleasesに出す

- Status: Accepted
- Date: 2026-10-15

## Context

ADR 0007で、ベースプロジェクトの依存のうち、GitHubのリポジトリが分かるものをWatchの候補にした。Watchしたリポジトリのリリースが、Releasesに入る。

しかし、GitHubのリリースで追えない依存がある。

- ソースがGitHubにない。nimbus-jose-jwtはBitbucketにある。
- GitHubのリポジトリがリリースを作らない。Apacheのcommons、bc-java、forbidden-apis、dotenvはタグかCHANGELOGだけである。
- registryの情報からソースが分からない。

Dependabotは、これらの依存にもPRを作る。Dependabotは新しい版を、ソースのリポジトリではなくregistryの版の一覧（Maven Centralの`maven-metadata.xml`など）から知る。PRの本文は、ソースのリポジトリのリリースかCHANGELOGから作る（dependabot-coreの`metadata_finders/base/changelog_finder.rb`）。nimbus-jose-jwtのPRは、BitbucketのCHANGELOG.txtから本文を作っている。

## Decision

GitHubのリリースで追えない依存は、registryの版の一覧から新しい版を知り、Releasesにリリースと同じ形で出す。

### 対象

ベースプロジェクトの依存のうち、ADR 0007でregistryに問い合わせたもの（npm、Maven、Gradleのプラグイン）で、次のどれかに当たるもの。

- ソースがGitHub以外のhost（Bitbucket、GitLab）にある。
- ソースのGitHubのリポジトリにリリースがない。または、見つからない。
- registryの情報からソースが分からない。

GitHubのリリースがある依存は、これまでどおりWatchで追う。同じ版が2回出ないようにするためである。

### 版

- npmはregistryの文書（`registry.npmjs.org/<name>`）の`versions`と`time`、MavenとGradleのプラグインは`maven-metadata.xml`の`versions`から取る。版の一覧は増えるので、キャッシュしない。
- Dependabotと同じく、依存ごとに1件だけ出す。使っている版より新しい、最新の安定版である。いくつかのプロジェクトが違う版を使うときは、一番古い版と比べる。
- pre-release（`-beta.1`、`-M2`、`-RC1`、`.Beta1`、`SNAPSHOT`など）は、使っている版がpre-releaseのときだけ対象にする。
- 公開日は、npmは`time`のとおりにする。Mavenは版ごとの公開日がないので、`<lastUpdated>`（最後に版が足された日時）を使う。古い版があとから足されると、ずれることがある。
- Gradleのプラグインと、そのライブラリが同じソースのリポジトリから来るとき（forbiddenapis）は、ライブラリの方だけを出す。DependabotがこれらをPR1つにまとめるのと同じである。

### 本文

- ソースのリポジトリの最上位にあるCHANGELOGを読む。名前はDependabotと同じく、`changelog`、`news`、`changes`、`history`、`release`、`whatsnew`、`releases`で始まり、拡張子が`.md`、`.txt`、`.rst`などのものを、この順に探す（`RELEASE-NOTES.txt`も含む）。
- GitHubはtokenを付けて、BitbucketとGitLabはtokenなしで、公開のAPIとraw fileから読む。送るのはリポジトリの名前だけである。
- 本文は、使っている版の次から最新の版までの節にする。CHANGELOGは新しい順と古い順のどちらでも読む。使っている版の見出しがなければ、最新の版の節だけにする。最大20000文字にする。
- 一覧に出す1文は、最新の版の節にある最初の項目にする。`### Changed`のような小見出しは飛ばす。CHANGELOGがなければ「A new version on Maven Central.」などと出す。

### 表示と扱い

- Releasesの行は、リポジトリ名の代わりにパッケージ名（`com.nimbusds:nimbus-jose-jwt`、`@types/node`）、タイトルに版を出す。リンクはregistryの版のページ（Maven Central、Gradle Plugin Portal、npm）にする。
- 関連（ADR 0007）は、パッケージ名で使っている依存に結び付ける。Related onlyと、プロジェクトでの絞り込みも同じように効く。
- Done、Save、既読は、GitHubのリリースと同じくURLごとに記録する。新しい版が出ると別の項目になる。
- Releasesの説明文に、registryから来た版の数を出す。
- ベースプロジェクトを読むたび（起動時、追加、Rescan、設定の変更）に取り直す。
- 通知はしない。

`ghclient releases`にも同じ項目を入れる。

## 検討した案

- 版ごとに1件ずつ出す: GitHubのリリースと同じ形になるが、毎日のように版を出すパッケージで一覧が埋まる。Dependabotと同じく最新の1件にする。
- GitHubのリリースがある依存も、registryの版で出す: Watchしなくても追えるが、Watchしたリポジトリのリリースと同じ版が2回出る。Watchの候補（ADR 0007）と役割を分ける。
- Mavenの版ごとの公開日を、版ごとのpomの`Last-Modified`で取る: 正確だが、版ごとにrequestが1本増える。`<lastUpdated>`にした。
- 通知する: GitHubのリリースはWatchごとに通知を選べる（ADR 0006）。registryの版にはWatchがなく、選ぶ場所がない。まずは一覧に出すだけにする。

## Consequences

### Positive

- Dependabotが追う依存のうち、GitHubのリリースで追えないものも、Releasesで新しい版と変更点が分かる。
- 使っている版から最新までの変更が、1つの項目で読める。

### Negative

- ベースプロジェクトを読むたびに、registryの版の一覧と、CHANGELOGの分だけrequestが増える。
- 起動したままでは、ベースプロジェクトを読み直すまで新しい版に気づかない。
- CHANGELOGの見出しの書き方によっては、節を切り出せない。そのときは本文がない。
- Mavenの公開日は、古い版をあとから足したパッケージではずれる。
