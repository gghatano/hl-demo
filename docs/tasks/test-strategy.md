# テスト戦略

## 前提
本デモ PoC。商用品質テスト不要。目的 = 「受け入れ条件（spec.md §15）満たす」＋「デモ本番事故回避」。

## 3層

### L1 単体（Unit）— Chaincode ロジック
- 対象: `chaincode/product-trace/` の Contract 関数
- ツール: `fabric-contract-api` + `fabric-shim` mock（`sinon-chai` / `chai-as-promised`）
- 実 Fabric 起動不要 → 高速（ミリ秒）
- 検証観点:
  - `CreateProduct`: 正常 / 重複拒否 / `initialOwner !== manufacturer` 拒否 / 非 OrgA 呼出 拒否
  - `TransferProduct`: 正常 / `fromOwner !== currentOwner` 拒否 / MSP 不一致 拒否 / 未登録拒否
  - `ReadProduct`: 正常 / 未登録エラー
  - `GetHistory`: 昇順整形 / IsDelete スキップ / txId・timestamp 取得
  - `getTxTimestampISO`: 決定性（固定入力 → 固定出力）
- 配置: `chaincode/product-trace/test/`
- 実行: `npm test`（Phase 3 完了条件）

### L2 結合（Integration）— 実 Fabric + Chaincode
- 対象: 3Org ネットワーク＋deploy 済み chaincode に対し invoke/query
- 前提: `network_up.sh` + `deploy_chaincode.sh` 成功
- 実行: bash スクリプト（`scripts/test_integration.sh`）
  - 各 step `invoke_as.sh` 呼出 → 戻り値 / stdout を `grep` / `jq` で assert
  - 失敗時 exit 1
- 検証観点:
  - endorsement policy 通りの commit 成功
  - 3Org 間 state 同期（A invoke 後 C から read 可）
  - history txId が複数ブロックに分散
  - 非決定性エラーが起きないこと（複数回実行で同値）
- demo スクリプトと棲み分け:
  - demo_* = 人向け、ナレーション付き、assert 無し
  - test_integration.sh = CI/自動、assert 有り、整形出力 無し
- 配置: `scripts/test_integration.sh` + `tests/integration/cases/*.sh`

### L3 E2E / 受け入れ（Acceptance）
- 対象: クリーン環境 → README 手順のみ → 完走
- 実行: 手動 or Docker コンテナ（Ubuntu 22.04 base）
- 検証観点: spec.md §15 受け入れ条件 1〜7 すべて
- Phase 7 タスク相当

## phase マッピング

| Phase | L1 | L2 | L3 |
|---|---|---|---|
| 1 環境 | — | — | — |
| 2 ネットワーク | — | network_up 正常終了 smoke | — |
| 3 Chaincode | **主戦場** T3-6 | — | — |
| 4 デプロイ | — | deploy smoke（commit 成功確認） | — |
| 5 デモ | — | **主戦場** test_integration.sh | — |
| 6 ドキュメント | — | — | — |
| 7 受入 | — | — | **主戦場** |

## テストピラミッド方針
- L1 厚め（chaincode バグを早期検知、実Fabric起動せず高速反復）
- L2 シナリオ網羅（N1〜N4 / E1〜E3）
- L3 最後に1〜2回（クリーンVM 完走）

## CI 方針
- PoC なので CI 任意
- ローカル `npm test`（L1）＋ `test_integration.sh`（L2）を Phase 完了条件にする
- L3 は手動リハ

## 既存 demo スクリプトとの関係
- `demo_error.sh` は assert 無しナレーション付き
- `test_integration.sh` は同シナリオを assert 付きで再実装（責務分離）
- 共通化したい場合 L2 assert を関数化し demo スクリプトから import（任意）

## エージェントレビュー タイミング
- L1 完了後: `fabric-architect-reviewer`
- L2 完了後: `devops-reproducibility-reviewer`
- L3 リハ後: `demo-storyteller-reviewer`
