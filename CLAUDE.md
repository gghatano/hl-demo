# CLAUDE.md — hl-proto 開発ガイド

Hyperledger Fabric サプライチェーン トレーサビリティ PoC。Claude Code 向け規約。

## プロジェクト概要
- 目的: A→B→C の製品譲渡履歴を Fabric 台帳に記録、C 視点で A 起点確認
- スコープ: ローカル Linux デモ、CLI ベース、3Org 構成
- 詳細仕様: `docs/spec.md`
- 開発タスク: `docs/tasks/README.md`
- テスト戦略: `docs/tasks/test-strategy.md`

## ディレクトリ構成
```
hl-proto/
  CLAUDE.md               # 本ファイル
  README.md               # ユーザー向け（Phase 6 で作成）
  docs/
    spec.md               # 仕様（凍結）
    tasks/                # phase 別タスク
    demo-scenarios.md     # Phase 6
    architecture.md       # Phase 6
    fabric-pitfalls.md    # Fabric 落とし穴集
  fabric/
    test-network-wrapper/
      patches/            # fabric-samples への差分
  chaincode/
    product-trace/
      index.js
      test/               # L1 単体テスト
  scripts/
    setup.sh network_up.sh reset.sh
    deploy_chaincode.sh invoke_as.sh
    demo_normal.sh demo_error.sh demo_verify_as_c.sh
  tests/
    integration/          # L2 結合テスト
  .claude/
    agents/               # レビュー専門エージェント
    commands/             # スラッシュコマンド
```

## 開発ルール

### Phase 進行
- Phase 単位で進める（`docs/tasks/phase*/tasks.md`）
- Phase 開始前 ユーザー承認必須
- Phase 完了時 `/phase-review <phase番号>` でレビュー依頼発火
- レビュー指摘は次 Phase 前に解消

### Chaincode 実装制約（Fabric 決定性）
- ❌ `Date.now()` / `Math.random()` / 環境変数 / 外部 HTTP
- ✅ `ctx.stub.getTxTimestamp()` → ISO8601 変換
- ✅ `ctx.clientIdentity.getMSPID()` / `getID()`
- ❌ state に `history` 配列 保持（GetHistoryForKey 一本化）
- エラーは `throw new Error(...)` → endorsement failure で伝搬
- 詳細: `docs/fabric-pitfalls.md`

### Endorsement Policy
- 3Org `OR` ポリシー明示必須:
  - `OR('OrgAMSP.peer','OrgBMSP.peer','OrgCMSP.peer')`
- invoke 時 `--peerAddresses` を endorsement policy に合致させる

### スクリプト規約
- bash 全て `set -euo pipefail`
- 冪等性必須（2回実行で壊れない）
- `--fresh` フラグで reset→up→deploy 連動可
- demo_* と test_integration.sh の責務分離:
  - demo_* = 人向け、ナレーション有、assert 無
  - test_integration.sh = 自動、assert 有、整形無

### コミット規約
- Conventional Commits:
  - `feat(chaincode): CreateProduct 実装`
  - `fix(scripts): reset.sh volume prune 漏れ`
  - `test(chaincode): CreateProduct 重複拒否ケース`
  - `docs(tasks): phase3 テスト戦略リンク追加`
- Phase 完了時 tag: `phase1-done` 等
- Co-Authored-By trailer 付与（Claude Code 規約）

### テスト
- L1 単体: `cd chaincode/product-trace && npm test`
- L2 結合: `./scripts/test_integration.sh`
- L3 受入: クリーン VM で README 完走
- Phase 3 完了条件 = L1 全緑
- Phase 5 完了条件 = L2 全緑

## レビューエージェント運用

3 専門エージェント（`.claude/agents/`）:
- `fabric-architect-reviewer` — Fabric 設計 / chaincode 正しさ
- `devops-reproducibility-reviewer` — 再現性 / 自動化
- `demo-storyteller-reviewer` — デモ訴求力

発火方法:
- `/phase-review <N>` — Phase N に対応するエージェントを並列起動
- 手動: Agent tool で `subagent_type` 指定

Phase とエージェントの対応:
| Phase | fabric | devops | demo |
|---|---|---|---|
| 1 環境 | — | ✓ | — |
| 2 ネットワーク | ✓ | ✓ | — |
| 3 Chaincode | ✓ | — | — |
| 4 デプロイ | ✓ | ✓ | — |
| 5 デモ | — | ✓ | ✓ |
| 6 ドキュメント | — | ✓ | ✓ |
| 7 受入 | ✓ | ✓ | ✓ |

## 原始人モード
セッション開始時 ユーザーが `/genshijin` 指定している。解除指示あるまで継続。コード / コミットメッセージ / PR は通常記述。

## 禁止事項
- `docs/spec.md` の無断変更（凍結）
- `--no-verify` コミット
- `docker system prune -af` 等 ユーザー確認なし破壊的操作
- 3Org 化を test-network へ直接手入れ（patches/ 経由必須）
- chaincode に非決定性 API 混入
