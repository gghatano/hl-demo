#!/usr/bin/env bash
# demo_seed.sh — サンプル素材を台帳に冪等投入
#
# Web UI デモ時の「手持ち素材一覧」が空になるのを防ぐため、
# 複数ロットが各組織に分散して保有されている現実的な在庫状態を作る。
#
# 投入結果 (最終状態):
#   --- 基本シナリオ (単純な分割 + 接合) -----------------------------
#   S-A-001    高炉A 鋼板 10t SS400    ACTIVE   (3 片切り出し済、本体は加工B 在庫に残る)
#   S-A-001-a  切り出し片 3t           CONSUMED (接合素材 → P-B-001)
#   S-A-001-b  切り出し片 3t           ACTIVE   建設D 直送済
#   S-A-001-c  切り出し片 4t           CONSUMED (接合素材 → P-B-002)
#   S-A-002    高炉A 鋼板 8t SS400     ACTIVE   高炉A 在庫 (未出荷)
#   S-X-001    電炉X 形鋼 2t SM490     CONSUMED (接合素材 → P-B-001)
#   S-X-002    電炉X 形鋼 3t SM520     ACTIVE   加工Y 在庫 (未加工)
#   S-X-003    電炉X 形鋼 0.8t SM490   CONSUMED (接合素材 → P-B-002)
#   P-B-001    接合: S-A-001-a+S-X-001 ACTIVE   建設D 納品済 (柱)
#   P-B-002    接合: S-A-001-c+S-X-003 ACTIVE   加工B 在庫 (梁)
#
#   --- 複雑シナリオ 1-3 (多段切り出し + Merge-of-Merge + Cross-fab) --
#   加工Y 側で小組 → 加工B 側で本体組 → 両者を最終接合 → 建設D 納品
#     S-X-004      電炉X 形鋼 2t SM490       ACTIVE   (加工Y が 2 分割した後も残る)
#     S-X-004-a    切り出し片 1.2t           ACTIVE   (さらに 2 分割した後も残る)
#     S-X-004-a1   さらに切り出し 0.5t       CONSUMED (P-Y-001 素材)
#     S-X-004-a2   さらに切り出し 0.7t       ACTIVE   (加工Y 在庫)
#     S-X-004-b    切り出し片 0.8t           CONSUMED (P-Y-001 素材)
#     P-Y-001      Y 内製小組 (a1+b)          CONSUMED (P-B-020 素材, B へ譲渡済み)
#     S-A-003      高炉A 鋼板 8t SS400       ACTIVE   (加工B で 2 分割後も残る)
#     S-A-003-x    切り出し片 3t             CONSUMED (P-B-010 素材)
#     S-A-003-y    切り出し片 5t             CONSUMED (P-B-010 素材)
#     P-B-010      B 内製本体組 (x+y)         CONSUMED (P-B-020 素材)
#     P-B-020      最終組立 (P-B-010+P-Y-001) ACTIVE   建設D 納品済
#
#   --- 複雑シナリオ 4 (Diamond DAG: 祖先再マージ) --------------------
#     S-A-005      高炉A 鋼板 6t SS400       CONSUMED (P-B-040 素材, 直接親)
#     S-A-005-p    切り出し片 2t             ACTIVE   (加工B 在庫)
#     S-A-005-p1   さらに切り出し 1t         CONSUMED (P-B-040 素材, 孫経由で S-A-005 に到達)
#     P-B-040      祖先再マージ実証 (S-A-005 + S-A-005-p1) ACTIVE   (加工B 在庫)
#
#   --- 業務リアリティ向上: メーカー在庫 + 仕掛中案件 ----------------
#   高炉A 未出荷在庫 (手持ち 5 ロット: S-A-002 含む):
#     S-A-006  SM490 15t   大型梁材向け     ACTIVE   高炉A 保有
#     S-A-007  SM520 12t   橋梁用高強度     ACTIVE   高炉A 保有
#     S-A-008  SS400 10t   柱材向け標準品   ACTIVE   高炉A 保有
#     S-A-009  SS400 5t    補修用小ロット   ACTIVE   高炉A 保有
#
#   電炉X 未出荷在庫 (手持ち 5 ロット):
#     S-X-005  H形鋼 SM490 5t  汎用梁材     ACTIVE   電炉X 保有
#     S-X-006  H形鋼 SM520 8t  大型梁材     ACTIVE   電炉X 保有
#     S-X-007  アングル SS400 2t           ACTIVE   電炉X 保有
#     S-X-008  チャンネル SM490 3t          ACTIVE   電炉X 保有
#     S-X-009  鉄筋 SD345 4t                ACTIVE   電炉X 保有
#
#   加工B 仕掛中 (受入→分割、接合待ち):
#     S-A-010    A→B 譲渡済 6t SS400       ACTIVE   (親、2 分割済みで ACTIVE 継続)
#     S-A-010-a  切り出し 3t 接合待ち       ACTIVE   加工B 保有
#     S-A-010-b  切り出し 3t 接合待ち       ACTIVE   加工B 保有
#
#   加工Y 仕掛中 (受入→分割、接合待ち):
#     S-X-010    X→Y 譲渡済 4t アングル    ACTIVE   (親、2 分割済み)
#     S-X-010-a  切り出し 2t 接合待ち       ACTIVE   加工Y 保有
#     S-X-010-b  切り出し 2t 接合待ち       ACTIVE   加工Y 保有
#
#   建設D 別工区納品 (素材直送):
#     S-X-011    鉄筋 SD390 3t              ACTIVE   (X→Y→D の通し納品)
#
# v1.3 以降の「切り出し」モデル: 親は CONSUMED にならず ACTIVE のまま残る。
# 親の children[] に切り出した子 ID が cumulative に記録される。
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
    skip "Carve ${parent} (CONSUMED)"
    return 0
  fi
  # 子 ID が既に全部存在していれば skip (冪等性)
  # 単純化: 最初の子 ID で判定
  local first_child
  first_child="$(printf '%s' "${children_json}" | jq -r '.[0].childId // ""')"
  if [[ -n "${first_child}" ]] && exists "${first_child}"; then
    skip "Carve ${parent} (先頭子 ${first_child} 既存)"
    return 0
  fi
  log "Carve ${parent} → children (by ${owner_org})"
  "${INVOKE}" "${owner_org}" invoke SplitProduct "${parent}" "${children_json}" >/dev/null 2>&1
  ok "${parent} 切り出し完了"
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

# ====================================
# 複雑シナリオ 1-3: 多段切り出し + Merge-of-Merge + Cross-fabricator
# ====================================
#
# フロー: 加工Y が小組 P-Y-001 を Y 内製 → B に譲渡 (cross-fab)
#        加工B が S-A-003 を分割→組立で本体 P-B-010 を作成
#        最後に P-B-010 + P-Y-001 を接合 → P-B-020 (Merge-of-Merge) → 建設D 納品

# 8. 電炉X が S-X-004 を製造 → 加工Y へ譲渡
seed_create "S-X-004" org2 Org2MSP '{"category":"shape","grade":"SM490","weightKg":2000,"heatNo":"HT-X-004"}'
seed_transfer "S-X-004" org2 Org2MSP Org4MSP

# 9. 加工Y が S-X-004 を 2 分割 (1 階層目)
seed_split "S-X-004" org4 '[{"childId":"S-X-004-a","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":1200,\"grade\":\"SM490\",\"note\":\"さらに分割予定\"}"},{"childId":"S-X-004-b","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":800,\"grade\":\"SM490\",\"note\":\"接合用\"}"}]'

# 10. 加工Y が S-X-004-a をさらに 2 分割 (2 階層目 → DAG 3 階層)
seed_split "S-X-004-a" org4 '[{"childId":"S-X-004-a1","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":500,\"grade\":\"SM490\",\"note\":\"接合用\"}"},{"childId":"S-X-004-a2","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":700,\"grade\":\"SM490\",\"note\":\"予備在庫\"}"}]'

# 11. 加工Y が S-X-004-a1 + S-X-004-b を接合 → P-Y-001 (Y 内製小組)
seed_merge '["S-X-004-a1","S-X-004-b"]' "P-Y-001" org4 '{"type":"welded","purpose":"小組ブラケット","note":"Y 内製"}'

# 12. Y→B: P-Y-001 を加工Bに送付 (cross-fabricator)
seed_transfer "P-Y-001" org4 Org4MSP Org3MSP

# 13. 高炉A が S-A-003 を製造 → 加工B へ譲渡
seed_create "S-A-003" org1 Org1MSP '{"category":"plate","grade":"SS400","weightKg":8000,"heatNo":"HT-A-003"}'
seed_transfer "S-A-003" org1 Org1MSP Org3MSP

# 14. 加工B が S-A-003 を 2 分割
seed_split "S-A-003" org3 '[{"childId":"S-A-003-x","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\",\"note\":\"本体ウェブ\"}"},{"childId":"S-A-003-y","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":5000,\"grade\":\"SS400\",\"note\":\"本体フランジ\"}"}]'

# 15. 加工B が x+y を接合 → P-B-010 (B 内製本体組)
seed_merge '["S-A-003-x","S-A-003-y"]' "P-B-010" org3 '{"type":"welded","purpose":"本体ウェブ+フランジ","note":"B 内製"}'

# 16. 加工B が P-B-010 + P-Y-001 を接合 → P-B-020 (Merge-of-Merge)
#     親の両方が「前段 Merge の結果」であり、DAG が 3 階層以上になる典型パターン。
seed_merge '["P-B-010","P-Y-001"]' "P-B-020" org3 '{"type":"welded","purpose":"最終組立ユニット","note":"本体+小組ブラケット"}'

# 17. B→D: P-B-020 を建設Dに納品
seed_transfer "P-B-020" org3 Org3MSP Org5MSP

# ====================================
# 複雑シナリオ 4: Diamond DAG (祖先再マージ)
# ====================================
#
# ある素材を一部切り出し、その子からさらに切り出したものを、元の素材に戻して接合する。
# 結果的に最終子 P-B-040 から起点 S-A-005 までの経路が 2 本できる (直接 / 孫経由)。

# 18. 高炉A が S-A-005 を製造 → 加工B へ譲渡
seed_create "S-A-005" org1 Org1MSP '{"category":"plate","grade":"SS400","weightKg":6000,"heatNo":"HT-A-005"}'
seed_transfer "S-A-005" org1 Org1MSP Org3MSP

# 19. 加工B が S-A-005 から S-A-005-p を切り出し (S-A-005 は ACTIVE のまま)
seed_split "S-A-005" org3 '[{"childId":"S-A-005-p","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":2000,\"grade\":\"SS400\",\"note\":\"ブラケット用途\"}"}]'

# 20. 加工B が S-A-005-p から S-A-005-p1 を切り出し (孫階層)
seed_split "S-A-005-p" org3 '[{"childId":"S-A-005-p1","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":1000,\"grade\":\"SS400\",\"note\":\"補強材\"}"}]'

# 21. 加工B が S-A-005 + S-A-005-p1 を接合 → P-B-040 (祖先再マージ)
#     P-B-040 の parents は [S-A-005, S-A-005-p1]。
#     さらに S-A-005-p1 → S-A-005-p → S-A-005 の経路でも祖先 S-A-005 に到達できる。
seed_merge '["S-A-005","S-A-005-p1"]' "P-B-040" org3 '{"type":"welded","purpose":"祖先再マージ実証","note":"S-A-005 由来を 2 経路で保持"}'

# ====================================
# 業務リアリティ向上: メーカー在庫 + 加工業者の仕掛中案件
# ====================================
#
# 各社の手持ち素材を現実に近づけるための追加投入。
# - 高炉A / 電炉X: 未出荷の在庫ロット (受注前 / 受注分 / 補修用の区別)
# - 加工B / 加工Y: 仕掛中の加工ジョブ (受入→分割後でまだ接合/納品前)

# --- 高炉A 未出荷在庫 (4 ロット) ------------------------------------
# 22. S-A-006: 大型梁材向け SM490 (受注残り待ち)
seed_create "S-A-006" org1 Org1MSP '{"category":"plate","grade":"SM490","weightKg":15000,"heatNo":"HT-A-006","note":"大型梁材向け"}'

# 23. S-A-007: 橋梁用高強度 SM520 (プレミアム在庫)
seed_create "S-A-007" org1 Org1MSP '{"category":"plate","grade":"SM520","weightKg":12000,"heatNo":"HT-A-007","note":"橋梁用高強度"}'

# 24. S-A-008: 汎用 SS400 10t (柱材向け標準品)
seed_create "S-A-008" org1 Org1MSP '{"category":"plate","grade":"SS400","weightKg":10000,"heatNo":"HT-A-008","note":"柱材向け標準品"}'

# 25. S-A-009: 小ロット補修用 SS400 5t
seed_create "S-A-009" org1 Org1MSP '{"category":"plate","grade":"SS400","weightKg":5000,"heatNo":"HT-A-009","note":"補修用小ロット"}'

# --- 電炉X 未出荷在庫 (5 ロット) ------------------------------------
# 26. S-X-005: H 形鋼 SM490 5t (汎用)
seed_create "S-X-005" org2 Org2MSP '{"category":"h-beam","grade":"SM490","weightKg":5000,"heatNo":"HT-X-005","note":"H形鋼 汎用梁材"}'

# 27. S-X-006: H 形鋼 SM520 8t (大型)
seed_create "S-X-006" org2 Org2MSP '{"category":"h-beam","grade":"SM520","weightKg":8000,"heatNo":"HT-X-006","note":"大型梁材"}'

# 28. S-X-007: 等辺アングル SS400 2t
seed_create "S-X-007" org2 Org2MSP '{"category":"angle","grade":"SS400","weightKg":2000,"heatNo":"HT-X-007","note":"ブレース用アングル"}'

# 29. S-X-008: チャンネル SM490 3t
seed_create "S-X-008" org2 Org2MSP '{"category":"channel","grade":"SM490","weightKg":3000,"heatNo":"HT-X-008","note":"チャンネル材"}'

# 30. S-X-009: 異形棒鋼 SD345 4t (鉄筋)
seed_create "S-X-009" org2 Org2MSP '{"category":"rebar","grade":"SD345","weightKg":4000,"heatNo":"HT-X-009","note":"鉄筋 D25"}'

# --- 加工B 仕掛中 (受入→分割中、接合前) ----------------------------
# 31. 高炉A が S-A-010 を製造 → 加工B へ譲渡
seed_create "S-A-010" org1 Org1MSP '{"category":"plate","grade":"SS400","weightKg":6000,"heatNo":"HT-A-010","note":"B受注分"}'
seed_transfer "S-A-010" org1 Org1MSP Org3MSP

# 32. 加工B が S-A-010 を 2 分割 (接合はまだ未着手 = 仕掛中)
seed_split "S-A-010" org3 '[{"childId":"S-A-010-a","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\",\"note\":\"接合待ち\"}"},{"childId":"S-A-010-b","toOwner":"Org3MSP","metadataJson":"{\"weightKg\":3000,\"grade\":\"SS400\",\"note\":\"接合待ち\"}"}]'

# --- 加工Y 仕掛中 (受入→分割中、接合前) ----------------------------
# 33. 電炉X が S-X-010 を製造 → 加工Y へ譲渡
seed_create "S-X-010" org2 Org2MSP '{"category":"angle","grade":"SS400","weightKg":4000,"heatNo":"HT-X-010","note":"Y受注分"}'
seed_transfer "S-X-010" org2 Org2MSP Org4MSP

# 34. 加工Y が S-X-010 を 2 分割 (接合待ち)
seed_split "S-X-010" org4 '[{"childId":"S-X-010-a","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":2000,\"grade\":\"SS400\",\"note\":\"接合待ち\"}"},{"childId":"S-X-010-b","toOwner":"Org4MSP","metadataJson":"{\"weightKg\":2000,\"grade\":\"SS400\",\"note\":\"接合待ち\"}"}]'

# --- 建設D 追加納品 (過去の別工区) ----------------------------------
# 35. 電炉X が S-X-011 (鉄筋ロット) を製造 → 加工Y → 建設D へ通し納品
#     D の手持ちに「素材をそのまま納品された鉄筋」パターンも追加。
seed_create "S-X-011" org2 Org2MSP '{"category":"rebar","grade":"SD390","weightKg":3000,"heatNo":"HT-X-011","note":"D 別工区向け鉄筋"}'
seed_transfer "S-X-011" org2 Org2MSP Org4MSP
seed_transfer "S-X-011" org4 Org4MSP Org5MSP

echo
ok "サンプルデータ投入完了"
echo
echo "${C_DIM}確認コマンド (各社の手持ち):${C_OFF}"
echo "  ./scripts/invoke_as.sh org1 query ListProductsByOwner Org1MSP   # 高炉A 未出荷在庫 (S-A-002, 006-009)"
echo "  ./scripts/invoke_as.sh org2 query ListProductsByOwner Org2MSP   # 電炉X 未出荷在庫 (S-X-005-009)"
echo "  ./scripts/invoke_as.sh org3 query ListProductsByOwner Org3MSP   # 加工B 手持ち (仕掛中 + 完成品)"
echo "  ./scripts/invoke_as.sh org4 query ListProductsByOwner Org4MSP   # 加工Y 手持ち"
echo "  ./scripts/invoke_as.sh org5 query ListProductsByOwner Org5MSP   # 建設D 納品済み"
echo
echo "${C_DIM}確認コマンド (複雑シナリオ):${C_OFF}"
echo "  ./scripts/invoke_as.sh org5 query GetLineage P-B-001            # 単純 DAG (A と X の 2 系統)"
echo "  ./scripts/invoke_as.sh org5 query GetLineage P-B-020            # Merge-of-Merge: 4 階層 DAG"
echo "  ./scripts/invoke_as.sh org3 query GetLineage P-B-040            # Diamond DAG: S-A-005 へ 2 経路"
echo "  ./scripts/invoke_as.sh org3 query GetHistory  S-A-010           # 仕掛中案件の履歴 (CREATE/TRANSFER/SPLIT)"
