---
description: Phase 開始時のコンテキスト読込 + サブタスク登録 + 方針宣言
argument-hint: <phase番号 1-7>
---

Phase $ARGUMENTS の作業を開始せよ。

## 手順

### 1. 前提コンテキスト読込（並列可）
以下を必ず読み、要点を把握する:

- `CLAUDE.md`（プロジェクト規約、Phase 対応表、禁止事項）
- `docs/spec.md`（Phase $ARGUMENTS と関連する機能要件セクション）
- `docs/tasks/phase$ARGUMENTS-*/tasks.md`（今 Phase のタスク分解と申し送り節）
- `docs/fabric-pitfalls.md`（決定性・reset・bin/peer・GetHistory 等の既知罠）
- `docs/tasks/test-strategy.md`（L1/L2/L3 のうち今 Phase が該当するもの）

### 2. 現状確認
- `git log --oneline -10` で直近コミット履歴
- `git tag --sort=-creatordate | head -5` で最新 Phase タグ
- 前 Phase が `phaseN-done` tag で完了しているか確認
- 未完了で進めようとしていたら停止してユーザーに確認

### 3. ユーザー承認
`CLAUDE.md` 規約:「Phase 開始前 ユーザー承認必須」
- 把握した Phase $ARGUMENTS のゴール・サブタスク・申し送り事項を 200 字以内で要約
- 実装方針（TDD 可否、エージェント並列発火の有無等）を宣言
- ユーザーに「このまま進めてよいか」を問う

### 4. TaskCreate でサブタスク登録
承認後、`docs/tasks/phase$ARGUMENTS-*/tasks.md` の T<N>-<M> 単位で TaskCreate する。
各タスクに description（何をやるか）と activeForm（進行中表示）を付与。

### 5. 実装開始
- 先頭タスクを in_progress にしてから着手
- 完了毎に completed に更新
- 実装 → テスト → 必要ならユーザー確認の順
- コミット規約（Conventional Commits + Co-Authored-By trailer）遵守

### 6. Phase 完了時
- 全 L1/L2 テスト緑を確認
- `/phase-review $ARGUMENTS` で対応エージェントへレビュー発火
- 指摘反映 → commit → `git tag phase$ARGUMENTS-done` → push

## 注意

- **原始人モード維持**（CLAUDE.md §原始人モード）
- **決定性 chaincode 制約** を常に意識（Phase 3 以降）
- **destructive な git 操作・docker 破壊的コマンド** はユーザー確認必須
- **サブエージェント発火** は `Agent` tool + `subagent_type: general-purpose` で
  `.claude/agents/<name>.md` を読ませる方式（プロジェクト agent 定義は subagent_type に
  直接指定できない点に注意）
