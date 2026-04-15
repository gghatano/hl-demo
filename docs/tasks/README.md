# 開発タスク

docs/spec.md ベース。3エージェント レビュー反映済み。

- [Phase 1 環境準備](phase1-env/tasks.md)
- [Phase 2 ネットワーク構築](phase2-network/tasks.md)
- [Phase 3 Chaincode 実装](phase3-chaincode/tasks.md)
- [Phase 4 デプロイ・運用スクリプト](phase4-deploy/tasks.md)
- [Phase 5 デモシナリオ](phase5-demo/tasks.md)
- [Phase 6 ドキュメント](phase6-docs/tasks.md)
- [Phase 7 受け入れ確認](phase7-accept/tasks.md)

## 横断

- [テスト戦略（L1/L2/L3）](test-strategy.md)

## Phase 運用プロトコル（Phase 2/3 で確立）

### 開始
- `/phase-start <N>` スラッシュコマンド
  - CLAUDE.md / spec.md / phase<N>-*/tasks.md / fabric-pitfalls.md / test-strategy.md を読込
  - `git log` + 最新 tag で前 Phase 完了確認
  - サブタスク登録（TaskCreate）
  - ユーザー承認取得後に着手

### 実装サイクル
1. **タスク単位で in_progress → completed** に更新
2. **決定性制約**（Date.now / Math.random / env 禁止）を chaincode では常時意識
3. **テスト先行**（L1 主戦場、`chaincode/product-trace/test/`、`npm test` 全緑が Phase 3 完了条件）
4. **bash スクリプト**は `set -euo pipefail` + 冪等性必須
5. コミット単位は小さく、Conventional Commits

### エラー規約（Phase 3 確立）
- chaincode エラーは `ChaincodeError(code, message)` で `[CODE] message` 形式に整形
- L2/demo スクリプトは `grep '\[OWNER_MISMATCH\]'` のように **エラーコード grep**
- 詳細: `docs/fabric-pitfalls.md#chaincode エラーは message 本文しか伝搬しない`

### state 拡張パターン（Phase 3 確立）
- GetHistoryForKey から取れるのは state スナップショット列のみ
- 呼出者情報を履歴に残したい場合は **state 本体に `lastActor: {mspId, id}` 埋め込み**
- 詳細: `docs/fabric-pitfalls.md#GetHistoryForKey は state 変遷のスナップショット列`

### Phase 完了プロトコル
1. L1/L2 テスト全緑確認
2. `/phase-review <N>` で対応エージェント並列発火
3. 指摘を優先度付きで整理 → ユーザー確認 → 反映
4. 反映後 `commit` + `git tag phase<N>-done` + `git push origin main --tags`

### レビューエージェント発火の注意
- `.claude/agents/<name>.md` に定義したプロジェクト agent は `subagent_type` に
  直接指定できない（`general-purpose` + エージェント定義ファイル読込指示で代替）
- `/phase-review` スラッシュコマンドが正しい発火パターンを内包している

### ナレッジ運用
- 実装中に踏んだ罠は **同じ Phase 内で** `docs/fabric-pitfalls.md` に追記
- 後続 Phase に影響するものは `docs/tasks/phase<後>-*/tasks.md` の冒頭に「申し送り節」を追加
- ナレッジ反映も同 Phase のコミットに含める（別 PR に分けない）
