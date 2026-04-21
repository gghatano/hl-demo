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

## chaincode package に node_modules を含めると peer build が broken pipe で落ちる

Phase 4 deploy で Fabric を 2.5.15 に上げる前に踏んだ二次的な罠。

- `peer lifecycle chaincode package` は `--path` 配下を丸ごと tar する
- Node chaincode は開発中に `npm install` で `node_modules/` を作る (L1 テスト用)
- そのまま `--path chaincode/product-trace` すると node_modules 込みの tar を
  peer に送り込み、peer 側の docker build で context が肥大 → stream 切れ
- 症状は Docker 29 互換問題と似た `broken pipe` だが、root cause が別
  (Docker 互換問題は 1 回の install がそもそも通らない、こちらは package 肥大化)

**対策**: staging ディレクトリ経由で不要物を除外してから package する
```bash
STAGE=build/stage-${CC_NAME}
rm -rf "${STAGE}" && mkdir -p "${STAGE}"
tar --exclude='node_modules' --exclude='test' --exclude='coverage' \
    -C "${CC_SRC}" -cf - . | tar -C "${STAGE}" -xf -
peer lifecycle chaincode package ... --path "${STAGE}"
```

fabric-samples が `.fabricignore` を認識しないため、ignore ファイル方式は不可。
staging が唯一の実用解。

## lifecycle chaincode の skip 判定は seq/ver だけでなく package_id まで見る

Phase 4 deploy レビューで指摘された Major。

- `peer lifecycle chaincode queryapproved` は approved 済定義を JSON で返す。
  構造 (2.5.15 時点):
  ```json
  {"version":"1.0","sequence":1,
   "source":{"Type":{"LocalPackage":{"package_id":"<label>:<sha>"}}}}
  ```
- 「再 approve するか」を seq/ver 一致だけで判定すると、chaincode ソースが変わり
  package hash (sha256) が変わっても「approve 済」扱いになり、commit 段の
  checkcommitreadiness を通過してしまい、invoke 時に古い approval と新 install の
  不整合で壊れる。CI が無いと発見が遅れる
- 正しい skip 判定:
  ```bash
  queryapproved --output json \
    | jq -e --arg v "$V" --argjson s "$S" --arg p "$PKG_ID" \
        '.version==$v and .sequence==$s
         and .source.Type.LocalPackage.package_id==$p'
  ```
- 同様に `querycommitted` は `checkcommitreadiness` より **先** に実行すべき。
  既 commit 済 seq を readiness に渡すと
  `requested sequence is X, but new definition must be sequence X+1` で落ちる
- `queryinstalled` のパースも `grep "Label: ..."` ではなく JSON + jq。
  Label 部分一致で別 CC にヒットする穴を塞ぐ

## MVCC_READ_CONFLICT

- 同一 key を同一ブロック内で複数 tx が更新 → 後続 tx 失敗
- デモでは直列実行なので通常発生しないが、並列 invoke する test で起きる
- 対策: テストで sleep or sequential 実行

## peer CLI ログ抑制 (demo 向け)

Phase 5 demo_normal.sh で遭遇。

- `peer chaincode invoke` の成功時ログ (ClientWait committed / status:200 payload...)
  は **stderr** に出る。`>/dev/null` だけではナレーションが埋もれる
- demo 系は `>/dev/null 2>&1` で両方抑制し、整形済の ReadProduct / GetHistory 出力で
  結果を見せる。ただし L2 test や demo_error は stderr を握って errorCode 抽出するので
  一律 `2>&1` は不可
- エラーメッセージは `peer chaincode invoke` の non-zero 終了 + stderr 本文に乗る。
  成功時 stderr は INFO 多発、失敗時 stderr は ERROR メッセージ、という非対称を前提に
  scripts を書き分ける

## bash サブシェルでテスト集計すると親の値を継承する

Phase 5 T5-5 test_integration.sh で遭遇。

- ケースを `( source "${c}" )` でサブシェル化すると、構文エラー脱出や `set -e` の
  波及を親から隔離できる → 1 件の壊れたケースで全停止しなくなる
- 罠: 子シェルは親の環境変数 (TC_PASS 等) を **初期値として継承** する。子が
  加算すると、子が書き出すのは「親の前回値 + 子の差分」。親がそれを単純加算すると
  二重計上する
- 対策: 子シェルの先頭で `TC_PASS=0 TC_FAIL=0 FAILED_CASES=()` と明示リセットし、
  子は差分のみを tempfile に書く。親は差分として加算する
- 再現性のデバッグ: L2 ケース数を意図的に知っている状態で動かして `total` が膨らむか
  を最初にチェック。pass/fail 数だけ見て OK 判定すると気付けない

## reset.sh の確認プロンプトを --fresh 系スクリプトから呼ぶ場合

Phase 5 T5-5 test_integration.sh / T5-1 demo_normal.sh で遭遇。

- `reset.sh` は破壊的操作のため `read -p "続行しますか? [y/N]"` の対話確認あり
- `test_integration.sh --fresh` / `demo_normal.sh --fresh` から `reset.sh` を呼ぶと
  ここで止まり、tail -200 しか見ていないと「キャンセル」の一行だけ流れて
  理由不明で失敗に見える
- 呼び出し側は `reset.sh --yes` を明示的に渡す。直接コマンドラインで実行するとき
  のみ確認を効かせる、というのが正しい設計
- `--fresh` フラグ自体が「破壊を許可する」意図表明なので二重確認は不要

## docker logs / docker rm に dev-peer ワイルドカードは渡らない

Phase 6 T6-1 README のトラブルシュート節で遭遇（レビュー指摘）。

- chaincode コンテナ名は `dev-peer0.org1.example.com-product-trace_1.0-<hash>` の
  ようにビルドごとに hash サフィックスが変わる
- ドキュメントで `docker logs dev-peer0.org1.*product-trace_1.0-* | tail` と
  書きたくなるが、**docker logs は引数に glob を展開しない**。bash の glob も
  コンテナ名はファイル名ではないため `*` がそのまま渡って失敗する
- 正解: `docker ps --format '{{.Names}}' | grep ...` で名前を動的取得し変数経由:
  ```bash
  DEV_CC=$(docker ps --format '{{.Names}}' | grep '^dev-peer0.org1.*product-trace' | head -1)
  [[ -n "$DEV_CC" ]] && docker logs "$DEV_CC" | tail -100
  ```
- `docker rm` も同じ。reset.sh では `docker ps -aq --filter 'name=dev-peer'` で
  ID を拾う設計になっている。ドキュメントのコピペコマンドもこの形に揃える

## デモ所要時間は invoke レイテンシ起点で見積もる

Phase 6 T6-2 demo-scenarios.md の所要時間表で遭遇（レビュー指摘）。

- Fabric invoke は endorsement + ordering + commit + peer validate を通るため
  **1 回あたり実測 3〜6 秒** が下限
- 正常系 N1〜N3 だけで invoke 3 + query 2 = 15〜30 秒が固定消費。これに
  `DEMO_PAUSE` とナレーション音読を足すと「5 分ちょうど」はタイト
- 初期見積もりは「5〜10 分」の幅で書き、Phase 7 のクリーン VM リハで実測校正する。
  一度固めるとナレーションの「間」も設計できる
- `demo_normal.sh` の `PAUSE="${DEMO_PAUSE:-1.2}"` は意図的な呼吸。0 にすると
  タイムは縮むがナレーションが棒読みになる副作用あり

## Docker Desktop (macOS) の socket proxy は Fabric chaincode install を壊す

Phase 4 deploy で Colima 移行前に踏んだ。Linux 側では起きないので混乱しやすい。

- macOS Docker Desktop は container が `/var/run/docker.sock` を bind-mount すると、
  透過的に `/run/host-services/docker.proxy.sock` に差し替える（Extensions 用の
  権限制限付きプロキシ）。ユーザー設定で無効化する手段は無い
- 確認: `docker inspect peer0.org1.example.com --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'`
  に `docker.proxy.sock -> /host/var/run/docker.sock` が出れば該当
- このプロキシは build API の `pull=1` + 直後の container 作成シーケンスで
  image 解決に失敗する。症状:
  ```
  Error: chaincode install failed with status: 500 ...
  docker build failed: Error creating container:
  Error response from daemon: No such image: hyperledger/fabric-nodeenv:2.5
  ```
- image 自体は daemon 側に存在する (`docker images` で見える)。
  host 側で `DOCKER_BUILDKIT=0 docker build --pull` を直接叩くと成功するので紛らわしい
- containerd image store の ON/OFF は直接の原因ではない
  (OFF にして overlay2 に戻しても proxy 経由では壊れたまま)
- **対策: Colima に移行**
  ```sh
  brew install colima
  colima start --cpu 4 --memory 6 --disk 30
  docker context use colima
  # Docker Desktop は Quit しておく（context 混乱防止）
  ```
  - Colima は native に近い docker VM を立てる → プロキシ無し
  - 既存 compose / scripts / DOCKER_HOST 経路は無変更で動く
- 代替案（いずれも割に合わない）:
  - Docker Desktop の TCP daemon (`tcp://localhost:2375`) 有効化 + patches/
    で `CORE_VM_ENDPOINT=tcp://host.docker.internal:2375` 書換
    → セキュリティ劣化 + fabric-samples 更新時のパッチ追従
  - CCAAS external builder に chaincode refactor → Phase 3 相当の変更量
- Linux 側開発者は native dockerd 直結で proxy 非経由。この罠は発生しない

## macOS 標準 bash は 3.2 固定 → bash 4+ syntax 不可

Apple のライセンス方針 (GPLv3 拒否) で macOS 同梱 bash は **3.2.57** で凍結。
`brew install bash` しない限り `/bin/bash` も `/usr/bin/env bash` も 3.2 を引く。

- 踏みやすい bash 4+ 構文:
  - `${var,,}` / `${var^^}` — 大小文字変換 → `bad substitution`
  - `declare -A` — 連想配列
  - `mapfile` / `readarray`
  - `[[ -v VAR ]]` — 変数存在チェック (4.2+)
- 症状例: `./scripts/reset.sh: line 54: ${ans,,}: bad substitution`
- Linux 側 (bash 5+) では普通に動くので CI 通過 → 手元 macOS で初めて判明する
- **対策: bash 3.2 互換で書く**
  - 小文字変換は `case` 分岐:
    ```bash
    case "${ans}" in
      y|Y|yes|YES|Yes) return 0 ;;
      *) return 1 ;;
    esac
    ```
  - 連想配列は避け、配列 + 線形探索で代替
- 予防: CI or pre-commit で `shellcheck -s bash scripts/*.sh` を回す
  (shellcheck は `#!/usr/bin/env bash` でも `-s bash` 指定時に 3.2 互換警告を出す)

## 「稼働コンテナ数」で健全性判定しない

Phase 6 T6-3 architecture.md で遭遇（レビュー指摘）。

- fabric-samples test-network は `-ca` オプションや CLI コンテナの有無で
  稼働コンテナ数が 8 / 9 / 10 と揺れる
- 「期待稼働 8 個」はその環境固有の観測値で普遍ではない。ドキュメントには
  「約 N 個」「環境により ±1」と注記するか、**名前で判定** する
  (`docker ps --filter 'name=peer0.org' | wc -l` 等)
- 自動化の健全性チェックも数ではなく期待名の存在を grep するのが堅い
