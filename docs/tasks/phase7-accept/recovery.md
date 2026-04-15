# Phase 7 T7-3 リカバリ保険手順書

デモ当日 Fabric が起動しない / chaincode install が壊れる等の緊急時用の保険。
T7-2 リハーサル後、クリーン状態で一度だけ実施し、成果物を `docs/tasks/phase7-accept/assets/` に保存する。

---

## 保険ポートフォリオ

1. **録画ログ** — CLI 実行の全文テキスト + 時系列。当日再生してデモ代替
2. **静止画（テキストキャプチャ）** — 3 枚の決定的シーンを個別テキスト保存
3. **フォールバック判断フロー** — 起動失敗時の戻し戦略

---

## 事前準備

```bash
cd /home/hatanotakuma/works/hl-proto
mkdir -p docs/tasks/phase7-accept/assets
./scripts/reset.sh --yes
./scripts/network_up.sh
./scripts/deploy_chaincode.sh
```

---

## 1. 録画ログ取得（`script` コマンド）

`script` は bash 標準で ttyrec 相当。asciinema でも代替可だが OS 依存なので
`script` を第一選択にする。

```bash
TS=$(date +%Y%m%d-%H%M%S)
ASSET_DIR=docs/tasks/phase7-accept/assets

# 1-1 正常系
script -q -c './scripts/demo_normal.sh' "${ASSET_DIR}/demo_normal-${TS}.log"

# 1-2 C 視点クライマックス
script -q -c './scripts/demo_verify_as_c.sh' "${ASSET_DIR}/demo_verify_as_c-${TS}.log"

# 1-3 異常系
script -q -c './scripts/demo_error.sh' "${ASSET_DIR}/demo_error-${TS}.log"
```

### 確認

- 各ログの末尾に `Script done` 行があること
- ANSI エスケープ (`\033[...`) が含まれていても `cat` で色付き再生可能
- サイズ: 50〜200KB 程度が目安。巨大ならどこかで無限ループしている可能性

### 再生（本番時）

```bash
cat docs/tasks/phase7-accept/assets/demo_normal-<TS>.log
```

プロジェクタで `cat` を直接見せてもよいし、`less -R` で色保持しながら pager しても
よい。

### （任意）asciinema

```bash
# 事前インストール: sudo apt-get install -y asciinema
asciinema rec docs/tasks/phase7-accept/assets/demo_normal-${TS}.cast \
  -c './scripts/demo_normal.sh'
# 再生:
asciinema play docs/tasks/phase7-accept/assets/demo_normal-${TS}.cast
```

asciinema は時間軸も再現するので「当日ナレーションと合わせやすい」利点あり。

---

## 2. テキストキャプチャ 3 枚（スクショ代替）

Claude で GUI スクショは取れないので、**特定シーンの出力だけを切り出したテキストファイル** を保険とする。

### 2-1 N4 GetHistory 一覧

```bash
# 直近の productId を拾う（demo_normal.sh が書いた）
PID=$(cat .last_product_id)
./scripts/invoke_as.sh org3 query GetHistory "${PID}" 2>/dev/null \
  | tee docs/tasks/phase7-accept/assets/capture-n4-history.txt
```

期待: 3 イベント (CREATE / TRANSFER / TRANSFER)。ファイルに `mspId` `txId` `timestamp` が並ぶこと。

### 2-2 C 視点クライマックス「#1 by メーカー A」

`demo_verify_as_c.sh` の出力全体を取るが、特に重要なのは整形層が出力する
`#1 CREATE by メーカー A (Org1MSP)` 行。`script` ログから grep で切り出す:

```bash
grep -E '#1 CREATE|by メーカー A|起点' \
  docs/tasks/phase7-accept/assets/demo_verify_as_c-*.log \
  | tee docs/tasks/phase7-accept/assets/capture-climax.txt
```

このテキストが保険の **クライマックス** となる。1 行でも「起点 = メーカー A」と
読める行が取れていれば合格。

### 2-3 E1 `[OWNER_MISMATCH]` エラー表示

```bash
PID=$(cat .last_product_id)
./scripts/invoke_as.sh org3 invoke TransferProduct "${PID}" Org2MSP Org3MSP \
  2>&1 | tee docs/tasks/phase7-accept/assets/capture-e1-error.txt || true
```

期待: `[OWNER_MISMATCH] fromOwner does not match currentOwner: from=Org2MSP, current=Org3MSP`
（README §異常系 の期待結果と同一）。

---

## 3. フォールバック判断フロー

当日起動失敗時、どこまで戻すか迷わないための決定木。

```
症状                                          → 戻し先                    → 代替
─────────────────────────────────────────────────────────────────────────────
peer コンテナが exit 137 / 起動せず          → reset → network_up 再実行 → assets のログ再生
chaincode install が broken pipe             → reset → deploy 再実行       → assets のログ再生
invoke が MVCC_READ_CONFLICT 連発             → 1 回 reset → 再デモ         → assets のログ再生
demo_normal.sh 途中で止まる                   → 手動版（README §手動版）   → assets のログ再生
docker daemon 応答せず                        → 復旧不能                   → assets のログ再生のみ
```

### 具体コマンド列

```bash
# Level 1: chaincode 層だけ戻す
./scripts/deploy_chaincode.sh

# Level 2: ネットワーク層から戻す（1 分以内に完了見込み）
./scripts/reset.sh --yes && ./scripts/network_up.sh && ./scripts/deploy_chaincode.sh

# Level 3: 時間切れ。assets ログで語り切る
cat docs/tasks/phase7-accept/assets/demo_normal-*.log
cat docs/tasks/phase7-accept/assets/demo_verify_as_c-*.log
cat docs/tasks/phase7-accept/assets/demo_error-*.log
```

### 判断基準

- 残り時間 > 3 分: Level 2 まで試す
- 残り時間 ≤ 3 分: 即 Level 3
- Docker daemon 自体が落ちている: 即 Level 3

---

## 実施後のアクション

以下をユーザー → Claude に報告:

```
script ログ取得: yes/no （NG なら理由）
capture-n4-history.txt 行数: <n>
capture-climax.txt 行数: <n>
capture-e1-error.txt 末尾行: <該当行>
assets/ 配下のファイル一覧: <ls 結果>
```

Claude 側 T7-4 で以下を確認:
- capture-e1-error.txt が README 期待結果と文字列一致しているか
- assets/ に全 3 本のログが保存されているか
- .gitignore で assets/*.log を除外するか（PII / 環境情報が混入していないか確認後判断）
