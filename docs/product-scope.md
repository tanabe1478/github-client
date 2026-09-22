# Product scope

## Product image

このアプリはGitHub全体を再実装する汎用クライアントではなく、ユーザーが登録したrepositoryを中心とする関連activity inboxである。

表示対象:

1. 登録repositoryのpull requestとissue
2. ユーザーへのmentionと参加中threadの更新
3. 登録repositoryが依存するrepositoryのpull requestとissueのうち、登録repositoryへ影響するもの

すべてのdependency repository activityを通知するとnoiseになるため、dependency側は関連理由を説明できる項目だけを採用する。

## Relevance reasons

各inbox itemは最低1つの理由を持つ。

- `RegisteredRepository`: 登録repository自身のactivity
- `ViewerMention`: ユーザーがmentionされたactivity
- `DependencyImpact`: dependency repositoryの変更が登録repositoryへ影響するactivity

`DependencyImpact`の初期signal:

- 登録repositoryまたはpackage名への明示的な参照
- linked issue / pull request
- 利用versionへ影響するsecurity advisory
- dependency update PRから辿れるupstream issue / pull request

単にdependency repositoryで作られたという理由だけではinboxへ入れない。

## Minimal GitHub API surface

包括的SDKには依存せず、必要なendpointとresponse型だけを`github_api/`へ実装する。

初期endpoint:

- `GET /user`
- `GET /notifications`
- `GET /repos/{owner}/{repo}`
- `GET /repos/{owner}/{repo}/issues`
- `GET /repos/{owner}/{repo}/pulls`
- `GET /repos/{owner}/{repo}/dependency-graph/sbom`

必要になった時点で、issue/pull detail、timeline、search、GraphQL dependency metadataを個別に追加する。未使用APIを先回りして実装しない。

## Delivery order

1. repositoryを手動登録してlocal保存
2. PATを使った`GET /user`接続
3. 登録repositoryのissue/pull取得
4. notification/mentionを統合したInbox
5. SBOMからdependency候補を抽出
6. dependency repositoryの関連判定
7. polling、既読、desktop notification
8. Device Flowとsecure token storage
