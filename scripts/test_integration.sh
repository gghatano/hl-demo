#!/usr/bin/env bash
# test_integration.sh — Phase 5 T5-5
# L2 結合テスト エントリポイント
#
# - 3Org ネットワーク + product-trace chaincode デプロイ済みを前提
# - tests/integration/cases/*.sh を昇順で source し assert 実行
# - 失敗 1 件でも exit 1
#
# Usage:
#   ./scripts/test_integration.sh           # 現状のネットワーク/デプロイに対し実行
#   ./scripts/test_integration.sh --fresh   # reset → up → deploy してから実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FRESH=0
for arg in "$@"; do
  case "${arg}" in
    --fresh) FRESH=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: ${arg}" >&2; exit 2 ;;
  esac
done

if ((FRESH)); then
  echo "[test_integration] --fresh: reset → network_up → deploy_chaincode"
  "${SCRIPT_DIR}/reset.sh" --yes
  "${SCRIPT_DIR}/network_up.sh"
  "${SCRIPT_DIR}/deploy_chaincode.sh"
fi

# preflight
if ! command -v jq >/dev/null 2>&1; then
  echo "[test_integration] jq required" >&2; exit 1
fi

INVOKE="${SCRIPT_DIR}/invoke_as.sh"
[[ -x "${INVOKE}" ]] || { echo "invoke_as.sh not executable: ${INVOKE}" >&2; exit 1; }
export INVOKE

# 共通 source
# shellcheck source=/dev/null
source "${REPO_ROOT}/tests/integration/lib/assert.sh"
# format.sh は test 内では使わないが、将来 diagnostic 用に可搬にしておく
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/format.sh"

# ケース間で共有する productId（一意化）
STAMP="$(date +%s)-$$"
export PRODUCT_N_ID="ITEST-N-${STAMP}"
export PRODUCT_E1_ID="ITEST-E1-${STAMP}"

echo "================ L2 integration start ================"
echo "  PRODUCT_N_ID  = ${PRODUCT_N_ID}"
echo "  CHANNEL_NAME  = ${CHANNEL_NAME:-supplychannel}"
echo "  CC_NAME       = ${CC_NAME:-product-trace}"

shopt -s nullglob
cases=( "${REPO_ROOT}/tests/integration/cases/"*.sh )
shopt -u nullglob
if ((${#cases[@]} == 0)); then
  echo "[test_integration] no cases found" >&2; exit 1
fi

for c in "${cases[@]}"; do
  echo
  echo "================ ${c##*/} ================"
  # shellcheck source=/dev/null
  source "${c}"
done

tc_summary
