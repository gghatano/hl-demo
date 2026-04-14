# Phase 2: ネットワーク構築

## 方針（Issue #1 決定事項）
- fabric-samples 標準 MSP ID（`Org1MSP` / `Org2MSP` / `Org3MSP`）をそのまま採用
- 業務語彙変換は T5-3 出力整形層で行う
- 対応: `Org1MSP` = メーカー A / `Org2MSP` = 卸 B / `Org3MSP` = 販売店 C

## T2-1 3Org 化（test-network 標準フロー使用）
- `network.sh up createChannel -c supplychannel -ca` で 2Org 起動
- `addOrg3/addOrg3.sh up -c supplychannel -ca` で Org3 合流
- patches は使わない（fabric-samples 追従コスト回避）

## T2-2 Channel
- `supplychannel` 作成
- 3 Peer join

## T2-3 `scripts/network_up.sh` / `scripts/reset.sh`
- reset 完全クリーン:
  - `dev-peer*` chaincode コンテナ全削除
  - `net_test` / Fabric docker network 削除
  - Fabric volume 明示 prune
  - `organizations/` 生成物削除
