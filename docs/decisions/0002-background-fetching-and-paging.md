# ADR 0002: GitHubからの取得をbackground jobで行い、一覧は上限付きで最後のページまで読む

- Status: Accepted
- Date: 2026-09-29（background化は2026-09-25の会話で決定）

## Context

当初の取得は描画loopの中で同期的に走っていた。Refreshを押すと取得が終わるまでevent処理も描画も止まり、cursorがローディング表示のまま固まったように見えた。インストール版がHTTPの読み込みで1日以上止まったこともある。止まった原因は特定していない。

起動時の取得は50.6秒かかっていた。

一覧は、リポジトリごとにopenなPRとissueを新しい順に50件ずつ、review依頼の検索も50件だけ取っていた。それより古い項目は黙って抜け落ちていた。

利用者の要望は「基本的に漏れは無いようにしたい。その上である程度はパフォーマンスも問題ないようにしたい」だった。

## Decision

### Background job

- 取得は1つずつ順番に走るjobとして、描画とは別のtaskで実行する。windowは取得中も描画を続ける。
- job内では、token、For youの各一覧、Watch中のリポジトリを並行して取得する。
- jobには90秒のtimeoutを付ける。timeoutやCancelのときは、止まったtaskの終了を待たずにjobを見捨てて次へ進む。見捨てたjobの結果が後から届いても反映しない（generationで判定する）。
- 表示中の一覧は、取得が完了したときにだけ差し替える。
- 画面の出し方（skeleton、loading dialog、線形bar）は`docs/screens.md`の「Loading state」に従う。

### Paging

- 1ページ100件（APIの上限）で、最後のページまで読む。
- 上限は、リポジトリごとのPR一覧とissue一覧がそれぞれ20ページ（2,000件）、For youの各一覧が10ページ（1,000件）。review依頼の検索はGitHub側の上限も1,000件である。
- 上限に達した一覧は、黙って切らずにwarning bannerで名前を出して知らせる。

### 条件付きrequest

- 前回の応答のETagを`If-None-Match`で送る。変化がなければGitHubは304を本文なしで返す。
- ETagはprocessのmemoryにだけ保持する。

### 記録の掃除

- InboxとFor youを誤りなく最後まで読めた更新のあとで、どの一覧にも現れなくなったURLのDoneとUnsubscribeの記録を消す。Savedは消さない。

### リクエストのタイミング（2026-10-08に追加）

変更の影響を受ける部分だけを取得する。きっかけごとの取得内容は`docs/screens.md`の「Fetching」の表に従う。

- Watchでは、追加したリポジトリのPR、issue、review commentのmentionと、mergedやclosedのmentionだけを取る。For youは全リポジトリ分を取ってから表示時にWatch中のものへ絞っているので、取り直さない。操作を止めるdialogは出さない。
- Unwatchでは何も取らない。
- アプリの外でのWatch追加は、追加されたリポジトリだけを取る。
- Mentionの設定を変えたら、設定で決まる部分（mergedとclosedのmention、review commentのmention）だけを取り直す。open mentionはそのまま残す。
- 画面の切り替えでは取得しない。navigation railの未読数と通知は、画面を開いていなくてもデータが要るからである。鮮度は5分ごとの自動更新と手動のRefreshで保つ。
- 起動、tokenの追加と削除、bannerのRetryは、tokenとリポジトリの対応が変わりうるので全体を取り直す。

きっかけは、Watchのたびに追加したリポジトリと関係のないFor you全体まで取り直し、操作を止めていたことである。

## 検討した案

- 取得を同期のまま、loading表示を前面に出す: 描画loop自体が止まるので表示を更新できない。不採用。
- 取得件数を固定（50件など）のままにする: 漏れが出る。不採用。
- 画面を表示したときにだけ取得する: navigation railの未読数と通知が古くなる。不採用。
- 上限なしで最後まで読む: 巨大なリポジトリで取得が終わらなくなるおそれがある。上限を置き、超えたことを知らせる形にした。2,000件と1,000件という値は「念のため」の上限で、それ以上の根拠は記録がない。

## 計測

同じ手順で変更前後を測った。

| 項目 | 変更前 | 変更後 |
|---|---|---|
| 起動時の取得（background化と並行取得） | 50.6秒 | 14.3、6.8、6.9秒 |
| 起動時の取得（paging追加の前後） | 29.4、7.1、6.3秒 | 17.4、7.2、7.2秒（requestは前後とも37本） |
| 行データの作成（Doneの記録 約5,000件、Inbox） | 4.78 ms | 1.46 ms |
| 同（For you） | 3.92 ms | 1.38 ms |

ETagは速さには効かなかった。同じ16本で、200の平均895 msに対し、304の平均938 msだった。

リクエストのタイミングを整理した前後のリクエスト数（token 4つ、Watch中のリポジトリ14件、実データの複製、2026-10-08）:

| 操作 | 変更前 | 変更後 |
|---|---|---|
| Watch（`octocat/Hello-World`。openなPRとissueが特に多い） | 81（追加分34、For you分47） | 39（追加分35、merged・closed mention 4） |
| Watch（`moonbitlang/core`） | 未計測 | 8 |
| Unwatch | 37 | 0 |
| アプリの外でのWatch追加（`moonbitlang/core`） | 未計測（InboxとFor you全体を取り直していた） | 8 |
| Mentionの設定変更 | 未計測（For you全体を取り直していた。For youのRefreshは46〜47） | 21 |

Watchの追加分が34から35に増えたのは、review commentが2ページになったためである。

## Consequences

### Positive

- 取得中もwindowが動き、Cancelできる。
- 上限までは漏れがなく、上限を超えたら利用者が気づける。

### Negative

- 見捨てたtaskは、processが終わるまで裏で動き続けることがある。HTTP library（moonbitlang/async）の読み取りがcancelを受け付けていない可能性が高いが、原因箇所は特定していない。
- ETagの効果は通信量の削減と、304がrate limitを消費しないことに限られる。後者はGitHubのドキュメントによるもので、未検証。
- ETagはmemoryにしかないので、起動直後の取得には効かない。
