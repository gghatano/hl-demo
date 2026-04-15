# アーキテクチャ

hl-proto ネットワークの論理・物理構成図。ASCII 図で完結させ、デモ担当者が画面に映して説明できる粒度。

---

## 目次

- [全体構成](#全体構成)
- [組織・ノード配置](#組織ノード配置)
- [チャネルとチェーンコード](#チャネルとチェーンコード)
- [invoke / query の経路](#invoke--query-の経路)
- [決定性 chaincode の実行モデル](#決定性-chaincode-の実行モデル)
- [GetHistory 取得の流れ](#gethistory-取得の流れ)
- [MSP と業務語彙の対応](#msp-と業務語彙の対応)
- [デプロイ単位 / ライフサイクル](#デプロイ単位--ライフサイクル)
- [データモデル](#データモデル)

---

## 全体構成

```
                      ┌──────────────────────────┐
                      │  Orderer Service (Raft)  │
                      │   orderer.example.com    │
                      │      port 7050           │
                      └──────────┬───────────────┘
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
        ┌───────▼──────┐ ┌───────▼──────┐ ┌───────▼──────┐
        │   Org1MSP    │ │   Org2MSP    │ │   Org3MSP    │
        │  メーカー A  │ │   卸 B       │ │  販売店 C    │
        ├──────────────┤ ├──────────────┤ ├──────────────┤
        │ peer0.org1   │ │ peer0.org2   │ │ peer0.org3   │
        │  :7051       │ │  :9051       │ │  :11051      │
        ├──────────────┤ ├──────────────┤ ├──────────────┤
        │ ca.org1      │ │ ca.org2      │ │ ca.org3      │
        │  :7054       │ │  :8054       │ │  :11054      │
        └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
               │                │                │
               └────────────────┴────────────────┘
                       channel: supplychannel
                  chaincode: product-trace v1.0
          endorsement: OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')
```

**稼働コンテナ数（起動直後）**: 8 個
- orderer × 1
- peer × 3（各 Org 1 ピア）
- fabric-ca × 4（orderer 用 1 + 各 Org 用 1 ×3）

chaincode コンテナ (`dev-peer0.*-product-trace-*`) はデプロイ後に各 peer が自動起動するため別枠。

---

## 組織・ノード配置

| 組織 | MSP ID | 業務語彙 | peer ホスト | gRPC ポート | CA ホスト |
|---|---|---|---|---|---|
| Org1 | `Org1MSP` | メーカー A | `peer0.org1.example.com` | 7051 | `ca.org1.example.com:7054` |
| Org2 | `Org2MSP` | 卸 B | `peer0.org2.example.com` | 9051 | `ca.org2.example.com:8054` |
| Org3 | `Org3MSP` | 販売店 C | `peer0.org3.example.com` | 11051 | `ca.org3.example.com:11054` |

**ベース構成**: `fabric-samples/test-network` + `addOrg3.sh`
- `network.sh up createChannel -ca` で Org1/Org2 + Orderer を立ち上げ
- `addOrg3.sh up -c supplychannel -ca` で Org3 を後から合流
- 差分パッチは `fabric/test-network-wrapper/patches/` に集約（test-network 本体は直接編集しない）

---

## チャネルとチェーンコード

```
  channel: supplychannel
  ┌────────────────────────────────────────────────────────────┐
  │                                                            │
  │   genesis block                                            │
  │        ↓                                                   │
  │   [channel config block]                                   │
  │        ↓                                                   │
  │   [chaincode lifecycle: approve × 3 orgs]                  │
  │        ↓                                                   │
  │   [chaincode commit]                                       │
  │        ↓                                                   │
  │   [invoke: CreateProduct X001]     ← Org1 endorse          │
  │        ↓                                                   │
  │   [invoke: TransferProduct X001 A→B] ← Org1 endorse        │
  │        ↓                                                   │
  │   [invoke: TransferProduct X001 B→C] ← Org2 endorse        │
  │        ↓                                                   │
  │   ...                                                      │
  └────────────────────────────────────────────────────────────┘

  chaincode: product-trace
    version  : 1.0
    sequence : 1
    language : node (fabric-contract-api 2.5.x)
    policy   : OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')
```

**Endorsement policy が `OR` である意図**:
- PoC 用途。1 組織で承認可能なので invoke 実行が単純
- 実運用では `AND(Org1MSP.peer, Org2MSP.peer)` など必要に応じて厳格化
- デモでは「任意の 1 ピアで endorsement できるが、chaincode ロジックで所有者照合するので実質的な権限はコードで制御」という説明

---

## invoke / query の経路

### 正常 invoke（N2: A → B 移転）の流れ

```
  ┌─────────┐
  │ Admin@  │ (1) proposal
  │ Org1MSP │ ──────────────────────────┐
  └─────────┘                           │
                                        ▼
                              ┌──────────────────┐
                        ┌─────┤ peer0.org1       │ (2) simulate
                        │     │ (endorser)       │     exec chaincode
                        │     │                  │     → read/write set
                        │     │                  │     → sign
                        │     └──────────────────┘
                        │              │
                        │              ▼
                        │     ┌──────────────────┐
                        │     │ signed response  │
                        │     └──────────────────┘
                        │              │
                        │              ▼
  ┌─────────┐ (3) endorsed tx   ┌──────────────┐
  │ Admin@  │ ◄─────────────────┤              │
  │ Org1MSP │                    │              │
  └────┬────┘                    │              │
       │                         │              │
       │ (4) broadcast           │              │
       ▼                         │              │
  ┌─────────────────┐            │              │
  │ Orderer (Raft)  │            │              │
  │ - order tx      │            │              │
  │ - cut block     │            │              │
  └────────┬────────┘            │              │
           │                     │              │
           │ (5) deliver block   │              │
           ▼                     ▼              ▼
  ┌──────────────┐      ┌──────────────┐  ┌──────────────┐
  │ peer0.org1   │      │ peer0.org2   │  │ peer0.org3   │
  │ - validate   │      │ - validate   │  │ - validate   │
  │ - commit     │      │ - commit     │  │ - commit     │
  │   state      │      │   state      │  │   state      │
  └──────────────┘      └──────────────┘  └──────────────┘
```

**重要ポイント**:
- (2) の simulate でのみ chaincode が実行される。以降はその read/write set が流れるだけ
- (5) で 3 Org すべての peer が同じ state に収束
- C (Org3) は自組織 peer に問い合わせるだけで最新 state が参照できる

### query（N4: C が GetHistory）

query は broadcast せず、指定 peer に simulate させて結果を受け取るだけ:

```
  ┌─────────┐       ┌──────────────┐
  │ Admin@  │──────►│ peer0.org3   │ simulate chaincode
  │ Org3MSP │       │ - read state │
  └─────────┘◄──────┤ - return     │
                    └──────────────┘
```

block には一切残らない（state DB への read のみ）。

---

## 決定性 chaincode の実行モデル

`OR` endorsement でも複数 peer が simulate するケースでは、全 endorser が **同一の write set を生成する必要** がある。非決定性 API が混入すると他の peer の計算と食い違い、endorsement 段階で失敗する。

**禁止されている API**:
- `Date.now()` / `new Date()`（実行時刻が peer ごとに異なる）
- `Math.random()`（seed なし）
- 環境変数 / `process.env`
- 外部 HTTP / DB / file I/O

**使うべき決定性 API**:
- `ctx.stub.getTxTimestamp()` → `google.protobuf.Timestamp` → ISO8601 文字列変換
- `ctx.clientIdentity.getMSPID()` / `getID()`
- `ctx.stub.getTxID()`
- state 操作: `getState` / `putState` / `deleteState` / `getHistoryForKey`

詳細: [`fabric-pitfalls.md`](fabric-pitfalls.md) §決定性。

---

## GetHistory 取得の流れ

`GetHistoryForKey(productId)` は **state DB のスナップショット列** を逆時系列で返す Fabric 標準 API。hl-proto ではこれを時系列順に反転し、各 state から `eventType` / `actor` / `txId` / `timestamp` を抽出して履歴配列を組み立てる。

```
  ┌────────────────────────────────────────────────────┐
  │ state DB (CouchDB/LevelDB) key=X001                │
  │  ┌────────────────────────────────────────────┐    │
  │  │ v1 (txId=a1b2, timestamp=09:00):           │    │
  │  │   currentOwner=Org1MSP, lastEvent=CREATE   │    │
  │  ├────────────────────────────────────────────┤    │
  │  │ v2 (txId=d4e5, timestamp=09:05):           │    │
  │  │   currentOwner=Org2MSP, lastEvent=TRANSFER │    │
  │  ├────────────────────────────────────────────┤    │
  │  │ v3 (txId=7890, timestamp=09:10):           │    │
  │  │   currentOwner=Org3MSP, lastEvent=TRANSFER │    │
  │  └────────────────────────────────────────────┘    │
  └────────────────────────────────────────────────────┘
                       │
                       ▼  getHistoryForKey("X001")
         ┌──────────────────────────────┐
         │ iterator (reverse chrono)    │
         │  v3 → v2 → v1                │
         └──────────────────────────────┘
                       │
                       ▼  chaincode で reverse
         ┌──────────────────────────────┐
         │ [                            │
         │   { #1: CREATE by Org1MSP }, │
         │   { #2: TRANSFER A→B },      │
         │   { #3: TRANSFER B→C }       │
         │ ]                            │
         └──────────────────────────────┘
```

**重要な設計判断**:
- state 本体に `history` 配列を持たせない。GetHistoryForKey 一本化で二重管理を回避
- CREATE 判定は state のメタデータで行う（詳細: [`fabric-pitfalls.md`](fabric-pitfalls.md) §GetHistory の CREATE 判定）
- `actor` は state の `lastActor` フィールドに書き込んでおき、各 state version から抽出

---

## MSP と業務語彙の対応

```
  chaincode 層       ← MSP ID のみ使用（Org1MSP 等）
  ────────────────────────────────────────────────────
  scripts/lib/format.sh  ← 表示時に業務語彙へ変換
                        msp_to_role("Org1MSP") → "メーカー A"
                        msp_to_role("Org2MSP") → "卸 B"
                        msp_to_role("Org3MSP") → "販売店 C"
  ────────────────────────────────────────────────────
  demo_*.sh 出力     ← 人間向け語彙で表示
                     "#1 CREATE by メーカー A (Org1MSP)"
```

**設計意図**:
- chaincode 側に業務語彙を埋め込まない（台帳の中身は MSP ID のみで純粋）
- 表示層で変換することで、別の業務語彙セットに差し替え可能
- `test_integration.sh` は整形層を通さず MSP ID で直接 assert する

---

## デプロイ単位 / ライフサイクル

Fabric 2.x の chaincode lifecycle は 4 段階:

```
  1. package   →  peer lifecycle chaincode package product-trace.tar.gz
                  staging ディレクトリから node_modules を除外してパック
                  (詳細: fabric-pitfalls.md §chaincode package)

  2. install   →  peer lifecycle chaincode install product-trace.tar.gz
                  各 Org の各 peer に対して実行（本 PoC では 3 回）

  3. approve   →  peer lifecycle chaincode approveformyorg \
                    --channelID supplychannel \
                    --name product-trace --version 1.0 --sequence 1 \
                    --package-id $PKG_ID \
                    --signature-policy "OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')"
                  各 Org で 1 回（3 回）

  4. commit    →  peer lifecycle chaincode commit \
                    --channelID supplychannel \
                    --name product-trace --version 1.0 --sequence 1 \
                    --signature-policy "OR(...)"
                  誰か 1 Org が実行すれば全体に反映
```

**冪等化の工夫** (`deploy_chaincode.sh`):
- `queryinstalled` の出力を `jq` で厳密一致判定（package_id まで見る）
- `queryapproved` / `querycommitted` で approve/commit 済みかを seq/ver/package_id で確認
- 全段階 skip 可能。2 回実行で壊れない

詳細: [`fabric-pitfalls.md`](fabric-pitfalls.md) §lifecycle chaincode の skip 判定。

---

## データモデル

### Product（state 本体）

```json
{
  "productId": "X001",
  "manufacturer": "Org1MSP",
  "currentOwner": "Org3MSP",
  "status": "ACTIVE",
  "createdAt": "2026-04-15T09:00:00.000Z",
  "updatedAt": "2026-04-15T09:10:00.000Z",
  "lastEvent": "TRANSFER",
  "lastActor": "Org2MSP"
}
```

- `manufacturer` は登録時に固定され以降不変
- `lastEvent` / `lastActor` は GetHistory 時に各 state version から履歴イベントを再構築するための手がかり
- `history` 配列は **state に保持しない**（GetHistoryForKey 一本化）

### ProductHistoryEvent（chaincode が GetHistory 時に生成）

```json
{
  "eventType": "TRANSFER",
  "productId": "X001",
  "fromOwner": "Org2MSP",
  "toOwner": "Org3MSP",
  "actor": {
    "mspId": "Org2MSP",
    "subjectDN": "CN=Admin@org2.example.com,..."
  },
  "txId": "7890abcd...",
  "timestamp": "2026-04-15T09:10:00.000Z"
}
```

- `actor.mspId` が C 視点検証のキー（`== Org1MSP` なら起点 A）
- `timestamp` は `ctx.stub.getTxTimestamp()` 由来（決定性）
- `txId` で block を特定可能

完全な仕様は [`spec.md`](spec.md) §10 参照。

---

## 関連ドキュメント

- [`README.md`](../README.md) — セットアップ / コマンドリファレンス
- [`spec.md`](spec.md) — 機能仕様（凍結）
- [`demo-scenarios.md`](demo-scenarios.md) — N1〜N4 / E1〜E3 シナリオ詳細
- [`fabric-pitfalls.md`](fabric-pitfalls.md) — Fabric 実装時の落とし穴集
