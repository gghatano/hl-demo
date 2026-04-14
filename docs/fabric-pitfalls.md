# Fabric 落とし穴集

実装時に踏みやすい罠。CLAUDE.md から参照。

## 決定性（最重要）

### NG API
- `Date.now()` / `new Date()` — endorsement ごとに値割れ → MVCC_READ_CONFLICT
- `Math.random()` — 同上
- `process.env.*` — peer ごとに異なる可能性
- ファイル I/O / HTTP / DB — 副作用 禁止

### OK
- `ctx.stub.getTxTimestamp()` — 全 endorsement で同値
  ```js
  const ts = ctx.stub.getTxTimestamp();
  const iso = new Date(ts.seconds * 1000 + ts.nanos / 1e6).toISOString();
  ```
- `ctx.stub.getTxID()` — 同上

## History

### GetHistoryForKey 仕様
- 返り値 順序: 実装依存だが一般に降順（新 → 旧）
- 昇順表示したい → 結果配列を reverse
- `IsDelete === true` の entry はスキップ推奨
- tombstone 保持 期間は peer 設定依存

### state に history を入れない
- `history: []` を Product オブジェクトに保持すると、state 肥大化 + 二重管理
- GetHistoryForKey で再構成すれば十分

## Endorsement Policy

### デフォルトの罠
- chaincode commit 時 `--signature-policy` 省略 → channel 既定（majority）
- 3Org channel で majority = 2 Org endorsement 必要
- `invoke_as.sh` が単一 peer のみ target → commit 失敗

### 対策
- commit 時 明示:
  `--signature-policy "OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')"`
- もしくは invoke 時 複数 `--peerAddresses` 指定

## MSP / Identity

### actor 取得
- `ctx.clientIdentity.getMSPID()` → 呼出元 MSP ID（例: `Org1MSP`）
- `ctx.clientIdentity.getID()` → X.509 subject DN
- spec 10.2 の `actor` は MSPID + user id の組合せ推奨
- MSP ID と業務語彙の対応（Issue #1 決定事項）:
  - `Org1MSP` = メーカー A / `Org2MSP` = 卸 B / `Org3MSP` = 販売店 C

### 初期所有者 検証
- `CreateProduct` 時 `clientIdentity.MSPID === 'Org1MSP'` を必須（メーカー A のみ登録可能）
- `initialOwner === manufacturer` 検証も並行

## test-network 3Org 化

### 罠
- test-network は 2Org 固定
- `addOrg3` サンプルは「後から追加」用 → チャンネル作成後 join
- 最初から 3Org で start するには `configtx.yaml` / crypto-config 編集必要
- MSP ID は fabric-samples 標準の `Org1MSP` / `Org2MSP` / `Org3MSP` をそのまま採用（Issue #1）

### 対策
- test-network 標準フロー使用:
  - `./network.sh up createChannel -c supplychannel -ca`
  - `./addOrg3/addOrg3.sh up -c supplychannel -ca`
- 業務語彙は T5-3 出力整形層で変換

## Docker / ネットワーク

### chaincode コンテナ残留
- `dev-peer*.product-trace*` コンテナ + image が残る
- reset 時 明示削除必須:
  ```sh
  docker ps -aq -f name=dev-peer | xargs -r docker rm -f
  docker images -q 'dev-peer*' | xargs -r docker rmi -f
  ```

### volume / network
- `net_test` / `docker_orderer.example.com` 等 残留で再 start 失敗
- reset で明示削除

### ポート衝突
- 7050 (orderer) / 7051 (peer0 Org1) / 9051 (peer0 Org2) / 11051 (peer0 Org3)
- WSL2 で他アプリ占有に注意

## WSL2

- メモリ 4GB 未満 → chaincode build OOM
- `.wslconfig` で 8GB 推奨

## reset 時の "no such volume" エラー

`network.sh down` 実行時に以下のエラーが出るが **無視してよい**:
```
Error response from daemon: get docker_orderer.example.com: no such volume
Error response from daemon: get docker_peer0.org1.example.com: no such volume
```
- 原因: test-network が旧 `docker-compose` プレフィックス付き volume（`docker_*`）を互換目的で削除試行
- 現行 Docker Compose v2 は `compose_*` プレフィックスを使うため対象 volume 不在
- 実害なし。`scripts/reset.sh` は最終 `verify_clean` で残留確認するため、エラー見逃しリスクなし

## busybox:latest 取得

`network.sh down` 初回実行時に `busybox:latest` が pull される。
- test-network 内部のクリーンアップに使用
- 想定動作、停止してはいけない

## MVCC_READ_CONFLICT

- 同一 key を同一ブロック内で複数 tx が更新 → 後続 tx 失敗
- デモでは直列実行なので通常発生しないが、並列 invoke する test で起きる
- 対策: テストで sleep or sequential 実行
