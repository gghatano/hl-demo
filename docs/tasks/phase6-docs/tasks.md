# Phase 6: ドキュメント

## Phase 5 からの申し送り

- `scripts/demo_normal.sh` は末尾で `.last_product_id` を repo root に書き出す。
  `scripts/demo_verify_as_c.sh` は引数省略時にこれを読む。README のデモ手順は
  この引継ぎを前提に、`demo_normal.sh → demo_verify_as_c.sh`（引数なし）で繋ぐ
- `demo_normal.sh` 末尾に「スコープと限界 30 秒ナレーション」が入っている。
  T6-2 `demo-scenarios.md` の §スコープ外 と内容を揃える（物理真正性非保証 /
  QR/RFID/IoT で補う前提）
- `scripts/test_integration.sh` は L2 主戦場。よくあるエラー節に以下を含める:
  - WSL2 で `docker daemon に接続できない` → `sg docker -c "..."` で実行、または
    `newgrp docker` でグループ反映
  - `既存の Fabric コンテナが稼働中` → `scripts/reset.sh --yes` を先に
  - test 失敗時の diagnostic は `scripts/invoke_as.sh org3 query GetHistory <id>`
    を直叩きして生の chaincode エラーを確認する
- chaincode エラーは `[CODE]` プレフィックス付き（Phase 3 申し送り継続）。
  README/scenarios のエラー例示でもコード名を前面に出す
- Phase 5 で `docs/fabric-pitfalls.md` に 3 節追加:
  「peer CLI ログ抑制」「bash サブシェルで集計すると親を継承」「reset.sh --yes 伝搬」。
  README のトラブルシュート欄から `docs/fabric-pitfalls.md` へのリンクを張る

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
