# ADR 0005: 画面設計はClaude Designのcanvasに置き、実装と同期させる

- Status: Accepted
- Date: 2026-09-29

## Context

Figmaでの設計管理を一度導入し、その後外した（52b27c4、1062f50、028a170）。導入と削除の理由は記録がない。

2026-09-29、利用者から「Claude Designを使ってデザインを考え直して。使いづらい」という依頼があった。当時の画面には次の問題があった。

- 1行ごとに4つのボタンが同じ重さで並び、本文の幅を奪っていた。そのためタイトルが3〜5行に折り返していた。
- Inboxにリポジトリの区別がなく、PRとissueが混ざって並んでいた。
- dependabotの更新PRが一覧の大半を占めていた。

## Decision

- 画面設計はClaude Designのcanvas「GitHub Client Redesign」に置く。Inbox、For you、Saved、Repositories、Settingsに加え、行の状態、ローディング、エラー、トランジション、初回起動、tokenダイアログ、通知をartboardとして持つ。
- 実装はcanvasに沿って描画する。実装を変えたら、canvasを実際の画面に合わせて更新する。
- 振る舞いの仕様は`docs/screens.md`に書く。振る舞いと見た目の実装の正は、リポジトリのコードとドキュメントである（`AGENTS.md`）。canvasは設計の参照元で、実装と食い違ったら実装に合わせて直す。
- READMEの画面画像は、canvasのartboardを`scripts/design/render-design.cjs`で描画して作る。

FigmaではなくClaude Designを選んだ理由（両者の比較）は記録がない。

## Consequences

### Positive

- 実装前に、ローディングやエラーまで含めた画面を一通り検討できた。
- READMEの画像をcanvasから作り直せる。

### Negative

- canvasはリポジトリの外にあり、コードと同じreviewやhistoryに乗らない。実装を変えたら手で同期させる必要がある。
- canvasには実際のリポジトリ名やPRのタイトルが入っている。canvasは非公開だが、READMEの画像を作るときは名前を架空のものに置き換えてから描画する必要がある（2026-09-30に、置き換えずに公開してしまい、履歴を書き換えた）。
- canvasとフォント、余白、件数などの細部が実装と一致しない。
