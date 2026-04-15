# デモシナリオ詳細

`spec.md` §9 のシナリオ N1〜N4 / E1〜E3 を、デモ担当者が **実演しながら語れる** 粒度に展開したもの。正常系 → C 視点クライマックス → 異常系の 3 段構成で約 5 分。

---

## 目次

- [前提](#前提)
- [登場人物と語彙対応](#登場人物と語彙対応)
- [全体フロー（5 分構成）](#全体フロー5-分構成)
- [正常系シナリオ](#正常系シナリオ)
  - [N1: 製品登録](#n1-製品登録)
  - [N2: A → B 移転](#n2-a--b-移転)
  - [N3: B → C 移転](#n3-b--c-移転)
  - [N4: C による履歴確認](#n4-c-による履歴確認)
- [C 視点クライマックス](#c-視点クライマックス)
- [異常系シナリオ](#異常系シナリオ)
  - [E1: 所有者偽装](#e1-所有者偽装)
  - [E2: 未登録製品の照会](#e2-未登録製品の照会)
  - [E3: 重複登録](#e3-重複登録)
- [口頭ナレーション（30 秒 スコープ説明）](#口頭ナレーション30-秒-スコープ説明)
- [スコープ外（このデモが扱わないこと）](#スコープ外このデモが扱わないこと)

---

## 前提

- ネットワーク起動 + chaincode デプロイ済み（[`README.md`](../README.md#セットアップ手順) 参照）
- 画面は 1 枚のターミナルで完結。事前に `./scripts/reset.sh --yes && ./scripts/network_up.sh && ./scripts/deploy_chaincode.sh` を済ませておく
- または `./scripts/demo_normal.sh --fresh` でクリーン状態から一括実行可能

---

## 登場人物と語彙対応

| 業務語彙 | MSP ID | 役割 | chaincode 権限 |
|---|---|---|---|
| メーカー A | `Org1MSP` | 製造元 | `CreateProduct` 可 |
| 卸 B | `Org2MSP` | 中間流通 | `TransferProduct`（現所有者時） |
| 販売店 C | `Org3MSP` | 最終販売 | `TransferProduct`（現所有者時） / 履歴照会 |

内部 MSP ID は fabric-samples 標準の `Org1MSP`/`Org2MSP`/`Org3MSP` を使用し、表示層 `scripts/lib/format.sh` で業務語彙に変換する。

---

## 全体フロー（5 分構成）

| 時間 | フェーズ | スクリプト | 目的 |
|---|---|---|---|
| 0:00–0:30 | 課題提起 / 登場人物 | `demo_normal.sh` 冒頭ナレーション | 「なぜ必要か」を共有 |
| 0:30–2:00 | 正常系 N1〜N3 | `demo_normal.sh` | A→B→C の譲渡を台帳に記録 |
| 2:00–3:00 | C 視点クライマックス | `demo_verify_as_c.sh` | 起点 A を C の立場で証明 |
| 3:00–4:30 | 異常系 E1〜E3 | `demo_error.sh` | 「書けないはずのものは書けない」 |
| 4:30–5:00 | スコープと限界 | 口頭ナレーション | 物理真正性は別論点（後述） |

---

## 正常系シナリオ

### N1: 製品登録

**語り**: 「メーカー A が出荷前の最終工程で、製品 `X001` を台帳に登録します。登録できるのは A だけ。他社が A を騙ることは chaincode 層で拒否されます。」

**コマンド**:
```bash
./scripts/invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP
```

**期待結果（整形後）**:
```
productId    : X001
manufacturer : メーカー A (Org1MSP)
currentOwner : メーカー A (Org1MSP)
status       : ACTIVE
createdAt    : 2026-04-15T09:00:00.000Z
updatedAt    : 2026-04-15T09:00:00.000Z
```

**検証ポイント**:
- `currentOwner == Org1MSP`
- `manufacturer == Org1MSP`（以降不変）
- `createdAt == updatedAt`（登録時は同時刻）
- timestamp は `ctx.stub.getTxTimestamp()` 由来（全 endorser で同一）

---

### N2: A → B 移転

**語り**: 「A が出荷し、卸 B に所有権が移ります。`fromOwner` を A、`toOwner` を B として TransferProduct を呼びます。chaincode は現所有者 = fromOwner = 呼び出し主体 を三点照合します。」

**コマンド**:
```bash
./scripts/invoke_as.sh org1 invoke TransferProduct X001 Org1MSP Org2MSP
```

**期待結果**:
```
productId    : X001
manufacturer : メーカー A (Org1MSP)
currentOwner : 卸 B (Org2MSP)
status       : ACTIVE
updatedAt    : 2026-04-15T09:05:00.000Z   ← 更新
```

**検証ポイント**:
- `currentOwner == Org2MSP`
- `manufacturer` は変わらず `Org1MSP`
- `updatedAt` のみ更新

---

### N3: B → C 移転

**語り**: 「さらに卸 B が販売店 C に譲渡します。今度は B の credential で invoke しないと通りません。A が代理実行することはできない。」

**コマンド**:
```bash
./scripts/invoke_as.sh org2 invoke TransferProduct X001 Org2MSP Org3MSP
```

**期待結果**:
```
currentOwner : 販売店 C (Org3MSP)
updatedAt    : 2026-04-15T09:10:00.000Z
```

---

### N4: C による履歴確認

**語り**: 「C の手元の台帳から履歴を取得します。C は自組織 peer に問い合わせているので、A や B の言い分を信用する必要がありません。」

**コマンド**:
```bash
./scripts/invoke_as.sh org3 query GetHistory X001
```

**期待結果（整形後）**:
```
#1 CREATE    by メーカー A (Org1MSP)
    at   : 2026-04-15T09:00:00.000Z
    txId : a1b2c3...

#2 TRANSFER  by メーカー A (Org1MSP)   Org1MSP → Org2MSP
    at   : 2026-04-15T09:05:00.000Z
    txId : d4e5f6...

#3 TRANSFER  by 卸 B    (Org2MSP)   Org2MSP → Org3MSP
    at   : 2026-04-15T09:10:00.000Z
    txId : 7890ab...
```

**検証ポイント**:
- 3 件が時系列順
- `#1.eventType == "CREATE"` かつ `#1.actor.mspId == Org1MSP` → **起点 A の証明**
- 各イベントに `txId` が付与されており後から同じ block を参照可能
- GetHistoryForKey は state 変遷のスナップショット列を返す（詳細: [`fabric-pitfalls.md`](fabric-pitfalls.md) §GetHistoryForKey）

---

## C 視点クライマックス

**スクリプト**: `./scripts/demo_verify_as_c.sh`（引数省略時は `demo_normal.sh` が書いた `.last_product_id` を自動取得）

**語り**:
> 「販売店 C のカウンターに商品 `X001` が並んでいる。流通過程で差し替わっていないか？ C は A や B に問い合わせる必要はなく、自組織 `Org3MSP` のクレデンシャルで、自組織 peer に履歴を尋ねるだけでよい。
>
> 結果 ── #1 のイベントは `CREATE`、実行主体は `Org1MSP` = メーカー A。その後 B を経由し、C の手元に届いた。**この履歴は B や C の主張ではなく、3 社のネットワーク全体で合意・承認されたもの** だ。」

**強調すべき点**:
- C は誰かを信用する必要がない（trust-minimized）
- `#1.actor.mspId == Org1MSP` を条件に「起点 A である」を機械判定できる
- 改ざんしようとすれば chaincode の所有者照合 or endorsement policy で弾かれる

---

## 異常系シナリオ

### E1: 所有者偽装

**攻撃者シナリオ**: 販売店 C が「これは直前まで B が持っていた product だ」と嘘の由来を主張し、B→C の移転を自分の Credential で書き込もうとする。

**コマンド**:
```bash
./scripts/invoke_as.sh org3 invoke TransferProduct X001 Org2MSP Org3MSP
```

**期待結果**:
```
Error: endorsement failure during invoke.
response: status:500 message:"[OWNER_MISMATCH] caller Org3MSP does not match fromOwner Org2MSP"
```

**検証二段構え**:
1. exit code ≠ 0、`[OWNER_MISMATCH]` エラーコードが付与されている
2. 直後に `GetHistory X001` を再実行し、履歴に新規イベントが追加されていないこと

**chaincode ロジック**: `ctx.clientIdentity.getMSPID()` と `fromOwner` を照合し、不一致なら `throw new Error('[OWNER_MISMATCH] ...')`。throw により endorsement failure となり block には載らない。

---

### E2: 未登録製品の照会

**語り**: 「偽の追跡番号を投げられても、chaincode は静かに成功を返さない。」

**コマンド**:
```bash
./scripts/invoke_as.sh org3 query ReadProduct GHOST-001
```

**期待結果**:
```
Error: [PRODUCT_NOT_FOUND] productId=GHOST-001
```

**検証ポイント**:
- 読み取り専用なので副作用なし（履歴の汚染が原理的に発生しない）
- エラーコードが明示的で、UI 側でユーザ向けメッセージへ変換可能

---

### E3: 重複登録

**攻撃者シナリオ**: 既存の `X001` と同じ productId で CreateProduct を再実行し、履歴の分岐を起こして起点を曖昧にしようとする。

**コマンド**:
```bash
./scripts/invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP
```

**期待結果**:
```
Error: endorsement failure ...
message:"[PRODUCT_ALREADY_EXISTS] productId=X001"
```

**検証二段構え**:
1. exit code ≠ 0、`[PRODUCT_ALREADY_EXISTS]` エラーコード
2. `GetHistory X001` で既存 3 件（CREATE / TRANSFER / TRANSFER）のまま。重複 CREATE は追加されない

---

## エラーコード一覧

| コード | 発生条件 | 対応 chaincode 関数 |
|---|---|---|
| `[OWNER_MISMATCH]` | 呼び出し主体 ≠ 現所有者 / fromOwner | `TransferProduct` |
| `[PRODUCT_NOT_FOUND]` | 指定 productId が未登録 | `ReadProduct` / `TransferProduct` / `GetHistory` |
| `[PRODUCT_ALREADY_EXISTS]` | 既存 productId に CreateProduct | `CreateProduct` |
| `[INITIAL_OWNER_MISMATCH]` | 登録主体 ≠ initialOwner | `CreateProduct` |

全て `throw new Error('[CODE] ...')` で endorsement failure を誘発する形式。詳細は [`fabric-pitfalls.md`](fabric-pitfalls.md) §chaincode エラーは message 本文しか伝搬しない 参照。

---

## 口頭ナレーション（30 秒 スコープ説明）

デモ末尾で必ず語るべき 30 秒スクリプト（`demo_normal.sh` 末尾にも埋め込み済み）:

> **このデモが示すのは「台帳に載った情報は改ざんされない」ことです。**
>
> 逆に言えば、台帳に載せる前 ── **モノ自体の真正性** ── は別レイヤーの論点になります。
>
> - 現物のすり替え
> - 偽タグの貼付
> - productId と物理製品の紐付けズレ
>
> これらは QR コード / RFID / IoT センサー / 真正品判定デバイスなど、物理世界側の仕組みと組み合わせて補う前提です。
>
> 本 PoC はあくまで **組織間で譲渡履歴を共有・検証する部分** を扱います。台帳への入力が正しいことを前提に、入力後の一貫性・改ざん困難性を保証する層です。

---

## スコープ外（このデモが扱わないこと）

`spec.md` §3.2 および §16 に基づく非対象領域。デモ中に質問された場合の回答テンプレート:

### 物理真正性は保証しない（最重要）

**保証する**: 台帳上の来歴の一貫性、参加者間で共有された記録の改ざん困難性

**保証しない**: 現実世界の物理製品が本当に当該 productId に対応していること

具体的に別論点となるもの:

- **QR コード貼付** — シールを剥がして別商品に貼り替える攻撃には無力
- **RFID タグ** — タグ自体の複製 / リーダー側での入力改ざん
- **IoT センサー連携** — センサーデータの真正性は別途担保が必要
- **真正品判定デバイス** — 現物と productId の 1:1 対応を保証する仕組み

これらは将来拡張の論点として `spec.md` §17 に記載。

### その他の非対象

- 本番運用向けの可用性設計 / HA（Raft 単一ノード orderer のため）
- 大規模性能試験
- 外部 ERP / 在庫管理システムとの本格連携
- 高度な秘密計算 / プライバシー強化技術の統合
- Web UI / 可視化（CLI のみ）
- Fabric CA 発行の end-user cert による認可（現状は Admin MSP 固定）

---

## デモ後の Q&A 想定

| 想定質問 | 回答要旨 |
|---|---|
| 「誰が書き換えを試みても止まるの？」 | chaincode の所有者照合 + endorsement policy (OR 3Org) の 2 段で止まる。E1 が実演例 |
| 「1 社だけが嘘をついたら？」 | 残り 2 社の peer が承認しなければ block に載らない（OR ポリシーで最低 1 peer 必要だが、invoke 者自身以外の peer も照合される設計も選択可能） |
| 「QR コードを貼り替えられたら？」 | **台帳の外の話** 。上述「物理真正性は保証しない」を参照 |
| 「本番でも使える？」 | いいえ、PoC。HA / 性能 / CA 運用 / キー管理などは別途設計必要 |
| 「historic query は誰でもできる？」 | 本 PoC ではチャンネル参加者全員が可。本番では Private Data Collection 等で閲覧制御可能 |

---

## 関連ドキュメント

- [`README.md`](../README.md) — セットアップ・コマンドリファレンス
- [`spec.md`](spec.md) — 機能仕様（凍結）
- [`architecture.md`](architecture.md) — 構成図
- [`fabric-pitfalls.md`](fabric-pitfalls.md) — 実装時の落とし穴集
