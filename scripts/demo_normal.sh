#!/usr/bin/env bash
# demo_normal.sh — Phase 8: 複合シナリオ (2系統製造 → 分割 → 接合 → 納品)
#
# 5Org (A/X/B/Y/D) の鋼材トレーサビリティ。鋼板 S1 を切断して接合素材を作り、
# 形鋼 S2 と接合して部材 P1 を建設会社 D に納品するフロー。
#
# - ナレーション付き (課題提起 → 登場人物紹介)
# - assert 無し (失敗検知は test_integration.sh)
# - --fresh で reset → up → deploy 連動
#
# Usage:
#   ./scripts/demo_normal.sh           # 現行ネットワーク
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

# json_arg: JSON 文字列を peer CLI に安全に渡すため shell クォート含みで出力
# (invoke_as.sh は bash 配列で引数を受け取るので、このスクリプトでは直接配列に入れる)

clear 2>/dev/null || true
cat <<'EOS'

================================================================
  hl-proto v2 — 鋼材トレーサビリティ デモ (5Org 複合シナリオ)
================================================================
EOS

say_narration "■ 課題"
say_note "鋼材は 1 本まるごと納品されることは稀で、加工業者が切断・接合して多段で流通する。"
say_note "建設現場で使われる部材について「どのメーカーのどの鋼材から作られたか」を"
say_note "遡れないと、品質問題が発覚したときに責任の所在と対象ロットが特定できない。"
pause

say_narration "■ 解決の型"
say_note "5 組織が台帳を共有し、譲渡だけでなく「分割 (1→N)」「接合 (N→1)」も記録する。"
say_note "各部材は parents/children で親子関係を持ち、任意の productId から"
say_note "祖先方向の DAG をたどれる。"
pause

say_narration "■ 登場人物"
say_note "  高炉メーカー A (Org1MSP) … 鋼板を製造"
say_note "  電炉メーカー X (Org2MSP) … 形鋼を製造"
say_note "  加工業者 B     (Org3MSP) … 切断・接合"
say_note "  加工業者 Y     (Org4MSP) … 切断・接合 (このデモでは登場のみ)"
say_note "  建設会社 D     (Org5MSP) … 最終納品先、系譜の検証者"
pause

if ((FRESH)); then
  say_section "--fresh: ネットワーク再構築 (5Org)"
  "${SCRIPT_DIR}/reset.sh" --yes
  "${SCRIPT_DIR}/network_up.sh"
  "${SCRIPT_DIR}/deploy_chaincode.sh"
fi

STAMP="$(date +%s)"
S1="DEMO-S1-${STAMP}"
S2="DEMO-S2-${STAMP}"
S1A="${S1}-a"
S1B="${S1}-b"
S1C="${S1}-c"
P1="DEMO-P1-${STAMP}"

say_note "今回の productId:"
say_note "  鋼板      S1 = ${S1}"
say_note "  形鋼      S2 = ${S2}"
say_note "  接合部材  P1 = ${P1}"
pause

# ---------- N1: 高炉メーカー A が鋼板 S1 を製造 ----------
say_section "N1: 高炉メーカー A が鋼板 ${S1} を製造"
say_step "CreateProduct ${S1} (Org1MSP, metadata=鋼板 10t SS400)"
S1_META='{"category":"plate","grade":"SS400","weightKg":10000,"heatNo":"HT-A01"}'
"${INVOKE}" org1 invoke CreateProduct "${S1}" Org1MSP Org1MSP "${S1_META}" "" "demo://millsheet/${S1}.pdf" >/dev/null 2>&1
pause

# ---------- N2: 電炉メーカー X が形鋼 S2 を製造 ----------
say_section "N2: 電炉メーカー X が形鋼 ${S2} を製造"
say_step "CreateProduct ${S2} (Org2MSP, metadata=形鋼 2t SM490)"
S2_META='{"category":"shape","grade":"SM490","weightKg":2000,"heatNo":"HT-X01"}'
"${INVOKE}" org2 invoke CreateProduct "${S2}" Org2MSP Org2MSP "${S2_META}" "" "demo://millsheet/${S2}.pdf" >/dev/null 2>&1
pause

# ---------- 加工業者 B へ集約 ----------
say_section "加工業者 B (Org3MSP) に両素材を集約"
say_step "TransferProduct ${S1} Org1MSP → Org3MSP"
"${INVOKE}" org1 invoke TransferProduct "${S1}" Org1MSP Org3MSP >/dev/null 2>&1
say_step "TransferProduct ${S2} Org2MSP → Org3MSP"
"${INVOKE}" org2 invoke TransferProduct "${S2}" Org2MSP Org3MSP >/dev/null 2>&1
pause

# ---------- 分割 ----------
say_section "N5: 加工業者 B が ${S1} を切断 (分割)"
say_note "鋼板 ${S1} を 3 枚に切断 → ${S1A} (3t, B保有) / ${S1B} (3t, D直送) / ${S1C} (4t, B保有)"
CHILDREN_JSON='[{"childId":"'${S1A}'","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\"}"},{"childId":"'${S1B}'","toOwner":"Org5MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\"}"},{"childId":"'${S1C}'","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":4000,\"grade\":\"SS400\"}"}]'
"${INVOKE}" org3 invoke SplitProduct "${S1}" "${CHILDREN_JSON}" >/dev/null 2>&1
pause

say_step "親 ${S1} の状態 (CONSUMED 遷移確認)"
"${INVOKE}" org3 query ReadProduct "${S1}" 2>/dev/null | format_product
pause

# ---------- 接合 ----------
say_section "N6: 加工業者 B が ${S1A} と ${S2} を溶接 (接合)"
say_note "分割片 ${S1A} + 形鋼 ${S2} → 部材 ${P1} (B保有)"
PARENTS_JSON='["'${S1A}'","'${S2}'"]'
CHILD_JSON='{"childId":"'${P1}'","metadataJson":"{\"type\":\"welded\",\"purpose\":\"柱\"}"}'
"${INVOKE}" org3 invoke MergeProducts "${PARENTS_JSON}" "${CHILD_JSON}" >/dev/null 2>&1
pause

# ---------- 納品 ----------
say_section "N3': 加工業者 B が接合部材 ${P1} を建設会社 D に納品"
"${INVOKE}" org3 invoke TransferProduct "${P1}" Org3MSP Org5MSP >/dev/null 2>&1
pause

# ---------- D 視点の検証 ----------
say_section "N7: 建設会社 D が ${P1} の系譜を検証 (GetLineage)"
say_step "GetLineage ${P1} (祖先 DAG を BFS で収集)"
LINEAGE_JSON="$("${INVOKE}" org5 query GetLineage "${P1}" 2>/dev/null)"
echo
say_note "── Nodes ─────────────────────"
printf '%s' "${LINEAGE_JSON}" | jq -r '.nodes[] | "  \(.id)  manufacturer=\(.manufacturer)  owner=\(.currentOwner)  status=\(.status)"'
echo
say_note "── Edges (祖先→子孫方向) ─────"
printf '%s' "${LINEAGE_JSON}" | jq -r '.edges[] | "  \(.from) ─\(.type)→ \(.to)"'
pause

say_section "${P1} の履歴 (eventType ベース)"
"${INVOKE}" org5 query GetHistory "${P1}" 2>/dev/null | format_history
pause

# 後続デモ用
echo "${P1}" > "${REPO_ROOT}/.last_product_id" 2>/dev/null || true

echo
say_narration "■ このデモで確認できたこと"
say_note "  1. 2 系統メーカー (A/X) の鋼材が台帳に並立して登録される"
say_note "  2. 分割・接合の各操作で親子関係 (parents/children) が自動記録される"
say_note "  3. 建設会社 D から一覧で起点 (高炉 A / 電炉 X) までたどれる"
say_note "  4. 親は CONSUMED になり、二重分割や二重接合は chaincode が拒否する"
echo
say_narration "■ スコープと限界"
say_note "台帳は「記録の一貫性」を保証する。物理鋼材そのものの真正性 (QR/RFID 等) は別レイヤー。"
say_note "重量保存則 (分割後 Σ子重量 = 親重量) は PoC スコープ外 - 実装上は検証していない。"
echo
