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

## `organizations/` は「生成物 + 付属スクリプト」の混在ディレクトリ

Phase 2 reset スクリプトで踏んだバグ。

- `fabric-samples/test-network/organizations/` は `network.sh up` 時に生成される
  `peerOrganizations/` / `ordererOrganizations/` と、**Git 管理の付属スクリプト**
  (`ccp-generate.sh` / `cfssl/*` / `cryptogen/*` / `fabric-ca/registerEnroll.sh`
  / `fabric-ca/*/fabric-ca-server-config.yaml`) が同居している
- **`rm -rf organizations/` すると付属スクリプトまで消え、次の `network.sh up` が
  `createOrg1: command not found` 等で死ぬ**
- reset で消してよいのは生成サブディレクトリのみ:
  ```sh
  rm -rf organizations/peerOrganizations organizations/ordererOrganizations
  rm -rf channel-artifacts addOrg3/channel-artifacts
  rm -rf addOrg3/fabric-ca/org3/{msp,tls-cert.pem,ca-cert.pem,IssuerPublicKey,IssuerRevocationPublicKey,fabric-ca-server.db}
  ```
- 誤って消した場合の復旧: `cd fabric-samples && git checkout -- test-network/organizations test-network/addOrg3`

## 期待稼働コンテナ数は 8（CA は 4 個）

- peer 3 + orderer 1 + **CA 4** = 8
- CA は `ca_org1` / `ca_org2` / `ca_org3` / **`ca_orderer`** の 4 個。orderer 用 CA を忘れがち
- アサートで `7` と書くと常に失敗する

## `bin/peer` 直呼びには `FABRIC_CFG_PATH` が必須

`scripts/network_up.sh` Org3 疎通確認で踏んだ罠。

- `fabric-samples/bin/peer` を直接実行するには `core.yaml` 探索用の設定パスが必要
- `FABRIC_CFG_PATH=${SAMPLES_DIR}/config` を export しないと起動失敗（エラー不明瞭）
- test-network の `./network.sh` 経由だと内部で設定されるので気付きにくい
- Phase 4 `deploy_chaincode.sh` / `invoke_as.sh` でも同じ対応が必要

## sudo でスクリプト実行すると root 所有ファイルが残る

- WSL2 等で docker グループ未設定の環境だと `sudo ./scripts/reset.sh` 運用になる
- `network.sh up` が作る `organizations/peerOrganizations/` 等が **root 所有** になる
- 次に非 sudo で git 操作すると "Permission denied" で復旧不能
- 対策:
  - docker グループに加入（`sudo usermod -aG docker $USER` → 再ログイン）が本筋
  - 暫定: 復旧時は `sudo chown -R $USER:$USER fabric-samples` で所有権を戻してから git 操作

## MVCC_READ_CONFLICT

- 同一 key を同一ブロック内で複数 tx が更新 → 後続 tx 失敗
- デモでは直列実行なので通常発生しないが、並列 invoke する test で起きる
- 対策: テストで sleep or sequential 実行
