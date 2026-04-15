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

---

## Phase 7 への申し送り

### 受入テストで検証してほしいこと
- **README 記載コマンドの実機整合**: 特に `invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP`
  の引数順 / フラグ名 / 出力形式が、クリーン環境で README 通りにコピペ実行して通ること。
  Phase 6 レビューで「未検証」として Major 指摘された項目。ヘッダコメントでは整合を確認
  済みだが、実機でのコピペ完走が最終確認
- **デモ所要時間の実測校正**: README / demo-scenarios は暫定「5〜7 分」としている。
  Phase 7 リハで実測し、必要なら両文書の時間表を書き換える。`DEMO_PAUSE` をいくつに
  したかも記録しておくとデモ担当者に親切
- **dev-peer コンテナ名の動的取得コマンド**: README トラブルシュート節の
  `docker ps --format ... | grep '^dev-peer0.org1.*product-trace'` が実環境の
  コンテナ名パターンに一致するか確認。fabric-samples のバージョンが上がると
  サフィックス形式が変わる可能性あり

### リカバリ保険（T7-3）用の素材候補
- `demo_normal.sh` / `demo_verify_as_c.sh` / `demo_error.sh` の CLI 出力を
  事前録画（`script` コマンド or asciinema）しておくと、当日 Fabric 起動失敗時に
  代替再生できる
- 主要シーン: N4 GetHistory 一覧 / C 視点クライマックスの「#1 by メーカー A」行 /
  E1 `[OWNER_MISMATCH]` エラー表示 — この 3 枚はスクショ必須
- `reset.sh --yes` → `network_up.sh` → `deploy_chaincode.sh` の起動失敗時の
  フォールバック判断フロー（どこまで戻すか）を簡易手順化

### ドキュメント整合性メモ
- README / demo-scenarios / architecture の 3 文書は **業務語彙（メーカー A / 卸 B / 販売店 C）**
  と **MSP ID（Org1MSP / Org2MSP / Org3MSP）** を併記するスタイルで統一済み。
  Phase 7 中に追記する場合もこのルールを維持
- E1 の筋書きは「C が嘘の由来を主張して横取りを試みる」で README / demo-scenarios
  両方統一済み。別の言い換えを加える場合はどちらか片方だけ変えないこと
- スコープ外宣言（物理真正性非保証）は README §非対象 と demo-scenarios §スコープ外
  の 2 箇所で整合。Phase 7 のデモでも末尾 30 秒ナレーションは必須
