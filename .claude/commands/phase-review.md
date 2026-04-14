---
description: Phase 完了時レビューを対応エージェントへ並列発火
argument-hint: <phase番号 1-7>
---

Phase $ARGUMENTS の完了レビュー依頼を実行せよ。

## 手順

1. `docs/tasks/phase$ARGUMENTS-*/tasks.md` を読む
2. `CLAUDE.md` の「Phase とエージェントの対応」表を参照し、対象エージェントを特定
3. 以下のマッピングで並列起動（`Agent` tool、`run_in_background: true`）:

| Phase | fabric | devops | demo |
|---|---|---|---|
| 1 | — | ✓ | — |
| 2 | ✓ | ✓ | — |
| 3 | ✓ | — | — |
| 4 | ✓ | ✓ | — |
| 5 | — | ✓ | ✓ |
| 6 | — | ✓ | ✓ |
| 7 | ✓ | ✓ | ✓ |

4. 各エージェントへのプロンプトに必ず含める:
   - `docs/spec.md` を読め
   - `CLAUDE.md` を読め
   - `docs/fabric-pitfalls.md` を読め（fabric エージェントのみ）
   - 自分のエージェント定義ファイル（`.claude/agents/<name>.md`）のチェックリストに従え
   - 対象 Phase の成果物パスを明示（chaincode/, scripts/, docs/ 等）
   - 出力形式を遵守
   - 日本語 600 字以内

5. 並列起動後 各完了通知を待つ
6. 全エージェント完了後、指摘を統合し優先度順に提示
7. ユーザーに「次 Phase へ進む」or「指摘を反映して再実行」を確認

## 注意
- 実装エージェントではないので コード変更は依頼しない
- レビュー結果のみを要求
- 原始人モード維持
