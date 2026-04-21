# hl-proto Spec v2 — 鋼材トレーサビリティ拡張 (5Org + 分割/接合 + 系譜可視化)

> このドキュメントは Phase 8 (Issue #9) で確定した仕様です。
> v1 (`docs/spec.md`) は Phase 1〜7 の凍結仕様として残し、本 v2 がアクティブな仕様となります。
> v1 との関係: 3Org を 5Org に拡張、1:1 譲渡に加えて分割 (1→N) / 接合 (N→1) を追加、系譜 DAG 取得 API を新設。

---

## 1. 背景

鋼材サプライチェーンでは以下の加工が日常的に発生する。

- **分割 (Split)**: 鋼板 1 本 → 切断 → 複数の小片
- **接合 (Merge)**: 複数の部材 → 溶接 → 1 個の結合部材

建設会社 (最終納品先) が完成部材を受領したとき、**どのメーカーのどのロットから作られたか** を DAG で遡れることが、品質責任・リコール対応・調達透明性の観点で価値となる。

v1 で構築した 3Org / 1:1 譲渡モデルを、この実務要件に耐える 5Org / DAG モデルへ拡張する。

---

## 2. 目的

1. 5 組織 (高炉メーカー / 電炉メーカー / 加工業者 2 社 / 建設会社) のサプライチェーンを Fabric で表現する
2. 分割・接合操作を chaincode レベルで決定性を保ったまま提供する
3. 任意の productId から祖先方向の DAG を取得でき、Web UI で可視化できる
4. ミルシート (品質証明書) の URI + 改ざん検知ハッシュを台帳に記録できる (本体はオフチェーン)
5. v1 で達成した正常系/異常系テストを 5Org 版に置換し、L1 + L2 全緑で検収可能にする

---

## 3. スコープ

### 3.1 対象
- 5Org 化 (3Org は残さない)
- Chaincode operation 拡張 (Split / Merge / GetLineage / metadata / 複数メーカー)
- Web UI 拡張 (5Org 切替 / 分割フォーム / 接合フォーム / DAG 可視化)
- 既存スクリプトの 5Org 対応
- デモシナリオ複合版 (1 コマンドで「2系統製造 → 分割 → 接合 → 納品」)
- L1 (chaincode 単体) / L2 (結合) テストの 5Org 拡張

### 3.2 非対象 (明示的な除外)
- 子孫方向のトレース (リコール用途) — 祖先方向のみ提供
- 重量保存則の chaincode 内検証 — 分割前後の重量合計は検証しない
- ミルシート本体のオンチェーン格納 — URI + SHA-256 ハッシュのみ保持
- Private Data Collection による組織限定閲覧
- 6 Org 以上への拡張
- v1 ↔ v2 間のデータ移行 — v2 は新規ネットワークで起動

---

## 4. 組織構成 (5Org)

| # | Org | MSP ID | 業務上の役割 | 新規操作の権限 |
|---|---|---|---|---|
| 1 | Org1 | `Org1MSP` | 高炉メーカー A | `CreateProduct` |
| 2 | Org2 | `Org2MSP` | 電炉メーカー X | `CreateProduct` (v2 新規) |
| 3 | Org3 | `Org3MSP` | 加工業者 B (切断・接合) | `SplitProduct` / `MergeProducts` |
| 4 | Org4 | `Org4MSP` | 加工業者 Y (切断・接合) | `SplitProduct` / `MergeProducts` |
| 5 | Org5 | `Org5MSP` | 建設会社 D (最終納品先) | — |

- `TransferProduct` は全 Org が発行可能 (`currentOwner === caller.mspId` で検証)
- `Split` / `Merge` 権限は技術的には「現 owner であること」のみ (caller が MSP B/Y/D/A/X のいずれでも可能だが、業務ロール上は加工業者 = Org3/Org4 が主)

### 4.1 ポート割当
| Org | peer port | CA port |
|---|---|---|
| Org1 | 7051 | 7054 |
| Org2 | 9051 | 8054 |
| Org3 | 11051 | 11054 |
| Org4 | **13051** | **13054** |
| Org5 | **15051** | **15054** |

orderer: 7050 (v1 と同じ)。

---

## 5. データモデル

### 5.1 Product (state, key = productId)

```js
{
  productId:     string,                // 一意 ID
  manufacturer:  "Org1MSP" | "Org2MSP",  // 起点メーカー MSP
  currentOwner:  string,                // 現保有 MSP (5 Org いずれか)
  status:        "ACTIVE" | "CONSUMED", // CONSUMED: 分割 or 接合で親になった
  parents:       string[],              // 親 productId 配列 (後述)
  children:      string[],              // 子 productId 配列 (後述)
  metadata:      object,                // 自由 JSON (grade, weightKg, heatNo, ...)
  millSheetHash: string,                // ミルシート SHA-256 (hex 64 文字, 空文字許容)
  millSheetURI:  string,                // 外部参照 URI (最大 1024 文字, 空文字許容)
  createdAt:     string,                // ISO8601 (Tx タイムスタンプ由来)
  updatedAt:     string,
  lastActor: { mspId: string, id: string }
}
```

### 5.2 parents / children フィールドの意味

| parents 長 | 生成経緯 | 例 |
|---|---|---|
| `0` | 新規製造 (`CreateProduct`) | メーカーが台帳に乗せた原材料 |
| `1` | 分割由来 (`SplitProduct`) の子 | 鋼板 S1 を切った片 S1-a |
| `2+` | 接合由来 (`MergeProducts`) の子 | S1-a + S2 を溶接した P1 |

- `children` は分割 / 接合で書き込まれる。分割なら N 個、接合なら 1 個
- 親に書き込まれた時点で親は `status = CONSUMED` となり、以降 Transfer / Split / Merge 対象にならない
- **決定性確保**: `parents` / `children` は格納時に `[...].sort()` で並び替える。入力順による非決定性を排除

### 5.3 metadata 自由 JSON

- chaincode は `JSON.parse` 後に `typeof === 'object'` であることのみ検証 (配列・null 不可)
- 中身 (`grade` / `weightKg` / `lengthMm` / `heatNo` / 任意キー) は業務層の取り決め
- 将来のスキーマ追加時も chaincode 改修不要

### 5.4 millSheet

- `millSheetHash`: 空文字 or `/^[0-9a-f]{64}$/`
- `millSheetURI`: 空文字 or 長さ 1024 以下の文字列
- ブラウザ側で `crypto.subtle.digest('SHA-256', file)` でハッシュ計算 → URI とセットで chaincode へ送る想定
- 本体 PDF はオフチェーン (`web/uploads/` や S3/IPFS 等) に配置

---

## 6. Operation (chaincode API)

### 6.1 CreateProduct
**シグネチャ**: `CreateProduct(productId, manufacturer, initialOwner, metadataJson, millSheetHash, millSheetURI) -> Product(JSON)`

**権限**:
- `caller.mspId ∈ {Org1MSP, Org2MSP}`
- `manufacturer === caller.mspId`
- `initialOwner === manufacturer`

**検証エラー**:
- `MSP_NOT_AUTHORIZED`: 権限違反
- `INITIAL_OWNER_MISMATCH`: initialOwner ≠ manufacturer
- `PRODUCT_ALREADY_EXISTS`: productId 重複
- `INVALID_METADATA`: metadata が JSON object でない
- `INVALID_ARGUMENT`: 引数欠落 / millSheetHash 形式違反 / millSheetURI 長さ超過

**副作用**: state に新規 Product を `status=ACTIVE`, `parents=[]`, `children=[]` で書き込む。

---

### 6.2 TransferProduct
**シグネチャ**: `TransferProduct(productId, fromOwner, toOwner) -> Product(JSON)` (v1 互換)

**権限**:
- product が `status === 'ACTIVE'`
- `caller.mspId === fromOwner === product.currentOwner`
- `toOwner ∈ 5Org MSP`
- `fromOwner !== toOwner`

**検証エラー**:
- `PRODUCT_NOT_FOUND`
- `OWNER_MISMATCH`
- `MSP_NOT_AUTHORIZED`
- `PARENT_NOT_ACTIVE`: product が CONSUMED
- `INVALID_ARGUMENT`

**副作用**: `currentOwner = toOwner`、`updatedAt` 更新、`lastActor` 更新。

---

### 6.3 SplitProduct (v2 新規)

**シグネチャ**: `SplitProduct(parentId, childrenJson) -> { parent: Product, children: Product[] }`

`childrenJson` は以下の JSON 配列を string 化したもの:
```json
[
  {
    "childId":       "S1-a",
    "toOwner":       "Org3MSP",
    "metadataJson":  "{\"weightKg\":3000,\"grade\":\"SS400\"}",
    "millSheetHash": "<64 hex or empty>",
    "millSheetURI":  "<uri or empty>"
  },
  ...
]
```

**権限**:
- parent が `status === 'ACTIVE'`
- `caller.mspId === parent.currentOwner`

**検証エラー**:
- `PRODUCT_NOT_FOUND`: parent 不在
- `PARENT_NOT_ACTIVE`: parent が CONSUMED
- `MSP_NOT_AUTHORIZED`: caller ≠ parent.currentOwner
- `INVALID_ARGUMENT`: children 2 件未満 / toOwner が 5 Org 外 / 各 spec が object でない
- `CHILD_ALREADY_EXISTS`: childId が state に既存 or children 内重複 or childId==parentId

**副作用**:
- parent を `status=CONSUMED`, `children=[...childIds].sort()` に更新
- 各 child を新規 `putState`:
  - `manufacturer = parent.manufacturer` (継承)
  - `currentOwner = toOwner`
  - `parents = [parentId]`
  - `children = []`
  - `status = 'ACTIVE'`
  - metadata / millSheetHash / millSheetURI は子個別指定

---

### 6.4 MergeProducts (v2 新規)

**シグネチャ**: `MergeProducts(parentIdsJson, childJson) -> { parents: Product[], child: Product }`

`parentIdsJson`: `["S1-a","S2"]` の形式。**最小 2 件** (1 件接合は無意味)。

※ Split も同様に **子 2 件以上** を要求。1→1 の変換は `TransferProduct` で表現する (状態継続) か、別途 Split→Merge で表現する。
この制約により、GetHistory の `SPLIT` / `MERGE` イベント区別を親の `children.length` のみで確定できる。
`childJson`:
```json
{
  "childId":       "P1",
  "metadataJson":  "{...}",
  "millSheetHash": "",
  "millSheetURI":  ""
}
```
(toOwner は caller に自動設定 = 接合者が保有)

**権限**:
- **全 parent の** `status === 'ACTIVE'`
- **全 parent の** `currentOwner === caller.mspId` (事前 Transfer で集約しておくこと)

**検証エラー**:
- `PRODUCT_NOT_FOUND`: parent いずれか不在
- `PARENT_NOT_ACTIVE`: いずれかの親が CONSUMED
- `PARENTS_OWNER_DIVERGENT`: いずれかの親の currentOwner ≠ caller
- `CHILD_ALREADY_EXISTS`
- `INVALID_ARGUMENT`: parentIds 1 件以下 / 重複

**副作用**:
- 全 parent を `status=CONSUMED`, `children=[childId]` (append + sort) に更新
- child を新規 `putState`:
  - `manufacturer = caller.mspId` (接合者が新部材のメーカー扱い)
    - ※ 業務解釈: 接合部材の品質責任者は接合実施者。起点メーカーは parents 経由で遡れる
  - `currentOwner = caller.mspId`
  - `parents = [...parentIds].sort()`
  - `children = []`
  - `status = 'ACTIVE'`

---

### 6.5 ReadProduct (v1 互換)
**シグネチャ**: `ReadProduct(productId) -> Product(JSON)`

権限なし (全員可)。`PRODUCT_NOT_FOUND` 返却条件のみ。

---

### 6.6 GetHistory (v1 拡張)
**シグネチャ**: `GetHistory(productId) -> HistoryEvent[]`

**v2 追加イベント**:
| eventType | 発生条件 (state 差分) |
|---|---|
| `CREATE` | 最初の putState (v1 と同じ) |
| `TRANSFER` | `currentOwner` 変化 (v1 と同じ) |
| `SPLIT` | `status: ACTIVE → CONSUMED` かつ `children.length >= 2` |
| `MERGE` | `status: ACTIVE → CONSUMED` かつ `children.length === 1` |
| `SPLIT_FROM` | 子の初回 putState で `parents.length === 1` |
| `MERGE_FROM` | 子の初回 putState で `parents.length >= 2` |

CREATE / SPLIT_FROM / MERGE_FROM は **子 product の GetHistory** 先頭イベント。
SPLIT / MERGE は **親 product の GetHistory** 末尾イベント (CONSUMED 後は更新なし)。

**返却スキーマ**:
```json
{
  "eventType":  "CREATE" | "TRANSFER" | "SPLIT" | "MERGE" | "SPLIT_FROM" | "MERGE_FROM",
  "productId":  "...",
  "fromOwner":  "Org1MSP" | null,   // CREATE/SPLIT_FROM/MERGE_FROM では null 可
  "toOwner":    "Org3MSP" | null,
  "parents":    ["..."] | undefined, // SPLIT_FROM / MERGE_FROM で設定
  "children":   ["..."] | undefined, // SPLIT / MERGE で設定
  "actor":      { "mspId": "...", "id": "..." },
  "txId":       "...",
  "timestamp":  "ISO8601"
}
```

---

### 6.7 GetLineage (v2 新規)
**シグネチャ**: `GetLineage(productId) -> Lineage`

祖先方向の DAG を BFS で再帰的に収集する。

**アルゴリズム**:
1. `visited = new Set()`, `queue = [productId]`, `depth = 0`
2. queue が空になるまで BFS
3. 各ノードについて ReadProduct → `parents` を queue に追加
4. `depth > 20` で `LINEAGE_DEPTH_EXCEEDED` throw (防御)

**返却スキーマ**:
```json
{
  "root": "P1",
  "nodes": [
    {
      "id": "P1",
      "manufacturer": "Org3MSP",
      "currentOwner": "Org5MSP",
      "status": "ACTIVE",
      "metadata": {...},
      "millSheetHash": "...",
      "millSheetURI":  "..."
    },
    ...
  ],
  "edges": [
    { "from": "S1",   "to": "S1-a", "type": "SPLIT" },
    { "from": "S1-a", "to": "P1",   "type": "MERGE" },
    { "from": "S2",   "to": "P1",   "type": "MERGE" }
  ]
}
```

- `edges` は **親→子** 方向 (祖先 DAG)
- `type` は親の children 数で判定:
  - 親の children = 1 → MERGE (または単独 Split から生まれた子だが、親視点で children 1 なら Split/Merge 区別不能 → 子視点で親が 1 なら SPLIT、親が複数なら MERGE、の方が正確)
  - **判定ルール (最終版)**: 子の `parents.length === 1` → 親から見て SPLIT、`parents.length >= 2` → 親から見て MERGE
  - すなわち `edge.type` は常に子の parents 数で決まる (同じ子への全 edges が同一 type)
- `TRANSFER` は同一 productId 内の owner 遷移 → **edge に含めない** (DAG 簡潔化)
- 返却順: `nodes` は BFS 訪問順、`edges` は `(from, to)` 辞書順 (決定性)

---

## 7. Endorsement Policy

```
OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer','Org4MSP.peer','Org5MSP.peer')
```

**選定根拠**:
- 5Org のうち 1 Org 落ちてもデモ継続可能 (PoC の頑健性)
- 実務では用途別に `AND(...)` や閾値署名 (`2 out of 5`) が検討対象だが、PoC の観点では OR で十分
- 将来 Channel ポリシー / Chaincode ポリシーの分離検証を追加可能 (scope 外)

**invoke 運用**:
- `peer chaincode invoke --peerAddresses` には **2 peer 以上** 指定することを推奨
  - 1 peer commit は gossip 依存でタイミング不安定になる
  - scripts/invoke_as.sh はデフォルトで Org1 + Org3 を endorsement 先に指定

---

## 8. デモシナリオ (v2)

### 8.1 正常系 N1〜N4 (v1 継承、5Org 版)

| # | 操作 | 実施組織 |
|---|---|---|
| N1 | `CreateProduct S1` (鋼板 10t SS400) | Org1 (高炉メーカー A) |
| N2 | `TransferProduct S1 Org1→Org3` | Org1 |
| N3 | `TransferProduct S1 Org3→Org5` | Org3 |
| N4 | `GetHistory S1` / `ReadProduct S1` | Org5 |

### 8.2 v2 新規シナリオ

#### N5: 分割単独
```
CreateProduct S1 (Org1, 鋼板 10t)
TransferProduct S1 Org1→Org3
SplitProduct S1 → [S1-a(3t→Org3), S1-b(3t→Org5), S1-c(4t→Org3)]
```
検証: `ReadProduct S1` → `status=CONSUMED, children=[S1-a,S1-b,S1-c].sort()`。各子 `parents=[S1]`。

#### N6: 接合単独
```
CreateProduct S1 (Org1, 鋼板)
CreateProduct S2 (Org2, 形鋼)
TransferProduct S1 Org1→Org3
TransferProduct S2 Org2→Org3
MergeProducts [S1, S2] -> P1 (Org3 保有)
```
検証: `ReadProduct P1` → `parents=[S1,S2].sort(), manufacturer=Org3MSP`。S1/S2 が `CONSUMED`。

#### N7: 複合 (分割 → 接合 → 納品)
```
CreateProduct S1 (Org1, 鋼板 10t)
CreateProduct S2 (Org2, 形鋼 2t)
TransferProduct S1 Org1→Org3
TransferProduct S2 Org2→Org3
SplitProduct S1 → [S1-a(3t→Org3), S1-b(3t→Org5), S1-c(4t→Org3)]
MergeProducts [S1-a, S2] -> P1 (Org3 保有)
TransferProduct P1 Org3→Org5
```
最終状態: Org5 は `S1-b` (S1 分割片) と `P1` (S1-a + S2 接合部材) を保有。
`GetLineage P1` で以下の DAG:
```
S1 ─SPLIT→ S1-a ─MERGE→ P1
                          ↑
                    S2 ─MERGE
```

### 8.3 異常系

| # | シナリオ | 期待エラー |
|---|---|---|
| E1 | 所有者でない Org が TransferProduct | `OWNER_MISMATCH` |
| E2 | 存在しない productId の ReadProduct | `PRODUCT_NOT_FOUND` |
| E3 | 重複 productId の CreateProduct | `PRODUCT_ALREADY_EXISTS` |
| E4 | Org3MSP が CreateProduct | `MSP_NOT_AUTHORIZED` (v2: メーカーは Org1/Org2 のみ) |
| E5 | CONSUMED parent を再 Split | `PARENT_NOT_ACTIVE` |
| E6 | 異なる owner の親で Merge (事前集約忘れ) | `PARENTS_OWNER_DIVERGENT` |
| E7 | 既存 childId で Split/Merge | `CHILD_ALREADY_EXISTS` |

---

## 9. 決定性の担保

chaincode 内で以下を禁止・強制する (v1 踏襲 + v2 追加):

| 項目 | 扱い |
|---|---|
| `Date.now()` / `Math.random()` / `process.env` | 禁止 |
| `ctx.stub.getTxTimestamp()` | 時刻は必ずここから |
| `ctx.clientIdentity.getMSPID/getID` | actor 情報はここから |
| `parents` / `children` の格納 | `[...arr].sort()` で正規化 |
| `GetLineage` の edges 順序 | `(from, to)` 辞書順ソート |
| `GetLineage` の nodes 順序 | BFS 訪問順 (親 productId 昇順で enqueue) |
| 外部 HTTP | 禁止 |
| state に `history` 配列を保持 | 禁止 (GetHistoryForKey 一本化) |

---

## 10. 受け入れ条件

Issue #9 本文と等価。以下すべて満たす:

- [ ] 建設会社D (Org5) が Web UI で任意 productId から系譜 DAG を確認できる
- [ ] 加工業者 B/Y が Web UI で分割・接合を実行でき、5 Org 全員から一致した state が見える
- [ ] 電炉メーカー X (Org2) が A (Org1) と同じ UI で鋼材を登録でき、ミルシート URI / ハッシュを添付できる
- [ ] `scripts/demo_normal.sh --fresh` で「2 系統製造 → 分割 → 接合 → 納品」が 1 コマンド完走
- [ ] L1 単体テスト全緑 (Split / Merge / GetLineage / 複数メーカー権限 / metadata 含む)
- [ ] L2 結合テスト 5Org 全緑 (N5/N6/N7 + E4〜E7)
- [ ] `docs/architecture.md` / `demo-scenarios.md` / `README.md` が 5Org 版に更新
- [ ] `phase8-done` tag 付与

---

## 11. 将来拡張 (v3 以降候補)

- 子孫方向 GetLineage (リコール用途)
- 重量保存則の chaincode 検証 (許容誤差パラメータ化)
- Private Data Collection でミルシート本体を組織限定共有
- 複数チャネル (メーカー-加工業者 / 加工業者-建設会社 の分離)
- Fabric CA を用いた加工作業者レベルの identity 管理
- QR / RFID 連携で物理真正性との突合
- Grafana / Prometheus によるブロック生成モニタリング
