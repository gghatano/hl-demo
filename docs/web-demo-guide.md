# Web デモガイド

ブラウザ上でサプライチェーン・トレーサビリティのデモを実施する手順。

---

## 前提条件

- Fabric ネットワーク起動済み (`./scripts/network_up.sh`)
- Chaincode デプロイ済み (`./scripts/deploy_chaincode.sh`)
- Node.js >= 18

## 起動

```bash
./scripts/web_demo.sh
```

ブラウザで `http://localhost:3000` を開く。

## 停止

ターミナルで `Ctrl+C`。

---

## 画面構成

| エリア | 説明 |
|---|---|
| ヘッダー | 操作組織の選択（メーカー A / 卸 B / 販売店 C） |
| 製品登録 | 製品 ID を入力して登録（メーカー A のみ） |
| 製品移転 | 製品 ID と移転先を指定して移転 |
| 製品照会 | 製品 ID で現在の状態を確認 |
| 来歴照会 | 製品 ID で全履歴をタイムライン表示 |
| 結果表示 | 操作結果・エラーメッセージを表示 |

---

## デモシナリオ（正常系）

### N1: 製品登録

1. 組織を **メーカー A** に切替
2. 「製品登録」パネルで製品 ID に `X001` を入力
3. 「登録」ボタンをクリック
4. 結果: `currentOwner: Org1MSP` が表示される

### N2: A → B へ移転

1. 組織は **メーカー A** のまま
2. 「製品移転」パネルで製品 ID に `X001`、移転先に `Org2MSP - 卸 B` を選択
3. 「移転」ボタンをクリック
4. 結果: `currentOwner: Org2MSP` に更新

### N3: B → C へ移転

1. 組織を **卸 B** に切替
2. 「製品移転」パネルで製品 ID に `X001`、移転先に `Org3MSP - 販売店 C` を選択
3. 「移転」ボタンをクリック
4. 結果: `currentOwner: Org3MSP` に更新

### N4: C による来歴確認

1. 組織を **販売店 C** に切替
2. 「来歴照会」パネルで製品 ID に `X001` を入力
3. 「来歴確認」ボタンをクリック
4. 結果:
   - フローチェーン: `メーカー A → 卸 B → 販売店 C`
   - 起点検証: 「OK: メーカー A (Org1MSP) が登録」
   - タイムライン: CREATE → TRANSFER → TRANSFER の 3 イベント

---

## デモシナリオ（異常系）

### E1: 所有者偽装

1. 組織を **メーカー A** に切替
2. `X001` を移転しようとする（既に C が所有）
3. 結果: エラー「fromOwner does not match currentOwner」

### E2: 未登録照会

1. 「製品照会」で `X999` を照会
2. 結果: エラー「product not found: X999」

### E3: 重複登録

1. 組織を **メーカー A** に切替
2. 既に登録済みの `X001` を再登録
3. 結果: エラー「product already exists: X001」

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `Fabric ネットワーク未起動` | `./scripts/network_up.sh` を実行 |
| `Chaincode 未デプロイ` | `./scripts/deploy_chaincode.sh` を実行 |
| `npm install` 失敗 | Node.js >= 18 か確認。`rm -rf web/node_modules && ./scripts/web_demo.sh` |
| gRPC 接続エラー | Fabric コンテナが正常か `docker ps` で確認 |
| ポート 3000 使用中 | `PORT=3001 ./scripts/web_demo.sh` で別ポート指定 |

---

## REST API リファレンス

全エンドポイントにクエリパラメータ `?org=org1|org2|org3` で操作組織を指定。

| Method | Path | Body | 説明 |
|---|---|---|---|
| GET | `/api/orgs` | - | 組織一覧 |
| POST | `/api/products` | `{"productId":"X001"}` | 製品登録 |
| POST | `/api/products/:id/transfer` | `{"toOwner":"Org2MSP"}` | 製品移転 |
| GET | `/api/products/:id` | - | 製品照会 |
| GET | `/api/products/:id/history` | - | 来歴照会 |
