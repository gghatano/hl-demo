# Phase 7: 受け入れ確認

## T7-1 クリーン環境再現
- Ubuntu 22.04 クリーン VM or Docker コンテナ
- README のみから完走
- 受け入れ条件に昇格（spec.md §15-6）

## T7-2 リハーサル
- 5〜10 分 タイム計測

## T7-3 リカバリ保険
- CLI 出力 事前録画
- 主要シーン スクリーンショット
- Fabric 起動失敗時 フォールバック手順

## レビュー運用
- Chaincode 実装後: `fabric-architect-reviewer` 再レビュー
- スクリプト実装後: `devops-reproducibility-reviewer` 再レビュー
- デモリハ後: `demo-storyteller-reviewer` 再レビュー
