# PR

## 関連 Issue
Closes #

## ユーザー価値（必須）
<!--
この PR がマージされた瞬間、誰のどんな困りごとが解消されるか を1〜3行で書く。
「○○関数を追加した」ではなく「△△ユーザーが□□できるようになる」と書く。
技術タスク PR でも、最終的にどのユーザー価値に繋がるかを書く。
-->



## 変更概要
<!-- 何を変えたか 箇条書き -->
- 

## 受け入れ条件の達成確認
<!-- 紐付く Issue の Given/When/Then を貼り 各項目の確認結果を書く -->
- [ ] 
- [ ] 

## テスト
<!-- L1 / L2 / L3 のどれを実行したか、結果 -->
- [ ] L1 単体（`cd chaincode/product-trace && npm test`）
- [ ] L2 結合（`./scripts/test_integration.sh`）
- [ ] L3 受入（手動、Phase 7 のみ）
- [ ] 新規テストケース追加（あれば記述）

## デモ影響
<!-- デモシナリオに影響する変更か。ある場合 docs/demo-scenarios.md 更新済みか -->
- [ ] デモシナリオへの影響なし
- [ ] デモシナリオ更新済み（`docs/demo-scenarios.md`）

## Fabric 決定性チェック（chaincode 変更時のみ）
- [ ] `Date.now()` / `Math.random()` / `process.env` 不使用
- [ ] timestamp は `ctx.stub.getTxTimestamp()` 経由
- [ ] state に `history` 配列を追加していない
- [ ] 外部 I/O 無し

## スクリプト変更時のみ
- [ ] `set -euo pipefail` 明示
- [ ] 冪等性確認（2 回実行 OK）
- [ ] `reset.sh` で完全クリーンされる

## レビュー依頼先
<!-- Phase とエージェント対応表（CLAUDE.md）に従い どのエージェントに見せたか -->
- [ ] fabric-architect-reviewer
- [ ] devops-reproducibility-reviewer
- [ ] demo-storyteller-reviewer

## スクリーンショット / CLI 出力例
<!-- デモ or UI 変更時 -->

## チェックリスト
- [ ] `docs/spec.md` 変更なし（凍結）または変更理由を記載
- [ ] Conventional Commits 準拠
- [ ] ドキュメント更新（必要な場合）
