# Phase 4: デプロイ・運用スクリプト

## Phase 2 からの申し送り（fabric-pitfalls.md 参照）
- `bin/peer` 直呼び時は `FABRIC_CFG_PATH=${SAMPLES_DIR}/config` を必ず export
  （`deploy_chaincode.sh` / `invoke_as.sh` 両方で必要）
- sudo 実行環境では root 所有ファイル問題に留意。docker グループ加入を
  `docs/prerequisites.md` に明記することを検討
- Org3 視点の動作確認は `network_up.sh` verify 側で既に通っている前提

## T4-1 `scripts/deploy_chaincode.sh`
- package / installAll / approveForMyOrg (3Org) / commit
- endorsement policy 明示:
  - `--signature-policy "OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')"`
- `version` / `sequence` 引数化（再デプロイ衝突回避）

## T4-2 `scripts/invoke_as.sh <org> <fn> <args...>`
- `CORE_PEER_*` 関数化 → Org 切替
- invoke 時 `--peerAddresses` 複数指定（endorsement policy 準拠）
