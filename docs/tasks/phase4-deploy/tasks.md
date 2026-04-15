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

## Phase 5 への申し送り（fabric-pitfalls.md 参照）

- Fabric は必ず v2.5.15 以上を使う。`setup.sh` の pin に根拠コメント済。
  ダウングレードすると Docker 29+ 下で chaincode install が壊れる
- `invoke_as.sh` は現状 3 peer 固定で叩いている (OR policy なのに実質 AND)。
  Phase 5 の `demo_error.sh` で「Org を 1 つ落としても OR で通る」を見せたい場合、
  `PEER_TARGETS` env で target を絞れるように拡張余地あり
- Admin MSP で invoke しているので `lastActor.id` が `Admin@orgN` の DN で固定。
  将来 Fabric CA 発行の user cert に切り替えると history の actor 文字列が不連続になる。
  T5-3 の出力整形層 (Org1MSP → メーカー A) で差分吸収すること
- `deploy_chaincode.sh` 再デプロイは `-v` と `-s` を同時に上げること (READMEでも案内)
- L2 smoke (`test_integration.sh`) は T5-x で新規作成。本 Phase の手動 smoke は
  fabric-architect-reviewer のレビュー指摘を消し込んだ状態で下記を確認済:
  - 正常系 N1-N4 (Create → Transfer A→B → Transfer B→C → GetHistory)
  - 異常系 E3 (PRODUCT_ALREADY_EXISTS で拒否)
  - 冪等: 2 回目の deploy_chaincode.sh が全 skip で完走
