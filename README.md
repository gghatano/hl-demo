# hl-proto — Hyperledger Fabric サプライチェーン・トレーサビリティ PoC

Hyperledger Fabric 上で、製品 `X` が **A（メーカー）→ B（卸）→ C（販売店）** と流通する来歴を台帳に記録し、最後に **C の視点で「この製品が本当に A 起点で流通してきたか」を検証できる** ことを示すローカルデモ環境。

> **Status**: Phase 4 完了（2026-04 時点）。3Org ネットワーク起動 / chaincode デプロイ / 任意の Org からの invoke・query まで動作確認済。デモ用ナレーションスクリプトと説明資料は Phase 5 で整備予定。

---

## 何を見せるデモか

### ゴール

3 社（A / B / C）で共有する改ざん困難な台帳の上に、製品単位の譲渡履歴を記録し、C の立場で来歴を辿れることを実演する。

### 正常系（spec §9.1）

1. **製品登録**: A が `X001` を新規登録する（A のみ実行可能）
2. **A→B 移転**: A が `X001` を B へ譲渡する（所有権が B に）
3. **B→C 移転**: B が `X001` を C へ譲渡する（所有権が C に）
4. **C による来歴確認**: C が `X001` の履歴を照会し、`CREATE → TRANSFER(A→B) → TRANSFER(B→C)` が連続していることを確認する

各イベントには **ブロック上で確定した時点のタイムスタンプ・txId・実行主体の MSP ID と証明書情報** が記録され、後から書き換えられない。

### 異常系（spec §9.2）

| シナリオ | 期待結果 |
|---|---|
| 既に B 所有の製品を A が第三者に再譲渡しようとする | endorsement 段階で `[OWNER_MISMATCH]` により拒否 |
| 存在しない productId を照会する | `[PRODUCT_NOT_FOUND]` |
| 既存の productId を重複登録しようとする | `[PRODUCT_ALREADY_EXISTS]` |

「台帳の整合性は chaincode ロジックで保証され、不正な更新は block に載らない」ことを見せるのが狙い。

### 検証できる技術要素

- **3Org 間の state 同期**: A の invoke が C の peer から即座に query できる
- **endorsement policy**: `OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')` の明示
- **決定性 chaincode**: `Date.now()` 等を使わず `ctx.stub.getTxTimestamp()` で時刻生成 → 全 endorser で同一結果
- **MSP による主体証明**: Org2 のふりをした invoke は証明書段で拒否される
- **GetHistoryForKey** による過去状態のスナップショット列挙

### 非対象（このデモでは扱わないこと）

- 本番可用性・性能
- 物理製品と productId の対応保証（QR / RFID / IoT 連携）
- Web UI / 可視化（CLI のみ）
- 外部 ERP / 在庫管理システム連携
- Fabric CA 発行の end-user cert による認可（現状は Admin MSP 固定）

詳細は `docs/spec.md` を参照。

---

## 技術スタック

| レイヤ | 採用 | バージョン pin | 備考 |
|---|---|---|---|
| 台帳基盤 | Hyperledger Fabric | **2.5.15** | Docker 29+ 対応のため 2.5.15 以上必須 (`docs/fabric-pitfalls.md` §Docker 29) |
| 認証局 | Fabric CA | **1.5.18** | test-network 標準構成 |
| ネットワーク雛形 | hyperledger/fabric-samples test-network + addOrg3 | commit pin | 3Org 化のため fabric-samples 標準フロー (`network.sh up` → `addOrg3.sh up`) を利用 |
| コンセンサス | Raft orderer (単一ノード) | — | PoC 用途、HA は非対象 |
| chaincode ランタイム | Node.js | 18 LTS | fabric-contract-api 2.5.x / fabric-shim 2.5.x |
| chaincode 言語 | JavaScript (Node) | — | 決定性 API のみ使用。制約は `docs/fabric-pitfalls.md` §決定性 参照 |
| 単体テスト | mocha + chai + sinon | — | L1 (chaincode mock) |
| 実行環境 | Linux (WSL2 想定) + Docker 29 + docker compose v2 | — | setup.sh が前提チェック |
| スクリプト | bash (`set -euo pipefail`) | — | 全スクリプト冪等性必須 |

### 組織構成

| MSP ID | 業務語彙 | 役割 |
|---|---|---|
| `Org1MSP` | メーカー A | 製品登録 (`CreateProduct`) 可能 |
| `Org2MSP` | 卸 B | 中間所有者 |
| `Org3MSP` | 販売店 C | 最終所有者。C 視点検証の主体 |

※ 内部では fabric-samples 標準の `Org1MSP` / `Org2MSP` / `Org3MSP` をそのまま使用し、業務語彙への変換は出力整形層（Phase 5 以降）で行う。

### チャンネル / チェーンコード

- Channel: `supplychannel`
- Chaincode: `product-trace` (version 1.0 / sequence 1)
- Endorsement policy: `OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')`
- データモデル (`Product` / `ProductHistoryEvent`): `docs/spec.md` §10

---

## ディレクトリ構成

```
hl-proto/
├── CLAUDE.md                         # 開発規約（Claude Code 向け）
├── README.md                         # 本ファイル
├── docs/
│   ├── spec.md                       # 機能仕様（凍結）
│   ├── fabric-pitfalls.md            # Fabric 落とし穴集（実装中の知見）
│   ├── tasks/                        # phase 別タスク
│   └── demo-scenarios.md             # Phase 6 で作成予定
├── chaincode/
│   └── product-trace/                # Node chaincode + L1 単体テスト
├── fabric/
│   ├── fabric-samples/               # setup.sh が取得（git ignore）
│   └── test-network-wrapper/patches/ # 差分管理（今後）
└── scripts/
    ├── setup.sh                      # Phase 1: 環境準備（Fabric binaries / image）
    ├── network_up.sh                 # Phase 2: 3Org + supplychannel 起動
    ├── reset.sh                      # Phase 2: ネットワーク完全リセット
    ├── deploy_chaincode.sh           # Phase 4: chaincode デプロイ
    └── invoke_as.sh                  # Phase 4: Org 切替 invoke / query
```

---

## クイックスタート（Phase 4 時点で叩ける操作）

### 前提

- Linux (WSL2 含む) + Docker 29+ + docker compose v2 + Node.js 18 + jq + git
- docker 操作は sudo 不要にしておく（`sudo usermod -aG docker $USER` → 再ログイン、もしくは一時的に `sg docker -c '...'` で包む）

### 1. 初回セットアップ

```bash
./scripts/setup.sh          # Fabric binaries / Docker image 取得
./scripts/network_up.sh     # 3Org + supplychannel 起動
./scripts/deploy_chaincode.sh   # product-trace v1.0 デプロイ
```

### 2. 正常系デモ（手動版）

```bash
# N1: A が X001 を登録
./scripts/invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP

# N2: A → B 移転
./scripts/invoke_as.sh org1 invoke TransferProduct X001 Org1MSP Org2MSP

# N3: B → C 移転
./scripts/invoke_as.sh org2 invoke TransferProduct X001 Org2MSP Org3MSP

# N4: C 視点で来歴照会
./scripts/invoke_as.sh org3 query  ReadProduct X001
./scripts/invoke_as.sh org3 query  GetHistory X001
```

### 3. 異常系確認

```bash
# E3: 既存 X001 を重複登録 → 拒否期待
./scripts/invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP

# E1: 既に C 所有の X001 を A が第三者に再譲渡 → 拒否期待
./scripts/invoke_as.sh org1 invoke TransferProduct X001 Org1MSP Org2MSP

# E2: 未登録製品の照会 → 拒否期待
./scripts/invoke_as.sh org3 query ReadProduct NOT_EXIST
```

### 4. 片付け

```bash
./scripts/reset.sh --yes    # ネットワーク停止 + 生成物削除
```

---

## Phase ロードマップ

| Phase | 内容 | 状態 |
|---|---|---|
| 1 環境 | Fabric binaries / image pin、setup.sh | ✅ |
| 2 ネットワーク | 3Org + supplychannel 起動、reset | ✅ |
| 3 Chaincode | product-trace 実装 + L1 単体テスト | ✅ |
| 4 デプロイ | deploy_chaincode.sh / invoke_as.sh | ✅ 本 commit |
| 5 デモ | demo_*.sh / test_integration.sh / 業務語彙変換 | 次 |
| 6 ドキュメント | README 完全版 / demo-scenarios.md / architecture.md | — |
| 7 受入 | クリーン VM での README 完走 | — |

Phase 5 のデモシナリオ詳細計画は [Issue #2](https://github.com/gghatano/hl-demo/issues/2) を参照。

---

## 開発者向け情報

### L1 単体テスト (chaincode)

```bash
cd chaincode/product-trace
npm install
npm test
```

### 落とし穴集

実装中に踏んだ罠とその対策は `docs/fabric-pitfalls.md` に集約している。特に以下は再現時の判断材料として重要:

- **Fabric 2.5.10 以前 × Docker 29+** で chaincode install が `broken pipe` で落ちる
- **Node chaincode package に node_modules を含めると** 別の `broken pipe` で落ちる（staging で除外）
- **lifecycle の skip 判定**は seq/ver だけでなく package_id まで見ないと壊れる
- **`bin/peer` 直呼びには `FABRIC_CFG_PATH=<samples>/config` が必須**
- **sudo でスクリプト実行すると root 所有ファイルが残り** 次の非 sudo 操作で詰む

### 開発規約

Claude Code で開発する場合のルールは `CLAUDE.md` 参照（決定性制約 / endorsement policy 明示 / MSP ID の扱い / コミット規約等）。

---

## ライセンス

未定（PoC のため）。
