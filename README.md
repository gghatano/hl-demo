# hl-proto — Hyperledger Fabric サプライチェーン・トレーサビリティ PoC

Hyperledger Fabric 上で、製品 `X` が **A（メーカー）→ B（卸）→ C（販売店）** と流通する来歴を台帳に記録し、最後に **販売店 C の立場で「この製品が本当に A を起点として流通したか」を検証できる** ことを示すローカルデモ環境。

> **Status**: Phase 5 完了（2026-04 時点）。3Org ネットワーク起動 / chaincode デプロイ / 正常系・異常系デモ / L2 結合テストまで動作。Phase 6 でドキュメント整備中。

---

## 目次

- [何を見せるデモか](#何を見せるデモか)
- [技術スタック](#技術スタック)
- [ディレクトリ構成](#ディレクトリ構成)
- [前提ソフトウェア](#前提ソフトウェア)
- [セットアップ手順](#セットアップ手順)
- [デモ実行手順](#デモ実行手順)
- [正常系の期待結果](#正常系の期待結果)
- [異常系の期待結果](#異常系の期待結果)
- [クリーンアップ手順](#クリーンアップ手順)
- [よくあるエラーと対処](#よくあるエラーと対処)
- [テスト](#テスト)
- [関連ドキュメント](#関連ドキュメント)

---

## 何を見せるデモか

### ゴール

3 社（A / B / C）で共有する改ざん困難な台帳の上に、製品単位の譲渡履歴を記録し、**販売店 C の立場から起点 A を証明する** ことを実演する。

### 正常系フロー（spec §9.1）

1. **N1 製品登録**: メーカー A が `X001` を新規登録（A のみ実行可能）
2. **N2 A→B 移転**: A が `X001` を卸 B へ譲渡
3. **N3 B→C 移転**: B が `X001` を販売店 C へ譲渡
4. **N4 C による来歴確認**: C が履歴を照会し `CREATE(A) → TRANSFER(A→B) → TRANSFER(B→C)` を確認

各イベントには **ブロック確定時のタイムスタンプ / txId / 実行主体の MSP ID** が記録され、後から書き換え不可。

### 異常系フロー（spec §9.2）

| シナリオ | 期待結果 |
|---|---|
| E1: 所有者偽装（C が B を騙って横取り） | `[OWNER_MISMATCH]` で endorsement 失敗 |
| E2: 未登録 productId を照会 | `[PRODUCT_NOT_FOUND]` |
| E3: 既存 productId を重複登録 | `[PRODUCT_ALREADY_EXISTS]` |

「書けないはずのものは、書けない。失敗しても履歴は汚染されない」を見せるのが狙い。

### 検証できる技術要素

- **3Org 間の state 同期**: A の invoke が C の peer から即座に query できる
- **endorsement policy**: `OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')` 明示
- **決定性 chaincode**: `ctx.stub.getTxTimestamp()` で時刻生成 → 全 endorser 同一結果
- **MSP による主体証明**: C が B の名義で invoke しても chaincode 層で拒否
- **GetHistoryForKey**: 過去 state のスナップショット列挙

### 非対象

- 本番可用性 / 性能
- **物理製品と productId の対応保証**（QR / RFID / IoT 連携は別レイヤー）
- Web UI / 可視化（CLI のみ）
- 外部 ERP / 在庫管理システム連携
- Fabric CA 発行の end-user cert による認可（現状は Admin MSP 固定）

詳細は [`docs/spec.md`](docs/spec.md) を参照。

---

## 技術スタック

| レイヤ | 採用 | バージョン | 備考 |
|---|---|---|---|
| 台帳基盤 | Hyperledger Fabric | **2.5.15** | Docker 29+ 対応のため 2.5.15 以上必須 ([fabric-pitfalls.md](docs/fabric-pitfalls.md)) |
| 認証局 | Fabric CA | **1.5.18** | test-network 標準構成 |
| ネットワーク雛形 | fabric-samples test-network + addOrg3 | pin 済 | 3Org 化 (`network.sh up` → `addOrg3.sh up`) |
| コンセンサス | Raft orderer (単一) | — | PoC 用途 |
| chaincode ランタイム | Node.js | 18 LTS | fabric-contract-api 2.5.x |
| chaincode 言語 | JavaScript | — | 決定性 API のみ使用 |
| 単体テスト | mocha + chai + sinon | — | L1 (chaincode mock) |
| 実行環境 | Linux (WSL2 想定) + Docker 29 + compose v2 | — | `setup.sh` が前提チェック |
| スクリプト | bash (`set -euo pipefail`) | — | 全スクリプト冪等性必須 |

### 組織構成

| MSP ID | 業務語彙 | 役割 |
|---|---|---|
| `Org1MSP` | メーカー A | 製品登録 (`CreateProduct`) 可能 |
| `Org2MSP` | 卸 B | 中間所有者 |
| `Org3MSP` | 販売店 C | 最終所有者。C 視点検証の主体 |

※ 内部 MSP ID は fabric-samples 標準の `Org1MSP`/`Org2MSP`/`Org3MSP` を使用。業務語彙への変換は表示層 (`scripts/lib/format.sh`) で行う。

### チャンネル / チェーンコード

- Channel: `supplychannel`
- Chaincode: `product-trace` (version 1.0 / sequence 1)
- Endorsement policy: `OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')`
- データモデル: [`docs/spec.md`](docs/spec.md) §10

---

## ディレクトリ構成

```
hl-proto/
├── CLAUDE.md                         # 開発規約（Claude Code 向け）
├── README.md                         # 本ファイル
├── docs/
│   ├── spec.md                       # 機能仕様（凍結）
│   ├── demo-scenarios.md             # N1〜N4 / E1〜E3 詳細 + ナレーション
│   ├── architecture.md               # Org / Peer / Channel / Chaincode 図解
│   ├── fabric-pitfalls.md            # Fabric 落とし穴集
│   └── tasks/                        # phase 別タスク
├── chaincode/
│   └── product-trace/                # Node chaincode + L1 単体テスト
├── fabric/
│   ├── fabric-samples/               # setup.sh が取得（git ignore）
│   └── test-network-wrapper/patches/ # 差分管理
├── scripts/
│   ├── setup.sh                      # Fabric binaries / image 取得
│   ├── network_up.sh                 # 3Org + supplychannel 起動
│   ├── reset.sh                      # ネットワーク完全リセット
│   ├── deploy_chaincode.sh           # chaincode デプロイ
│   ├── invoke_as.sh                  # Org 切替 invoke / query
│   ├── demo_normal.sh                # 正常系デモ（人向け）
│   ├── demo_error.sh                 # 異常系デモ（人向け）
│   ├── demo_verify_as_c.sh           # C 視点検証クライマックス
│   ├── test_integration.sh           # L2 結合テスト（自動 assert）
│   └── lib/format.sh                 # 出力整形・MSP→業務語彙変換
└── tests/
    └── integration/                  # L2 結合テストケース
```

---

## 前提ソフトウェア

| ツール | バージョン | 備考 |
|---|---|---|
| OS | Linux (WSL2 含む) | Ubuntu 22.04 で検証 |
| Docker | 29+ | `docker compose v2` 必須 |
| Node.js | 18 LTS | chaincode / L1 テスト |
| jq | 1.6+ | スクリプト全般で JSON 整形に使用 |
| git | 任意 | fabric-samples 取得に使用 |
| bash | 5+ | `set -euo pipefail` 前提 |

Docker 操作は **sudo 不要** にしておくこと:

```bash
sudo usermod -aG docker "$USER"   # → 再ログイン
# または未反映シェルで一時的に:
sg docker -c './scripts/network_up.sh'
```

---

## セットアップ手順

### 1. 初回セットアップ（Fabric binaries / Docker image 取得）

```bash
./scripts/setup.sh
```

- fabric-samples を pin した commit で clone
- `fabric-samples/bin/` に `peer` 等を配置
- 必要な Docker image (`hyperledger/fabric-peer:2.5.15` 等) を pull

冪等。2 回目以降はスキップされる。

### 2. ネットワーク起動（3Org + supplychannel）

```bash
./scripts/network_up.sh
```

- `network.sh up` → `addOrg3.sh up` → channel create
- 最終的に 8 個の Fabric コンテナが稼働（orderer 1 + peer 3 + CA 4）

### 3. chaincode デプロイ

```bash
./scripts/deploy_chaincode.sh
```

- `product-trace` を staging 経由で package（`node_modules` 除外）
- 3 Org 全ピアに install → approveformyorg → commit
- Endorsement policy: `OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')`

### 一括起動（クリーン状態から）

```bash
./scripts/reset.sh --yes && ./scripts/network_up.sh && ./scripts/deploy_chaincode.sh
```

または `demo_normal.sh --fresh` で reset → up → deploy → デモ本編まで連動。

---

## デモ実行手順

### 推奨: ナレーション付き 3 段構え（約 5 分）

```bash
# 1. 正常系: A→B→C の譲渡を語る
./scripts/demo_normal.sh

# 2. C 視点クライマックス: 起点 A を証明する
./scripts/demo_verify_as_c.sh
# ※ 引数省略時は demo_normal.sh が書いた .last_product_id を自動で拾う

# 3. 異常系: 「書けないはずのものは書けない」
./scripts/demo_error.sh
```

`demo_normal.sh` の末尾で `.last_product_id` がリポジトリ直下に書き出され、`demo_verify_as_c.sh` が引数なしで引き継ぐ設計。間に時間が空いても同じ productId を追跡できる。

### 手動版（台本なしで 1 コマンドずつ）

```bash
# N1: A が X001 を登録
./scripts/invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP

# N2: A → B
./scripts/invoke_as.sh org1 invoke TransferProduct X001 Org1MSP Org2MSP

# N3: B → C
./scripts/invoke_as.sh org2 invoke TransferProduct X001 Org2MSP Org3MSP

# N4: C 視点で照会
./scripts/invoke_as.sh org3 query ReadProduct X001
./scripts/invoke_as.sh org3 query GetHistory X001
```

シナリオの詳細な台本・期待出力・30 秒ナレーションは [`docs/demo-scenarios.md`](docs/demo-scenarios.md) を参照。

---

## 正常系の期待結果

### N1: `CreateProduct X001 Org1MSP Org1MSP`（A が実行）

```json
{
  "productId": "X001",
  "manufacturer": "Org1MSP",
  "currentOwner": "Org1MSP",
  "status": "ACTIVE",
  "createdAt": "2026-04-15T...",
  "updatedAt": "2026-04-15T..."
}
```

- `currentOwner` = Org1MSP（メーカー A）
- `manufacturer` = Org1MSP（以後不変）

### N2: `TransferProduct X001 Org1MSP Org2MSP`（A が実行）

- `currentOwner` が `Org2MSP`（卸 B）に更新
- `manufacturer` は変わらず `Org1MSP`

### N3: `TransferProduct X001 Org2MSP Org3MSP`（B が実行）

- `currentOwner` が `Org3MSP`（販売店 C）に更新

### N4: `GetHistory X001`（C が実行）

時系列順に 3 件の履歴イベント:

```
#1 CREATE   by メーカー A (Org1MSP)  at 2026-04-15T...  txId=...
#2 TRANSFER by メーカー A (Org1MSP)  Org1MSP → Org2MSP  txId=...
#3 TRANSFER by 卸 B    (Org2MSP)  Org2MSP → Org3MSP  txId=...
```

`#1 actor.mspId == Org1MSP` により **起点 A が証明される**。これが `demo_verify_as_c.sh` のクライマックス。

---

## 異常系の期待結果

全ケースで chaincode は `[CODE]` プレフィックス付きエラーを返す。失敗 invoke は block に載らず、履歴は汚染されない。

### E1: 所有者偽装

C (Org3) が B (Org2MSP) を騙って自分への移転を invoke:

```bash
./scripts/invoke_as.sh org3 invoke TransferProduct X001 Org2MSP Org3MSP
```

期待:
```
Error: [OWNER_MISMATCH] caller Org3MSP does not match fromOwner Org2MSP
```
- exit code ≠ 0
- 直後の `GetHistory X001` で履歴に新イベントが追加されていないこと

### E2: 未登録製品の照会

```bash
./scripts/invoke_as.sh org3 query ReadProduct GHOST-001
```

期待:
```
Error: [PRODUCT_NOT_FOUND] productId=GHOST-001
```
- 読み取り専用なので副作用なし

### E3: 既存 productId の重複登録

```bash
./scripts/invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP
```

期待:
```
Error: [PRODUCT_ALREADY_EXISTS] productId=X001
```
- 元の X001 の履歴は変わらず

全ケースのエラーコード定義と検証方針は [`docs/demo-scenarios.md`](docs/demo-scenarios.md) 参照。

---

## クリーンアップ手順

```bash
./scripts/reset.sh --yes
```

以下を削除する:

1. `network.sh down`（orderer / peer / CA コンテナ停止）
2. chaincode コンテナ (`dev-peer*`) 削除
3. chaincode image (`dev-peer*-product-trace*`) 削除
4. Fabric 関連 volume (`compose_*`, `docker-*_*`) 削除
5. `.last_product_id` 等の生成物削除

`--yes` なしだと確認プロンプト。冪等なので 2 回実行しても壊れない。

> ⚠️ `docker system prune -af` は **決して実行しないこと**。関係ない image / volume まで消える。`reset.sh` は Fabric 関連のみを選択削除する。

---

## よくあるエラーと対処

### ポート 7050 / 7051 / 9051 / 11051 が衝突

```
Error: port is already allocated
```

- 他の Fabric ネットワークや Node サーバーが同ポートを占有
- 対処: `sudo lsof -i :7050` で特定 → 停止、または `./scripts/reset.sh --yes`
- 関連: [`fabric-pitfalls.md` §ポート衝突](docs/fabric-pitfalls.md)

### WSL2 メモリ不足 (peer が OOM で落ちる)

```
peer0.org1.example.com exited with code 137
```

- WSL2 の既定メモリ制限（2〜4GB）が不足
- 対処: `%USERPROFILE%\.wslconfig` に以下を追記して `wsl --shutdown`:

  ```ini
  [wsl2]
  memory=8GB
  processors=4
  ```
- 最低 8GB 推奨。4GB では chaincode build で頻繁に落ちる。

### `dev-peer*` chaincode コンテナ残留

前回デプロイの chaincode コンテナが残っていると、新しい package を install しても古いコードで動くことがある:

```
Chaincode invocation returned stale response
```

- 対処: `./scripts/reset.sh --yes` で `dev-peer*` と関連 image を一掃してから再デプロイ
- 関連: [`fabric-pitfalls.md` §chaincode コンテナ残留](docs/fabric-pitfalls.md)

### `Cannot connect to the Docker daemon` (WSL2)

```
permission denied while trying to connect to the Docker daemon socket
```

- docker グループ未反映のシェルから実行している
- 対処 1: `newgrp docker` でグループ反映
- 対処 2: 一時回避として `sg docker -c './scripts/network_up.sh'` で包む
- 対処 3: 再ログインして `id` で `docker` グループが見えることを確認

### 既存 Fabric ネットワーク稼働中に `network_up.sh` を叩いた

```
Error: network supplychannel already exists
```

- 前回の起動が残存
- 対処: `./scripts/reset.sh --yes` を先に実行

### `test_integration.sh` が失敗した時の一次切り分け

L2 結合テストが落ちた場合、整形層で隠れた生エラーを直接確認:

```bash
./scripts/invoke_as.sh org3 query GetHistory <失敗した productId>
```

chaincode の `[CODE]` エラーメッセージが出る。それで判別できないときは:

```bash
docker logs peer0.org1.example.com | tail -100
docker logs dev-peer0.org1.example.com-product-trace_1.0-* | tail -100
```

### その他の落とし穴

実装中に踏んだ罠の完全リストは [`docs/fabric-pitfalls.md`](docs/fabric-pitfalls.md) に集約:

- Fabric 2.5.10 以前 × Docker 29+ → chaincode install が `broken pipe`
- Node chaincode package に `node_modules` を含めると `broken pipe`
- lifecycle skip 判定は seq/ver だけでなく `package_id` まで見る
- `bin/peer` 直呼びには `FABRIC_CFG_PATH=<samples>/config` 必須
- sudo でスクリプト実行すると root 所有ファイルが残って次に詰む
- chaincode エラーは `[CODE]` プレフィックス付き（message 本文しか伝搬しない）
- MVCC_READ_CONFLICT 時のリトライ

---

## テスト

### L1 単体テスト（chaincode mock）

```bash
cd chaincode/product-trace
npm install
npm test
```

chaincode ロジックを fabric-shim mock で単体検証する。決定性 API のみの使用をここで担保。

### L2 結合テスト（実ネットワーク）

```bash
./scripts/test_integration.sh
```

- 実 3Org ネットワークに対して正常系・異常系をまとめて自動 assert
- `demo_*.sh` と責務分離: テスト側は整形なし・ナレーションなし・assert あり
- `--fresh` で reset → up → deploy → テストを一括

詳細なテスト戦略は [`docs/tasks/test-strategy.md`](docs/tasks/test-strategy.md) 参照。

---

## 関連ドキュメント

| ドキュメント | 内容 |
|---|---|
| [`docs/spec.md`](docs/spec.md) | 機能仕様（凍結） |
| [`docs/demo-scenarios.md`](docs/demo-scenarios.md) | N1〜N4 / E1〜E3 詳細 + ナレーション台本 + スコープ外宣言 |
| [`docs/architecture.md`](docs/architecture.md) | 組織 / Peer / Channel / Chaincode 図解 |
| [`docs/fabric-pitfalls.md`](docs/fabric-pitfalls.md) | Fabric 落とし穴集（実装中の知見） |
| [`docs/tasks/`](docs/tasks/) | Phase 別タスク分解 |
| [`CLAUDE.md`](CLAUDE.md) | Claude Code 向け開発規約 |

---

## Phase ロードマップ

| Phase | 内容 | 状態 |
|---|---|---|
| 1 環境 | Fabric binaries / image pin、setup.sh | ✅ |
| 2 ネットワーク | 3Org + supplychannel 起動、reset | ✅ |
| 3 Chaincode | product-trace 実装 + L1 単体テスト | ✅ |
| 4 デプロイ | deploy_chaincode.sh / invoke_as.sh | ✅ |
| 5 デモ | demo_*.sh / test_integration.sh / 業務語彙変換 | ✅ |
| 6 ドキュメント | README 完全版 / demo-scenarios.md / architecture.md | 🚧 本 commit |
| 7 受入 | クリーン VM での README 完走 | — |

---

## ライセンス

未定（PoC のため）。
