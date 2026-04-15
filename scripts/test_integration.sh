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

# preflight: 新人環境で「invoke failed」だけ出て迷子化しないよう、依存を明示
fail_pre() { echo "[test_integration] $*" >&2; exit 1; }

command -v jq     >/dev/null 2>&1 || fail_pre "jq が必要（apt install jq）"
command -v docker >/dev/null 2>&1 || fail_pre "docker が必要"
docker info       >/dev/null 2>&1 || fail_pre "docker daemon に接続できない（WSL2 では sg docker -c で実行するか newgrp docker）"

SAMPLES_DIR="${REPO_ROOT}/fabric/fabric-samples"
PEER_BIN="${SAMPLES_DIR}/bin/peer"
[[ -x "${PEER_BIN}" ]] || fail_pre "peer binary 不在: ${PEER_BIN} (先に ./scripts/setup.sh)"

INVOKE="${SCRIPT_DIR}/invoke_as.sh"
[[ -x "${INVOKE}" ]] || fail_pre "invoke_as.sh not executable: ${INVOKE}"
export INVOKE

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^peer0.org1.example.com$'; then
  fail_pre "Fabric ネットワーク未起動。./scripts/test_integration.sh --fresh か ./scripts/network_up.sh を先に"
fi

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

# 各 case は子シェルで実行し、1 件の構文/exit エラーで全停止しないようにする。
# 子シェルのカウンタは tempfile に吐き出して親で集計する。
TC_TMP="$(mktemp -t hl-l2-XXXXXX)"
trap 'rm -f "${TC_TMP}"' EXIT

for c in "${cases[@]}"; do
  echo
  echo "================ ${c##*/} ================"
  if ! bash -n "${c}" 2>&1; then
    tc_fail "case ${c##*/}: syntax error"
    continue
  fi
  (
    # サブシェルで source。set -e の脱出や変数破壊が親に波及しない。
    # 子は差分だけをカウントするよう親の値をリセットしてから開始。
    TC_PASS=0
    TC_FAIL=0
    FAILED_CASES=()
    # shellcheck source=/dev/null
    source "${c}"
    printf '%s\n%s\n' "${TC_PASS}" "${TC_FAIL}" > "${TC_TMP}"
    for f in "${FAILED_CASES[@]+"${FAILED_CASES[@]}"}"; do
      printf 'F\t%s\n' "${f}" >> "${TC_TMP}"
    done
  ) || tc_fail "case ${c##*/}: aborted (rc=$?)"

  if [[ -s "${TC_TMP}" ]]; then
    sub_pass=$(sed -n '1p' "${TC_TMP}")
    sub_fail=$(sed -n '2p' "${TC_TMP}")
    TC_PASS=$((TC_PASS + ${sub_pass:-0}))
    TC_FAIL=$((TC_FAIL + ${sub_fail:-0}))
    while IFS=$'\t' read -r mark msg; do
      [[ "${mark}" == "F" ]] && FAILED_CASES+=("${msg}")
    done < <(sed -n '3,$p' "${TC_TMP}")
    : > "${TC_TMP}"
  fi
done

tc_summary
