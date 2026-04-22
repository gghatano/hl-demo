#!/usr/bin/env bash
# demo_normal.sh — Phase 8: 複合シナリオ (3 部構成)
#
# 5Org (A/X/B/Y/D) の鋼材トレーサビリティ。以下の 3 パートで難易度を段階的に上げる。
#
#   Part 1: 基本シナリオ (2系統製造 → 分割 → 接合 → 納品)
#   Part 2: Merge-of-Merge (多段組立: Y 小組 → B 本体組 → 最終組立)
#   Part 3: Diamond DAG (祖先再マージで経路が 2 本になる)
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
say_note "  加工業者 B     (Org3MSP) … 切断・接合 (Part 1/2/3 を担当)"
say_note "  加工業者 Y     (Org4MSP) … 切断・接合 (Part 2 で小組ユニットを担当)"
say_note "  建設会社 D     (Org5MSP) … 最終納品先、系譜の検証者"
pause

say_narration "■ このデモの進め方"
say_note "  Part 1: 単純な分割+接合で起点メーカーを検証 (約 2 分)"
say_note "  Part 2: Y が小組を作り B が本体組を作り、最後に両者を接合 (Merge-of-Merge)"
say_note "  Part 3: 祖先再マージで Diamond DAG ができることを確認"
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

say_narration "============================================================"
say_narration "  Part 1: 基本シナリオ (2系統製造 → 分割 → 接合 → 納品)"
say_narration "============================================================"
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

# ============================================================
#  Part 2: Merge-of-Merge (多段組立)
# ============================================================
echo
say_narration "============================================================"
say_narration "  Part 2: Merge-of-Merge (多段組立)"
say_narration "============================================================"
say_note "実際の建材は「小組 → 本体組 → 最終組立」と段階的に接合される。"
say_note "親が前段 Merge の結果であるケース (Merge-of-Merge) を実演する。"
pause

# Part 2 で使う ID
S3="DEMO-S3-${STAMP}"
S3A="${S3}-a"
S3A1="${S3A}-1"
S3B="${S3}-b"
PY="DEMO-PY-${STAMP}"
S4="DEMO-S4-${STAMP}"
S4X="${S4}-x"
S4Y="${S4}-y"
PB="DEMO-PB-${STAMP}"
PF="DEMO-PF-${STAMP}"

say_note "Part 2 の productId:"
say_note "  形鋼 (Y 用)    S3 = ${S3}"
say_note "  鋼板 (B 用)    S4 = ${S4}"
say_note "  Y 小組         PY = ${PY}"
say_note "  B 本体組       PB = ${PB}"
say_note "  最終組立       PF = ${PF}"
pause

say_section "P2-1: 電炉X が形鋼 ${S3} を製造 → 加工Y へ譲渡"
S3_META='{"category":"shape","grade":"SM490","weightKg":2000,"heatNo":"HT-X02"}'
"${INVOKE}" org2 invoke CreateProduct "${S3}" Org2MSP Org2MSP "${S3_META}" "" "demo://millsheet/${S3}.pdf" >/dev/null 2>&1
"${INVOKE}" org2 invoke TransferProduct "${S3}" Org2MSP Org4MSP >/dev/null 2>&1
pause

say_section "P2-2: 加工Y が ${S3} を 2 分割 (1 階層目)"
CHILDREN_P2A='[{"childId":"'${S3A}'","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":1200,\"grade\":\"SM490\"}"},{"childId":"'${S3B}'","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":800,\"grade\":\"SM490\"}"}]'
"${INVOKE}" org4 invoke SplitProduct "${S3}" "${CHILDREN_P2A}" >/dev/null 2>&1
pause

say_section "P2-3: 加工Y が ${S3A} をさらに切り出し (2 階層目, DAG 3 階層)"
CHILDREN_P2B='[{"childId":"'${S3A1}'","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":500,\"grade\":\"SM490\"}"}]'
"${INVOKE}" org4 invoke SplitProduct "${S3A}" "${CHILDREN_P2B}" >/dev/null 2>&1
pause

say_section "P2-4: 加工Y が小組 ${PY} を接合 (${S3A1} + ${S3B})"
PARENTS_PY='["'${S3A1}'","'${S3B}'"]'
CHILD_PY='{"childId":"'${PY}'","metadataJson":"{\"type\":\"welded\",\"purpose\":\"Y 小組\"}"}'
"${INVOKE}" org4 invoke MergeProducts "${PARENTS_PY}" "${CHILD_PY}" >/dev/null 2>&1
pause

say_section "P2-5: 加工Y → 加工B に ${PY} を譲渡 (cross-fabricator)"
"${INVOKE}" org4 invoke TransferProduct "${PY}" Org4MSP Org3MSP >/dev/null 2>&1
pause

say_section "P2-6: 高炉A が ${S4} を製造 → 加工B へ譲渡"
S4_META='{"category":"plate","grade":"SS400","weightKg":8000,"heatNo":"HT-A02"}'
"${INVOKE}" org1 invoke CreateProduct "${S4}" Org1MSP Org1MSP "${S4_META}" "" "demo://millsheet/${S4}.pdf" >/dev/null 2>&1
"${INVOKE}" org1 invoke TransferProduct "${S4}" Org1MSP Org3MSP >/dev/null 2>&1
pause

say_section "P2-7: 加工B が ${S4} を 2 分割"
CHILDREN_P2C='[{"childId":"'${S4X}'","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\"}"},{"childId":"'${S4Y}'","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":5000,\"grade\":\"SS400\"}"}]'
"${INVOKE}" org3 invoke SplitProduct "${S4}" "${CHILDREN_P2C}" >/dev/null 2>&1
pause

say_section "P2-8: 加工B が本体 ${PB} を接合 (${S4X} + ${S4Y})"
PARENTS_PB='["'${S4X}'","'${S4Y}'"]'
CHILD_PB='{"childId":"'${PB}'","metadataJson":"{\"type\":\"welded\",\"purpose\":\"B 本体組\"}"}'
"${INVOKE}" org3 invoke MergeProducts "${PARENTS_PB}" "${CHILD_PB}" >/dev/null 2>&1
pause

say_section "P2-9: 加工B が最終組立 ${PF} を接合 (${PB} + ${PY}) ← Merge-of-Merge"
say_note "親 ${PB} (B 本体組) と ${PY} (Y 小組) はどちらも前段 Merge の結果。"
say_note "→ ${PF} から見ると祖先が 2 系統 (A→B 系, X→Y 系) の DAG になる。"
PARENTS_PF='["'${PB}'","'${PY}'"]'
CHILD_PF='{"childId":"'${PF}'","metadataJson":"{\"type\":\"welded\",\"purpose\":\"最終組立ユニット\"}"}'
"${INVOKE}" org3 invoke MergeProducts "${PARENTS_PF}" "${CHILD_PF}" >/dev/null 2>&1
pause

say_section "P2-10: 加工B → 建設D に ${PF} を納品"
"${INVOKE}" org3 invoke TransferProduct "${PF}" Org3MSP Org5MSP >/dev/null 2>&1
pause

say_section "P2-11: 建設D が ${PF} の系譜を検証 (多段 DAG)"
LINEAGE_PF="$("${INVOKE}" org5 query GetLineage "${PF}" 2>/dev/null)"
echo
say_note "── Nodes ─────────────────────"
printf '%s' "${LINEAGE_PF}" | jq -r '.nodes[] | "  \(.id)  manufacturer=\(.manufacturer)  owner=\(.currentOwner)  status=\(.status)"'
echo
say_note "── Edges (祖先→子孫方向) ─────"
printf '%s' "${LINEAGE_PF}" | jq -r '.edges[] | "  \(.from) ─\(.type)→ \(.to)"'
say_note "→ 起点は高炉A (${S4}) と電炉X (${S3}) の 2 系統。中間に PY/PB の Merge 結果が挟まる。"
pause

# ============================================================
#  Part 3: Diamond DAG (祖先再マージ)
# ============================================================
echo
say_narration "============================================================"
say_narration "  Part 3: Diamond DAG (祖先再マージ)"
say_narration "============================================================"
say_note "ある素材を切り出して、さらにその子から切り出したものを、元の素材に接合する。"
say_note "部分加工して戻す工程に相当。最終子から起点まで経路が 2 本できる (Diamond DAG)。"
pause

# Part 3 で使う ID
S5="DEMO-S5-${STAMP}"
S5P="${S5}-p"
S5P1="${S5P}-1"
PD="DEMO-PD-${STAMP}"

say_note "Part 3 の productId:"
say_note "  鋼板           S5    = ${S5}"
say_note "  切り出し片     S5P   = ${S5P}     (${S5} の子)"
say_note "  さらに切り出し S5P1  = ${S5P1}    (${S5P} の子)"
say_note "  Diamond 接合品 PD    = ${PD}      (${S5} + ${S5P1} の Merge)"
pause

say_section "P3-1: 高炉A が ${S5} を製造 → 加工B へ譲渡"
S5_META='{"category":"plate","grade":"SS400","weightKg":6000,"heatNo":"HT-A03"}'
"${INVOKE}" org1 invoke CreateProduct "${S5}" Org1MSP Org1MSP "${S5_META}" "" "demo://millsheet/${S5}.pdf" >/dev/null 2>&1
"${INVOKE}" org1 invoke TransferProduct "${S5}" Org1MSP Org3MSP >/dev/null 2>&1
pause

say_section "P3-2: 加工B が ${S5} から ${S5P} を切り出し (${S5} は ACTIVE 継続)"
CHILDREN_P3A='[{"childId":"'${S5P}'","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":2000,\"grade\":\"SS400\",\"note\":\"ブラケット用\"}"}]'
"${INVOKE}" org3 invoke SplitProduct "${S5}" "${CHILDREN_P3A}" >/dev/null 2>&1
pause

say_section "P3-3: 加工B が ${S5P} から ${S5P1} をさらに切り出し (孫階層)"
CHILDREN_P3B='[{"childId":"'${S5P1}'","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":1000,\"grade\":\"SS400\",\"note\":\"補強材\"}"}]'
"${INVOKE}" org3 invoke SplitProduct "${S5P}" "${CHILDREN_P3B}" >/dev/null 2>&1
pause

say_section "P3-4: 加工B が ${S5} + ${S5P1} を接合 → ${PD} (祖先再マージ)"
say_note "${PD} の直接の親は [${S5}, ${S5P1}]。"
say_note "加えて ${S5P1} → ${S5P} → ${S5} の経路でも ${S5} に到達する。"
say_note "→ ${S5} への入エッジが 2 本ある Diamond DAG になる。"
PARENTS_PD='["'${S5}'","'${S5P1}'"]'
CHILD_PD='{"childId":"'${PD}'","metadataJson":"{\"type\":\"welded\",\"purpose\":\"祖先再マージ実証\"}"}'
"${INVOKE}" org3 invoke MergeProducts "${PARENTS_PD}" "${CHILD_PD}" >/dev/null 2>&1
pause

say_section "P3-5: ${PD} の GetLineage (Diamond DAG 確認)"
LINEAGE_PD="$("${INVOKE}" org3 query GetLineage "${PD}" 2>/dev/null)"
echo
say_note "── Nodes ─────────────────────"
printf '%s' "${LINEAGE_PD}" | jq -r '.nodes[] | "  \(.id)  manufacturer=\(.manufacturer)  owner=\(.currentOwner)  status=\(.status)"'
echo
say_note "── Edges (祖先→子孫方向) ─────"
printf '%s' "${LINEAGE_PD}" | jq -r '.edges[] | "  \(.from) ─\(.type)→ \(.to)"'
say_note "→ ${S5} → ${PD} (直接) と ${S5} → ${S5P} → ${S5P1} → ${PD} (間接) の 2 経路が出ている。"
say_note "  循環は無く DAG として整合。chaincode は祖先再マージを構造的に許容する設計。"
pause

echo
say_narration "■ このデモで確認できたこと"
say_note "  1. 2 系統メーカー (A/X) の鋼材が台帳に並立して登録される"
say_note "  2. 分割・接合の各操作で親子関係 (parents/children) が自動記録される"
say_note "  3. 建設会社 D から一覧で起点 (高炉 A / 電炉 X) までたどれる"
say_note "  4. Merge-of-Merge (前段接合の結果をさらに接合) も正しく DAG に表現される"
say_note "  5. 祖先再マージ (Diamond DAG) でも循環は発生せず、経路が 2 本として現れる"
say_note "  6. 親の状態遷移 (ACTIVE/CONSUMED) と所有者検査で不正操作は拒否される"
echo
say_narration "■ スコープと限界"
say_note "台帳は「記録の一貫性」を保証する。物理鋼材そのものの真正性 (QR/RFID 等) は別レイヤー。"
say_note "重量保存則 (分割後 Σ子重量 = 親重量) は PoC スコープ外 - 実装上は検証していない。"
say_note "GetLineage の深さは LINEAGE_MAX_DEPTH=20 で打ち切る (深い多段加工では要見直し)。"
echo
