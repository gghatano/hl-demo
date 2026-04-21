# よくあるエラーと対処

## ポート 7050 / 7051 / 9051 / 11051 が衝突

```
Error: port is already allocated
```

- 他の Fabric ネットワークや Node サーバーが同ポートを占有
- 対処: `sudo lsof -i :7050` で特定 → 停止、または `./scripts/reset.sh --yes`
- 関連: [`fabric-pitfalls.md` §ポート衝突](fabric-pitfalls.md)

## WSL2 メモリ不足 (peer が OOM で落ちる)

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

## `dev-peer*` chaincode コンテナ残留

前回デプロイの chaincode コンテナが残っていると、新しい package を install しても古いコードで動くことがある:

```
Chaincode invocation returned stale response
```

- 残留確認:
  ```bash
  docker ps -a --format '{{.Names}}' | grep '^dev-peer'
  ```
- 対処: `./scripts/reset.sh --yes` で `dev-peer*` と関連 image を一掃してから再デプロイ
- 関連: [`fabric-pitfalls.md` §chaincode コンテナ残留](fabric-pitfalls.md)

## `Cannot connect to the Docker daemon` (WSL2)

```
permission denied while trying to connect to the Docker daemon socket
```

- docker グループ未反映のシェルから実行している
- 対処 1: `newgrp docker` でグループ反映
- 対処 2: 一時回避として `sg docker -c './scripts/network_up.sh'` で包む
- 対処 3: 再ログインして `id` で `docker` グループが見えることを確認

## 既存 Fabric ネットワーク稼働中に `network_up.sh` を叩いた

```
Error: network supplychannel already exists
```

- 前回の起動が残存
- 対処: `./scripts/reset.sh --yes` を先に実行

## `test_integration.sh` が失敗した時の一次切り分け

L2 結合テストが落ちた場合、整形層で隠れた生エラーを直接確認:

```bash
./scripts/invoke_as.sh org3 query GetHistory <失敗した productId>
```

chaincode の `[CODE]` エラーメッセージが出る。それで判別できないときは:

```bash
docker logs peer0.org1.example.com | tail -100
# dev-peer コンテナ名はビルドごとに変わるため ps から動的に取得
DEV_CC=$(docker ps --format '{{.Names}}' | grep '^dev-peer0.org1.*product-trace' | head -1)
[[ -n "$DEV_CC" ]] && docker logs "$DEV_CC" | tail -100
```

## その他の落とし穴

実装中に踏んだ罠の完全リストは [`fabric-pitfalls.md`](fabric-pitfalls.md) に集約:

- Fabric 2.5.10 以前 × Docker 29+ → chaincode install が `broken pipe`
- Node chaincode package に `node_modules` を含めると `broken pipe`
- lifecycle skip 判定は seq/ver だけでなく `package_id` まで見る
- `bin/peer` 直呼びには `FABRIC_CFG_PATH=<samples>/config` 必須
- sudo でスクリプト実行すると root 所有ファイルが残って次に詰む
- chaincode エラーは `[CODE]` プレフィックス付き（message 本文しか伝搬しない）
- MVCC_READ_CONFLICT 時のリトライ
- **macOS Docker Desktop の socket proxy で `No such image: hyperledger/fabric-nodeenv:2.5` → Colima に移行**
- macOS bash 3.2 で `${var,,}: bad substitution` → scripts は 3.2 互換で書く
