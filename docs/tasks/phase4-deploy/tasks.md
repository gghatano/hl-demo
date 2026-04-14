# Phase 4: デプロイ・運用スクリプト

## T4-1 `scripts/deploy_chaincode.sh`
- package / installAll / approveForMyOrg (3Org) / commit
- endorsement policy 明示:
  - `--signature-policy "OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')"`
- `version` / `sequence` 引数化（再デプロイ衝突回避）

## T4-2 `scripts/invoke_as.sh <org> <fn> <args...>`
- `CORE_PEER_*` 関数化 → Org 切替
- invoke 時 `--peerAddresses` 複数指定（endorsement policy 準拠）
