# Phase 6: ドキュメント

## T6-1 `README.md`（spec.md §14 準拠）
- 目的 / 前提（バージョン明記）/ セットアップ / 起動 / デプロイ
- デモ手順 / 正常系期待結果 / 異常系期待結果
- クリーンアップ / よくあるエラー
- よくあるエラー必須項目:
  - ポート 7050/7051 衝突
  - WSL2 メモリ不足
  - dev-peer 残留

## T6-2 `docs/demo-scenarios.md`
- N1〜N4 / E1〜E3 期待結果
- **§スコープ外**（必須節）: spec.md §16 物理真正性非保証
- 口頭ナレーション用スクリプト（30秒 限界説明含む）

## T6-3 `docs/architecture.md`
- 組織 / Peer / Channel / Chaincode 図解
