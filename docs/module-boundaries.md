# Module boundaries

MoonBit module間の依存方向を一方向に固定する。

```text
tanabe1478/github-client (desktop composition root)
  ├── github-client-domain
  ├── github-client-github-api
  ├── github-client-credential-store ──> github-client-app-paths
  └── github-client-repository-store ──> github-client-app-paths
                                      └─> github-client-domain
```

## Modules

### `modules/domain`

Pureなproduct modelとrelevance rule。filesystem、HTTP、GLFW、Dear ImGuiを参照しない。

### `modules/github_api`

必要なGitHub endpoint、request/response、HTTP transportを所有する。domainやstorageを参照しない。API DTOからdomainへの変換はdesktop composition rootまたは将来のapplication service moduleが担当する。

### `modules/app_paths`

OS別application data directoryだけを所有する。他のproject moduleを参照しない。

### `modules/credential_store`

PATをOS-backed storageで暗号化し、暗号文だけをfilesystemへ保存する。`app_paths`のみを参照し、domain、GitHub API、UIを参照しない。

### `modules/repository_store`

登録repositoryのfilesystem persistenceを所有する。`app_paths`とdomainの`RepositoryRef`のみを一方向に参照する。GitHub APIとUIを参照しない。

### Root module

`cmd/github_client`がcomposition rootとしてmoduleを組み合わせる。domain rule、HTTP、storageの実装を持ち込まない。

## Prohibited dependencies

- domain → storage / GitHub API / desktop UI
- GitHub API → domain / storage / desktop UI
- credential store → domain / repository store / GitHub API / desktop UI
- repository store → credential store / GitHub API / desktop UI
- app paths → 他のproject module
- module同士の循環参照
- C++ Dear ImGui bridge内へのproduct rule実装
