# ADR 0003: トリアージはアプリ内に記録し、GitHubを変更しない

- Status: Accepted
- Date: 2026-09-29（Done、Save、Unsubscribeの方式は2026-09-24のbb81c54で導入済み）

## Context

Done、Save、Unsubscribeは、どれもこのアプリの中だけで記録し、GitHub APIを呼ばない形でbb81c54から実装されている。GitHub側の既読や購読を変更しない理由は、会話にもcommitにも記録がない。

その後、GitHubの仕様と利用者の期待がずれる点が見つかった。チームの誰かがレビューを提出すると、GitHubはチームへのreview依頼を外すことがある。外れると、自分がレビューしていなくてもReview requestedから消える。利用者の要望は「レビューしないといけないことは変わらないので消えないで欲しい」だった（2026-09-29）。

## Decision

### Done、Save、Unsubscribe

- Doneは、項目の今の`updated_at`を記録する。GitHubで更新されると未読に戻る。記録は`read-state.txt`に置く。
- SaveとUnsubscribeはURLを`triage.txt`に記録する。SaveはDoneかどうかに関係なくSavedに残す。Unsubscribeは、Savedを含むすべての一覧から隠し、通知も止める。
- どれもGitHubの既読、購読、通知設定を変更しない。
- 違いと使い分けは`README.md`の「Done, Save, and Unsubscribe」に書いた。

### チームへのreview依頼を残す

- 自分にreview依頼が来たPRのURLを`review-requests.txt`に記録する。
- GitHubの一覧から消えたら、そのPRの状態とreviewを確認する。自分がレビューを提出するか、PRがcloseまたはmergeされるまで、For youに`Still needs your review`のlabel付きで残す。pendingとdismissedのreviewは提出に数えない。

## 検討した案

- GitHubの検索だけでreview依頼を出す: 外された依頼はGitHubの検索では見つけられないので、要望を満たせない。不採用。

Done、Save、UnsubscribeをGitHub APIに反映する案を検討したかどうかは、記録がない。

## Consequences

### Positive

- tokenに書き込み権限が要らない。tokenに求めるのはissue、pull request、metadataの読み取りだけ（tokenダイアログの説明文）。
- 誤って操作しても、GitHub側の状態は変わらない。

### Negative

- Unsubscribeしても、GitHubからの購読通知（メールなど）は止まらない。
- Unsubscribeした項目を一覧する画面がない。戻せるのはsnackbarのUndoか`ghclient unmute`だけ。
- 記録は端末ごとで、別の端末やGitHubのWebとは共有されない。
- 残しているreview依頼1件ごとに、取得のたびにrequestが2本増える。
