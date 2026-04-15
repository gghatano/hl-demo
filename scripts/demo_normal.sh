#!/usr/bin/env bash
# demo_normal.sh — Phase 5 T5-0 / T5-1
# A→B→C の正常フローを「人向け」に語るデモスクリプト
#
# - ナレーション付き (冒頭: 課題提起 / 登場人物紹介)
# - 生 JSON 直接表示は禁止。scripts/lib/format.sh の整形を通す
# - assert は無い（失敗検知は test_integration.sh）
# - --fresh で reset → up → deploy 連動
#
# Usage:
#   ./scripts/demo_normal.sh           # 現行ネットワークに対し実行
#   ./scripts/demo_normal.sh --fresh   # クリーン起動から

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export REPO_ROOT
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/format.sh"

FRESH=0
for arg in "$@"; do
  case "${arg}" in
    --fresh) FRESH=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown arg: ${arg}" >&2; exit 2 ;;
  esac
done

INVOKE="${SCRIPT_DIR}/invoke_as.sh"

PAUSE="${DEMO_PAUSE:-1.2}"
pause() { sleep "${PAUSE}" 2>/dev/null || true; }

# ---------- 冒頭ナレーション (T5-0) ----------
clear 2>/dev/null || true
cat <<'EOS'

================================================================
  Hyperledger Fabric サプライチェーン トレーサビリティ デモ
================================================================
EOS

say_narration "■ 課題"
say_note "偽装転売・中抜き・産地偽装 ──"
say_note "「誰が作り、誰を経由し、誰の手に渡ったか」を後から追えないと、"
say_note "被害が表面化した時には既に手遅れになる。"
pause

say_narration "■ 解決の型"
say_note "3 社それぞれの組織が持つ台帳に、譲渡イベントを多重記録する。"
say_note "単一の誰かが書き換えてもネットワーク全体の同意なしには成立しない。"
pause

say_narration "■ 登場人物"
say_note "  メーカー A (Org1MSP) … 製品を作る"
say_note "  卸 B     (Org2MSP) … メーカーから仕入れ、販売店に流す"
say_note "  販売店 C (Org3MSP) … 消費者に販売する。後で起点 A を検証する側"
pause

if ((FRESH)); then
  say_section "--fresh: ネットワーク再構築"
  "${SCRIPT_DIR}/reset.sh" --yes
  "${SCRIPT_DIR}/network_up.sh"
  "${SCRIPT_DIR}/deploy_chaincode.sh"
fi

PRODUCT_ID="${PRODUCT_ID:-DEMO-$(date +%s)-$$}"
say_note "今回の productId: ${PRODUCT_ID}"
pause

# ---------- N1 ----------
say_section "N1: メーカー A が新規製造を台帳に登録"
say_step "CreateProduct ${PRODUCT_ID} (manufacturer=Org1MSP, initialOwner=Org1MSP)"
say_note "=> A 自身が A を initialOwner として登録する。chaincode が MSP を検証"
"${INVOKE}" org1 invoke CreateProduct "${PRODUCT_ID}" Org1MSP Org1MSP >/dev/null 2>&1
pause

say_step "現在の台帳状態を A から照会"
"${INVOKE}" org1 query ReadProduct "${PRODUCT_ID}" 2>/dev/null | format_product
pause

# ---------- N2 ----------
say_section "N2: A から 卸 B に譲渡"
say_step "TransferProduct ${PRODUCT_ID} Org1MSP → Org2MSP (A の承認で実行)"
"${INVOKE}" org1 invoke TransferProduct "${PRODUCT_ID}" Org1MSP Org2MSP >/dev/null 2>&1
pause

# ---------- N3 ----------
say_section "N3: 卸 B から 販売店 C に譲渡"
say_step "TransferProduct ${PRODUCT_ID} Org2MSP → Org3MSP (B の承認で実行)"
"${INVOKE}" org2 invoke TransferProduct "${PRODUCT_ID}" Org2MSP Org3MSP >/dev/null 2>&1
pause

# ---------- フロー結果 ----------
say_section "履歴を A→B→C の順で表示"
"${INVOKE}" org3 query GetHistory "${PRODUCT_ID}" 2>/dev/null | format_history
pause

say_narration "■ ここまでが正常フロー"
say_note "次は異常系: ./scripts/demo_error.sh ${PRODUCT_ID}"
say_note "C の立場で起点 A を確認する決め場面: ./scripts/demo_verify_as_c.sh ${PRODUCT_ID}"

# 後続デモが引数省略で拾えるよう、直近の productId を置く
echo "${PRODUCT_ID}" > "${REPO_ROOT}/.last_product_id" 2>/dev/null || true

echo
say_narration "■ スコープと限界（経営層向け 30 秒）"
say_note "このデモが示すのは「台帳に載った情報は改ざんされない」こと。"
say_note "逆に言えば、台帳に載せる前の「モノ自体の真正性」── 現物のすり替えや"
say_note "偽タグ貼付 ── は別レイヤーの論点であり、QR/RFID/IoT との組み合わせで補う。"
say_note "本 PoC はあくまで 組織間で譲渡履歴を共有・検証 する部分を扱う。"
echo
