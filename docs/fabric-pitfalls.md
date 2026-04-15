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

## chaincode エラーは message 本文しか伝搬しない

Phase 3 で判明。

- `throw new Error('...')` は endorsement failure として返るが、クライアント側
  （`peer chaincode invoke` / SDK）で取得できるのは **message 本文のみ**
- `err.code` / `err.name` / カスタムフィールドはレスポンスに乗らない
- L2/L3 テストや `demo_error.sh` で「どのエラーか」を判定したい場合、
  message 先頭に識別子を埋め込むのが唯一の実用解
- 本リポの採用形式:
  ```js
  throw new ChaincodeError(ErrorCodes.OWNER_MISMATCH, '...');
  // => message = "[OWNER_MISMATCH] ..."
  ```
- これで `grep '\[OWNER_MISMATCH\]'` が使える

## GetHistoryForKey は state 変遷のスナップショット列

Phase 3 GetHistory 実装で整理したこと。

- 返り値は **key に紐づく各 putState 時点の state 全体** を新→旧の順に列挙する
  iterator。「イベントログ」ではない
- 呼び出し元の clientIdentity や引数は **履歴には残らない**。
  知りたければ state 本体に埋め込んでおくしかない
- 本リポでは `product.lastActor = { mspId, id }` を putState 毎に更新し、
  GetHistory 側で各スナップショットから復元する方式を採用
- CREATE / TRANSFER の区別も state の差分（`currentOwner` 変化）から推論する必要がある
- 順序は実装依存（一般に降順）なので、昇順表示したい場合は受け取って `reverse()` 推奨
- `isDelete === true` の entry は state 値が空なのでスキップ必須

## GetHistory の CREATE 判定は `events.length === 0` で

- 「先頭 entry = CREATE」判定を naive に `firstSeen` フラグで書くと、
  **先頭 entry が `isDelete=true`** のとき次 entry も `firstSeen` のままで CREATE 扱いされる
- 先頭 isDelete は DeleteState → 再 Create の理論ケース。通常起きないが堅牢性で抑えたい
- 対策: 判定を `if (events.length === 0)` にする。events に積まれていなければ CREATE

## L1 mock と実 fabric-shim の微妙な差分

- `ctx.stub.getState(key)` の未登録キー時の戻り値:
  - 実 fabric-shim: **`null`**
  - 自前 mock（`Buffer.from('')`）: **空 Buffer**
- contract 側は `if (!raw || raw.length === 0)` で両対応しておけば安全
- 片側だけを判定する（例: `raw === null`）と本番 vs mock で挙動割れ

## Fabric 2.5.10 以前 × Docker 29+ は chaincode install が壊れる

Phase 4 deploy で踏んだ。

- Fabric 2.5.10 以前の peer は `github.com/fsouza/go-dockerclient` を使って chaincode
  image を build する。Docker 29 / API 1.54 ではこのクライアントと daemon の
  プロトコル互換が切れ、`write unix @->/run/docker.sock: write: broken pipe` で
  install が落ちる
- peer ログに以下が出ていれば確定:
  ```
  [dockercontroller] buildImage -> Error building image: write unix @->/run/docker.sock: write: broken pipe
  [chaincode.platform] func1 -> io: read/write on closed pipe
  ```
- 直前に `[ccaas_builder] ::Error: chaincode type not supported: node` が出るのは別物で、
  ccaas external builder が node type を扱えないだけ。問題は次段の dockercontroller fallback
- **対策: Fabric を v2.5.15 以上に上げる**
  - 修正 PR: hyperledger/fabric#5355（`go-dockerclient` → `moby/client` 置換）
  - `scripts/setup.sh` の `FABRIC_VERSION` / `CA_VERSION` を更新 → `./scripts/reset.sh --yes`
    → `./scripts/setup.sh --force` → `./scripts/network_up.sh` → `./scripts/deploy_chaincode.sh`
- 言語を Go に書き直しても解決しない。`dockercontroller.buildImage` 経路は node/go 共通で踏む
- 根因は **pin 時に upstream 最新を確認しなかった** こと。2.5.10 は 2024-09 リリース、
  2.5.15 は 2026-02。pin する瞬間に GitHub releases を叩く運用必須

## MVCC_READ_CONFLICT

- 同一 key を同一ブロック内で複数 tx が更新 → 後続 tx 失敗
- デモでは直列実行なので通常発生しないが、並列 invoke する test で起きる
- 対策: テストで sleep or sequential 実行
