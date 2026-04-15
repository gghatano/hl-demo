#!/usr/bin/env bash
# demo_verify_as_c.sh — Phase 5 T5-4
# クライマックス: 販売店 C の立場で履歴を引き、起点 A を特定して見せる
#
# - demo_normal.sh が作った product に対して単独再実行可能
# - 画面クリア → C 視点ナレーション → 履歴表示 → 起点 A ハイライト
#
# Usage:
#   ./scripts/demo_verify_as_c.sh <productId>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/format.sh"

INVOKE="${SCRIPT_DIR}/invoke_as.sh"
PAUSE="${DEMO_PAUSE:-1.5}"
pause() { sleep "${PAUSE}" 2>/dev/null || true; }

PRODUCT_ID="${1:-}"
# 引数省略時: demo_normal.sh が残した .last_product_id を拾う
if [[ -z "${PRODUCT_ID}" && -f "${REPO_ROOT}/.last_product_id" ]]; then
  PRODUCT_ID="$(cat "${REPO_ROOT}/.last_product_id")"
fi
if [[ -z "${PRODUCT_ID}" ]]; then
  cat >&2 <<EOF
Usage: $(basename "$0") [productId]
  productId 省略時は直近の demo_normal.sh が書いた .last_product_id を読む
  環境変数: DEMO_PAUSE (既定 1.5 秒) で pause 間隔を調整
EOF
  exit 2
fi

clear 2>/dev/null || true
cat <<'EOS'

================================================================
  販売店 C の立場で ──
  「この商品、本当に あのメーカー A が作ったものですか？」
================================================================
EOS
pause

say_narration "■ 状況設定"
say_note "販売店 C のカウンターに、1 つの商品が並んでいる。"
say_note "productId: ${PRODUCT_ID}"
say_note "C は この商品の素性を知らない。流通過程で差し替わっている可能性もある。"
pause

say_narration "■ C が行動する"
say_note "C は台帳に対し、自組織 Org3MSP のクレデンシャルで履歴を問い合わせる。"
say_note "問合せ先は C 自身の peer0 ──「C の手元の台帳」──であって、"
say_note "A や B の言い分を信用する必要はない。"
pause

say_step "現在の所有状態を確認 (Org3 view)"
"${INVOKE}" org3 query ReadProduct "${PRODUCT_ID}" 2>/dev/null | format_product
pause

say_step "譲渡履歴を時系列で取得"
HIST_JSON=$("${INVOKE}" org3 query GetHistory "${PRODUCT_ID}" 2>/dev/null)
printf '%s' "${HIST_JSON}" | format_history
pause

# 起点 A のハイライト
FIRST_ACTOR=$(printf '%s' "${HIST_JSON}" | jq -r '.[0].actor.mspId // "-"')
FIRST_EVENT=$(printf '%s' "${HIST_JSON}" | jq -r '.[0].eventType // "-"')
FIRST_TX=$(printf '%s'   "${HIST_JSON}" | jq -r '.[0].txId // "-"')
FIRST_TS=$(printf '%s'   "${HIST_JSON}" | jq -r '.[0].timestamp // "-"')
FIRST_ROLE=$(msp_to_role "${FIRST_ACTOR}")

echo
say_narration "■ 起点の特定"
printf '  %s#1 %s event=%s\n' "${FMT_BOLD}${FMT_YELLOW}" "${FMT_OFF}" "${FIRST_EVENT}"
printf '    by      : %s%s%s (%s)\n' "${FMT_BOLD}" "${FIRST_ROLE}" "${FMT_OFF}" "${FIRST_ACTOR}"
printf '    at      : %s\n' "${FIRST_TS}"
printf '    txId    : %s\n' "${FIRST_TX}"
pause

say_narration "■ 結論"
if [[ "${FIRST_ACTOR}" == "Org1MSP" ]]; then
  say_note "→ この商品は 確かに メーカー A によって台帳に登録された。"
  say_note "→ その後 卸 B を経由し、C の手元に渡った。"
  say_note "→ B や C の主張ではなく、ネットワーク全体で承認された履歴として証明された。"
else
  say_note "→ 起点は ${FIRST_ROLE} (${FIRST_ACTOR}) であり メーカー A ではない。"
  say_note "→ この商品は正規ルートから外れている可能性がある。"
fi
echo
