# ADR 0006: Watchごとに受け取る種類を選び、リリースはReleases画面に出す

- Status: Accepted
- Date: 2026-10-13

## Context

利用者は、pnpmの最近の動向（v12の安定版、remote cacheの追加など）をSNSで知った。これをこのアプリで知りたいという要望があった。

`pnpm/pnpm`のGitHub Releasesには、各リリースの冒頭に何が変わったかを1文でまとめた説明がある。SNS上の評判は取れないが、リリースの内容はGitHubから取れる。

一方で、`pnpm/pnpm`をWatchすると、openなPRとissueが大量に入る。利用者が知りたいのはリリースだけである。

## Decision

Watchごとに受け取る種類を選べるようにし、リリースは種類の1つにする。GitHub自身のWatchにある「Custom」と同じ考え方である。何を受け取るかの管理はWatchに1つにまとめ、リリースを読む場所としてReleases画面を設ける。

### 受け取る種類

Watch中のリポジトリごとに、次の4つを選ぶ。

| 種類 | 内容 |
|---|---|
| Pull requests | openなPR |
| Issues | openなissue |
| Releases | リリース（最新30件） |
| For you | そのリポジトリのreview依頼、assign、mention、購読 |

- 既存のWatchと、新しくWatchしたリポジトリは、Pull requests、Issues、For youが選ばれた状態から始まる。これまでの動きは変わらない。
- 取得するのは選んだ種類だけ。Releasesだけを選んだリポジトリは、1回の更新でrequestが1本で済む。
- For youは全リポジトリ分を取ってから表示時に絞っているので（ADR 0002）、For youを選んだかどうかは表示の絞り込みとreview commentの走査対象だけに効く。

### Releases画面

- navigation railのFor youの下にReleasesを置き、未読数を出す。
- Releasesを選んだリポジトリのリリースを、新しい順に1つの一覧で並べる。各行にリポジトリ名を出し、リポジトリで絞り込める。InboxとFor youにはリリースを出さない。
- Saveしたリリースは、PRやissueと同じくSavedにも出る。
- 行には、リリース名（なければtag）、リリースノートの最初の1文、作者、公開日を出す。pre-releaseにはlabelを付ける。draftのリリースは出さない。
- Done、Save、Unsubscribeは、PRやissueと同じように使える。Doneは公開日を記録する。
- 初めてReleasesを受け取るとき、公開から30日より前のリリースはDoneの状態から始める。

### リリースの通知

リポジトリごとに選ぶ。既定はMajor and minor。

| 選択肢 | 通知するもの |
|---|---|
| All | すべてのリリース |
| Major and minor | メジャーとマイナーのリリース |
| Major only | メジャーのリリース |
| Off | 通知しない |

- メジャーとマイナーはtagの番号で判定する。`x.0.0`がメジャー、`x.y.0`がマイナー、それ以外がパッチ。番号として読めないtagはマイナーとして扱う。
- pre-releaseは、Allのときだけ通知する。
- 一覧には、通知の選択に関係なくすべてのリリースを出す。

### 保存形式

`repositories.txt`を`v2`にする。1行に1リポジトリで、tab区切りで種類と通知を書く。

```
v2
pnpm/pnpm	releases	releases=major-minor
tanabe1478/github-client	pull-requests,issues,for-you	releases=major-minor
```

`v1`のファイルは読み込めるようにし、すべてのリポジトリを既定の種類として扱う。保存するときは`v2`で書く。

## 検討した案

- Watchとは別に「リリースを追う」一覧を作る: 管理する一覧が2つになる。利用者から、Watchの中で種類を選べば同じことができると指摘があった。不採用。
- リリースをInboxに混ぜる: triageの対象であるPRやissueと、読むだけのリリースが混ざる。利用者から、画面として分けてほしいという要望があった。不採用。
- For youは種類に含めず、常にWatch中のリポジトリを対象にする: Releasesだけを受け取りたいリポジトリで、購読スレッドが入ってうるさくなる。種類の1つにした。
- 通知の範囲を全体で1つにする: リポジトリによってリリースの頻度が大きく違う。リポジトリごとに選べるようにした。

## Consequences

### Positive

- 依存しているツールやライブラリのリリースを、PRやissueと混ぜずに追える。
- 必要な種類だけを取得するので、requestが減る。

### Negative

- navigation railの項目が1つ増える。
- `repositories.txt`の形式が変わる。`v2`を書いたあとは、古い版のアプリと`ghclient`では読めない。
- SNS上の評判や、つまずいている人が多い問題（issueやDiscussions）は、この変更では取れない。
