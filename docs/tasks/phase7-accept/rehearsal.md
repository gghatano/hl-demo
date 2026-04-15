# Phase 7 T7-2 リハーサル手順書

デモ所要時間を実測し、README / demo-scenarios の暫定「5〜7 分」を校正する。
実行者: デモ担当（ユーザー）。Claude は実施しない（環境差を避けるため）。

---

## 目的

1. クリーンなネットワーク状態から `demo_normal.sh` → `demo_verify_as_c.sh` → `demo_error.sh` を通しで走らせる
2. 各シーンの経過時間を計測する
3. `DEMO_PAUSE` を調整し、「人間が読めるテンポ」と「5〜10 分」の両方を満たす値を決める
4. 結果を Claude に報告 → README / demo-scenarios / このファイルに反映

---

## 事前準備

```bash
cd /home/hatanotakuma/works/hl-proto

# 1. クリーン状態を作る
./scripts/reset.sh --yes
./scripts/network_up.sh
./scripts/deploy_chaincode.sh

# 2. DEMO_PAUSE の初期値を決める（README/demo-scenarios は未指定 = デフォルト）
#    say_section 後の間を秒単位で制御する環境変数
#    推奨レンジ: 1.5（サクサク）〜 3.0（ゆっくり解説付き）
export DEMO_PAUSE=2.0
```

> `DEMO_PAUSE` は各 `demo_*.sh` で `pause() { sleep "${DEMO_PAUSE:-X}"; }` として実装済み。
> デフォルトは `demo_normal.sh=1.2 / demo_error.sh=1.2 / demo_verify_as_c.sh=1.5`。
> pause はキー入力待ちではなく sleep なので `time` コマンドで正確に計測できる。

---

## 計測手順

計測は `time` ではなく **壁時計タイムスタンプ** で行う。理由: スクリプト内で `pause` がキー入力待ちになる場合があるため、`time` では実時間にならない。

### 方式 A: `script` で全録画しつつタイムスタンプ

```bash
# ログファイル
TS=$(date +%Y%m%d-%H%M%S)
LOG=docs/tasks/phase7-accept/rehearsal-${TS}.log

# script は -t でタイミング別ファイル、-f で flush 毎書き
script -q -t 2>${LOG}.timing -c '
  echo "===== START $(date -Iseconds) ====="
  echo "--- demo_normal.sh ---"
  date +%s.%N
  ./scripts/demo_normal.sh
  date +%s.%N
  echo "--- demo_verify_as_c.sh ---"
  date +%s.%N
  ./scripts/demo_verify_as_c.sh
  date +%s.%N
  echo "--- demo_error.sh ---"
  date +%s.%N
  ./scripts/demo_error.sh
  date +%s.%N
  echo "===== END $(date -Iseconds) ====="
' "${LOG}"
```

終了後、`${LOG}` に 3 本の (start, end) ペアが入っている。各差分が各シナリオの所要時間。

### 方式 B: 簡易（time を 3 回、推奨）

`pause` は sleep ベースなので `time` で正確:

```bash
{ time ./scripts/demo_normal.sh      ; } 2>&1 | tee -a rehearsal.log
{ time ./scripts/demo_verify_as_c.sh ; } 2>&1 | tee -a rehearsal.log
{ time ./scripts/demo_error.sh       ; } 2>&1 | tee -a rehearsal.log
```

---

## 計測対象シーン（spec §9 / demo-scenarios 準拠）

| # | シーン | スクリプト | 目標秒 | 実測秒 | メモ |
|---|---|---|---|---|---|
| N1 | CreateProduct | demo_normal.sh | 20 | — | A が productId 登録 |
| N2 | TransferProduct A→B | demo_normal.sh | 20 | — | |
| N3 | TransferProduct B→C | demo_normal.sh | 20 | — | |
| N4 | GetHistory | demo_normal.sh | 30 | — | 履歴 3 行可視化 |
| V1 | C 視点検証クライマックス | demo_verify_as_c.sh | 60 | — | 山場。余裕を持たせる |
| E1 | OWNER_MISMATCH | demo_error.sh | 40 | — | 狙い: `[OWNER_MISMATCH]` 可視化 |
| E2 | PRODUCT_NOT_FOUND | demo_error.sh | 25 | — | |
| E3 | PRODUCT_ALREADY_EXISTS | demo_error.sh | 25 | — | |
| — | 合計目標 | | **240 (=4:00)** | — | ナレーション込みで 5〜7 分 |

実測を本表に記入 → Claude に `rehearsal-YYYYMMDD.md` ごと添付 or 転記して報告。

---

## 合否判定

- ✅ 合格: 合計 5:00 〜 7:00 に収まる
- 🟡 調整: 4:30 未満 or 7:30 超 → `DEMO_PAUSE` を変更して再計測
- 🔴 再設計: `DEMO_PAUSE` 調整だけでは収まらない / 山場 V1 で表示が流れすぎる

---

## 実施後のアクション

計測結果を Claude に以下の形式で報告する:

```
DEMO_PAUSE=<value>
demo_normal.sh: <秒>
demo_verify_as_c.sh: <秒>
demo_error.sh: <秒>
合計: <秒> (<m:ss>)
所感: <テンポ / 読みやすさ / その他>
```

Claude 側で T7-4 として:
- README §デモ実行手順 の「実測 5〜7 分」を実測値へ更新
- demo-scenarios.md の各シーン目標時間を実測値で上書き
- 必要なら各 `demo_*.sh` の `DEMO_PAUSE` デフォルト値を pin
