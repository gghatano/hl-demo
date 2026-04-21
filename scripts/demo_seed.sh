#!/usr/bin/env bash
# demo_seed.sh — サンプル素材を台帳に冪等投入
#
# Web UI デモ時の「手持ち素材一覧」が空になるのを防ぐため、
# 複数ロットが各組織に分散して保有されている現実的な在庫状態を作る。
#
# 投入結果 (最終状態):
#   S-A-001   高炉A 鋼板 10t SS400   CONSUMED (B で 3 分割済)
#   S-A-001-a 分割片 3t               CONSUMED (接合素材 → P-B-001)
#   S-A-001-b 分割片 3t               ACTIVE   建設D 直送済
#   S-A-001-c 分割片 4t               CONSUMED (接合素材 → P-B-002)
#   S-A-002   高炉A 鋼板 8t SS400    ACTIVE   高炉A 在庫 (未出荷)
#   S-X-001   電炉X 形鋼 2t SM490    CONSUMED (接合素材 → P-B-001)
#   S-X-002   電炉X 形鋼 3t SM520    ACTIVE   加工Y 在庫 (未加工)
#   S-X-003   電炉X 形鋼 0.8t SM490  CONSUMED (接合素材 → P-B-002)
#   P-B-001   接合: S-A-001-a+S-X-001 ACTIVE   建設D 納品済 (柱)
#   P-B-002   接合: S-A-001-c+S-X-003 ACTIVE   加工B 在庫 (梁)
#
# 再実行: 既存素材があれば skip するので冪等。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVOKE="${SCRIPT_DIR}/invoke_as.sh"

if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_SKIP=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_SKIP=""; C_DIM=""; C_OFF=""
fi
log()  { echo "${C_DIM}[seed]${C_OFF} $*"; }
ok()   { echo "${C_OK}[ ok ]${C_OFF} $*"; }
skip() { echo "${C_SKIP}[skip]${C_OFF} $*"; }

exists() {
  local pid="$1"
  "${INVOKE}" org1 query ReadProduct "${pid}" >/dev/null 2>&1
}

current_owner() {
  local pid="$1"
  "${INVOKE}" org1 query ReadProduct "${pid}" 2>/dev/null | jq -r '.currentOwner // ""'
}

current_status() {
  local pid="$1"
  "${INVOKE}" org1 query ReadProduct "${pid}" 2>/dev/null | jq -r '.status // ""'
}

seed_create() {
  local pid="$1" org="$2" msp="$3" meta="$4"
  if exists "${pid}"; then
    skip "Create ${pid}"
    return 0
  fi
  log "Create ${pid} by ${msp}"
  "${INVOKE}" "${org}" invoke CreateProduct "${pid}" "${msp}" "${msp}" "${meta}" "" "demo://mill/${pid}.pdf" >/dev/null 2>&1
  ok "${pid} 作成"
}

seed_transfer() {
  local pid="$1" from_org="$2" from_msp="$3" to_msp="$4"
  local cur
  cur="$(current_owner "${pid}")"
  if [[ "${cur}" == "${to_msp}" ]]; then
    skip "Transfer ${pid} → ${to_msp} (到達済)"
    return 0
  fi
  if [[ "${cur}" != "${from_msp}" ]]; then
    skip "Transfer ${pid} (currentOwner=${cur})"
    return 0
  fi
  log "Transfer ${pid} ${from_msp} → ${to_msp}"
  "${INVOKE}" "${from_org}" invoke TransferProduct "${pid}" "${from_msp}" "${to_msp}" >/dev/null 2>&1
  ok "${pid}: ${from_msp} → ${to_msp}"
}

seed_split() {
  local parent="$1" owner_org="$2" children_json="$3"
  local status
  status="$(current_status "${parent}")"
  if [[ "${status}" == "CONSUMED" ]]; then
    skip "Split ${parent} (CONSUMED)"
    return 0
  fi
  log "Split ${parent} → children (by ${owner_org})"
  "${INVOKE}" "${owner_org}" invoke SplitProduct "${parent}" "${children_json}" >/dev/null 2>&1
  ok "${parent} 分割完了"
}

seed_merge() {
  local parent_ids_json="$1" child_id="$2" owner_org="$3" meta="$4"
  if exists "${child_id}"; then
    skip "Merge → ${child_id}"
    return 0
  fi
  log "Merge ${parent_ids_json} → ${child_id}"
  local esc_meta="${meta//\"/\\\"}"
  local child_json='{"childId":"'"${child_id}"'","metadataJson":"'"${esc_meta}"'"}'
  "${INVOKE}" "${owner_org}" invoke MergeProducts "${parent_ids_json}" "${child_json}" >/dev/null 2>&1
  ok "${child_id} 接合完了"
}

# ====================================
# 投入シーケンス
# ====================================
echo
log "==== 鋼材サンプルデータ投入 ===="
echo

# 1. 高炉A が鋼板 2 種を製造
seed_create "S-A-001" org1 Org1MSP '{"category":"plate","grade":"SS400","weightKg":10000,"heatNo":"HT-A-001"}'
seed_create "S-A-002" org1 Org1MSP '{"category":"plate","grade":"SS400","weightKg":8000,"heatNo":"HT-A-002"}'

# 2. 電炉X が形鋼 3 種を製造
seed_create "S-X-001" org2 Org2MSP '{"category":"shape","grade":"SM490","weightKg":2000,"heatNo":"HT-X-001"}'
seed_create "S-X-002" org2 Org2MSP '{"category":"shape","grade":"SM520","weightKg":3000,"heatNo":"HT-X-002"}'
seed_create "S-X-003" org2 Org2MSP '{"category":"shape","grade":"SM490","weightKg":800,"heatNo":"HT-X-003"}'

# 3. 譲渡: A→B (S-A-001), X→B (S-X-001, S-X-003), X→Y (S-X-002)
seed_transfer "S-A-001" org1 Org1MSP Org3MSP
seed_transfer "S-X-001" org2 Org2MSP Org3MSP
seed_transfer "S-X-002" org2 Org2MSP Org4MSP
seed_transfer "S-X-003" org2 Org2MSP Org3MSP

# 4. B が S-A-001 を 3 分割 (JSON は単一行で渡す: 改行入りは ctor に入らない)
seed_split "S-A-001" org3 '[{"childId":"S-A-001-a","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\",\"note\":\"接合用\"}"},{"childId":"S-A-001-b","toOwner":"Org5MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\",\"note\":\"現場直送\"}"},{"childId":"S-A-001-c","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":4000,\"grade\":\"SS400\",\"note\":\"接合用\"}"}]'

# 5. B が S-A-001-a + S-X-001 を接合 → P-B-001 (柱材)
seed_merge '["S-A-001-a","S-X-001"]' "P-B-001" org3 '{"type":"welded","purpose":"柱","note":"SS400+SM490"}'

# 6. B→D: P-B-001 を建設D に納品
seed_transfer "P-B-001" org3 Org3MSP Org5MSP

# 7. B が S-A-001-c + S-X-003 を接合 → P-B-002 (梁材, B 社内在庫)
seed_merge '["S-A-001-c","S-X-003"]' "P-B-002" org3 '{"type":"welded","purpose":"梁","note":"SS400+SM490 小形"}'

echo
ok "サンプルデータ投入完了"
echo
echo "${C_DIM}確認コマンド:${C_OFF}"
echo "  ./scripts/invoke_as.sh org3 query ListProductsByOwner Org3MSP   # 加工B 手持ち (S-A-001 系と P-B-002)"
echo "  ./scripts/invoke_as.sh org4 query ListProductsByOwner Org4MSP   # 加工Y 手持ち (S-X-002)"
echo "  ./scripts/invoke_as.sh org5 query ListProductsByOwner Org5MSP   # 建設D 手持ち (S-A-001-b と P-B-001)"
echo "  ./scripts/invoke_as.sh org5 query GetLineage P-B-001            # P-B-001 系譜 (A と X 起点が見える)"
