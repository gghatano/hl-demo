# CLAUDE.md — hl-proto 開発ガイド

Hyperledger Fabric サプライチェーン トレーサビリティ PoC。Claude Code 向け規約。

## プロジェクト概要
- 目的 (v1): A→B→C の製品譲渡履歴を Fabric 台帳に記録、C 視点で A 起点確認
- 目的 (v2 / Phase 8): 鋼材の分割 (1→N) / 接合 (N→1) を扱う 5Org 構成。建設 D が系譜 DAG で起点メーカーを検証
- スコープ: ローカル Linux (WSL2) / macOS (Colima) デモ、CLI + Web UI
- 詳細仕様: **`docs/spec-v2.md` (現行)** / `docs/spec.md` (v1 凍結)
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
- Phase 開始時 `/phase-start <phase番号>` でコンテキスト読込 + サブタスク登録 + ユーザー承認
- Phase 完了時 `/phase-review <phase番号>` でレビュー依頼発火
- レビュー指摘は次 Phase 前に解消
- 運用プロトコル詳細: `docs/tasks/README.md#Phase 運用プロトコル`

### Chaincode 実装制約（Fabric 決定性）
- ❌ `Date.now()` / `Math.random()` / 環境変数 / 外部 HTTP
- ✅ `ctx.stub.getTxTimestamp()` → ISO8601 変換
- ✅ `ctx.clientIdentity.getMSPID()` / `getID()`
- ❌ state に `history` 配列 保持（GetHistoryForKey 一本化）
- エラーは `throw new Error(...)` → endorsement failure で伝搬
- 詳細: `docs/fabric-pitfalls.md`

### Endorsement Policy (v2)
- 5Org `OR` ポリシー明示必須:
  - `OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer','Org4MSP.peer','Org5MSP.peer')`
- invoke 時 `--peerAddresses` を endorsement policy に合致させる (2 peer 以上)
- v1 時代は 3Org OR。v2 以降は 5Org OR。

### MSP ID の扱い
- 内部 MSP ID は fabric-samples 標準の `Org1MSP`〜`Org5MSP`
- 業務語彙への変換は `scripts/lib/format.sh` の `msp_to_role` + Web UI の MSP_LABELS
- 対応関係 (v2):
  - `Org1MSP` = 高炉メーカー A (CreateProduct 権限)
  - `Org2MSP` = 電炉メーカー X (CreateProduct 権限)
  - `Org3MSP` = 加工業者 B    (Split/Merge)
  - `Org4MSP` = 加工業者 Y    (Split/Merge)
  - `Org5MSP` = 建設会社 D

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
- `docs/spec.md` (v1) / `docs/spec-v2.md` (v2) の無断変更 (両方凍結。変更は Issue 経由)
- `--no-verify` コミット
- `docker system prune -af` 等 ユーザー確認なし破壊的操作
- test-network への直接手入れ (3Org は fabric-samples 付属、4/5Org は patches/ 経由必須)
- chaincode に非決定性 API 混入 (Date.now(), Math.random(), process.env, 外部 HTTP)
- parents/children 配列を非ソート状態で保存 (v2: normalizeIds() 必須)
