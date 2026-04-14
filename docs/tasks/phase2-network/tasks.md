# Phase 2: ネットワーク構築

## T2-1 3Org化（`addOrg3` サンプル差分起点）
- T2-1a MSP ID 統一: `OrgAMSP` / `OrgBMSP` / `OrgCMSP`
- T2-1b CA / Peer / Orderer ポート割当（衝突回避）
- T2-1c 差分パッチ版管理: `configtx.yaml` / `crypto-config*.yaml` / `docker-compose-org3.yaml`
  - 配置: `fabric/test-network-wrapper/patches/`

## T2-2 Channel
- `supplychannel` 作成
- 3 Peer join

## T2-3 `scripts/network_up.sh` / `scripts/reset.sh`
- reset 完全クリーン:
  - `dev-peer*` chaincode コンテナ全削除
  - `net_test` / Fabric docker network 削除
  - Fabric volume 明示 prune
  - `organizations/` 生成物削除
