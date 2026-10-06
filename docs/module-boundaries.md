# Module boundaries

MoonBit module間の依存方向を一方向に固定する。

```text
tanabe1478/github-client (desktop and command-line composition roots)
  ├── github-client-domain
  ├── github-client-github-api
  ├── github-client-activity-sync ──> github-client-domain
  │                                ├─> github-client-github-api
  │                                └─> github-client-credential-store
  ├── github-client-credential-store ──> github-client-app-paths
  ├── github-client-repository-store ──> github-client-app-paths
  │                                   └─> github-client-domain
  ├── github-client-review-request-store ──> github-client-app-paths
  ├── github-client-settings-store ──> github-client-app-paths
  └── github-client-read-state-store ──> github-client-app-paths
                                      └─> github-client-domain
```

## Modules

### `modules/domain`

Pureなproduct modelとrelevance rule。filesystem、HTTP、GLFW、Dear ImGuiを参照しない。

### `modules/github_api`

必要なGitHub endpoint、request/response、HTTP transportを所有する。domainやstorageを参照しない。API DTOからdomainへの変換はdesktop composition rootまたは将来のapplication service moduleが担当する。

### `modules/activity_sync`

GitHub activityの取得手順（token選択、並列取得、失敗の記録）とAPI DTOからdomainの`ActivityItem`への変換を所有する。desktopとCLIが共有する。domain、GitHub API、credential storeのlogin labelのみを参照し、他のstorageとUIを参照しない。

### `modules/app_paths`

OS別application data directoryだけを所有する。他のproject moduleを参照しない。

### `modules/credential_store`

PATをOS-backed storageで暗号化し、暗号文だけをfilesystemへ保存する。`app_paths`のみを参照し、domain、GitHub API、UIを参照しない。

### `modules/repository_store`

登録repositoryのfilesystem persistenceを所有する。`app_paths`とdomainの`RepositoryRef`のみを一方向に参照する。GitHub APIとUIを参照しない。

### `modules/review_request_store`

viewerにreviewを依頼したpull requestのURLをfilesystemへ保存する。GitHubがteamへの依頼を外したあとも、viewerがreviewするかpull requestが閉じるまでFor youに残すために使う。`app_paths`のみを参照する。

### `modules/settings_store`

ユーザー設定を`settings.txt`へ保存する。人やAIが直接編集できるよう、コメント付きの`key = value`形式にする。`app_paths`のみを参照する。

### `modules/read_state_store`

activity URLごとの既読時点をfilesystemへ保存する。`app_paths`とdomainの`ReadMarker`のみを参照し、GitHub APIとUIを参照しない。

### Root module

`cmd/github_client`（desktop）と`cmd/ghclient`（CLI）がcomposition rootとしてmoduleを組み合わせる。domain rule、HTTP、storageの実装を持ち込まない。

## Prohibited dependencies

- domain → storage / GitHub API / desktop UI
- GitHub API → domain / storage / desktop UI
- credential store → domain / repository store / GitHub API / desktop UI
- repository store → credential store / read state store / GitHub API / desktop UI
- read state store → credential store / repository store / GitHub API / desktop UI
- activity sync → storage（credential storeのlogin label以外） / desktop UI
- app paths → 他のproject module
- module同士の循環参照
- C++ Dear ImGui bridge内へのproduct rule実装
