# Phase 5: デモシナリオ

## Phase 3 からの申し送り（fabric-pitfalls.md 参照）
- chaincode エラーは message 先頭に `[CODE]` プレフィックス付き
  （例: `[OWNER_MISMATCH] ...`、`[PRODUCT_NOT_FOUND] ...`）
- `demo_error.sh` / `test_integration.sh` で異常系を判定する際は
  `grep '\[OWNER_MISMATCH\]'` のように **エラーコード単位で grep** すること
  （message 本文の日本語変化に壊れない）
- `GetHistory` 応答の `actor` は `{mspId, id}` オブジェクト。
  T5-3 出力整形では `actor.mspId` を業務語彙にマップする

## T5-0 冒頭ナレーション
- `demo_normal.sh` 先頭で echo
- 課題提起: 偽装転売・中抜きの痛み
- 登場人物: 「メーカー A」「卸 B」「販売店 C」

## T5-1 `scripts/demo_normal.sh`
- N1 登録 → N2 A→B → N3 B→C
- `--fresh` フラグで reset→up→deploy 連動
- コマンド実行前 意図 echo（ナレーション可能）
- `set -x` 生ログ垂れ流し回避

## T5-2 `scripts/demo_error.sh`
- E1 所有者不一致 / E2 未登録照会 / E3 重複登録
- 各ケース後 履歴再照会 → 改ざん不在を見せる（二段構え）

## T5-3 出力整形ライブラリ
- bash 関数 or jq テンプレ
- 組織コード → 業務語彙（`Org1MSP` → `メーカー A` / `Org2MSP` → `卸 B` / `Org3MSP` → `販売店 C`）
- 履歴 表形式: `#1 CREATE A / #2 TRANSFER A→B / #3 TRANSFER B→C`
- 生 JSON 直接表示 禁止

## T5-5 `scripts/test_integration.sh`（L2 主戦場）
- N1〜N4 / E1〜E3 を assert 付きで再実装
- demo_* と責務分離（ナレーション無し・整形無し・exit code で成否）
- 配置: `tests/integration/cases/*.sh`
- 詳細: [test-strategy.md#L2](../test-strategy.md)

## T5-4 `scripts/demo_verify_as_c.sh`（クライマックス独立）
- N4 分離
- 画面クリア → 「C の立場で確認」ナレーション → 履歴表示 → A 起点ハイライト
- 単独再実行可能
