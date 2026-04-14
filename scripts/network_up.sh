#!/usr/bin/env bash
# network_up.sh — Phase 2 ネットワーク起動
# test-network 標準フローで 2Org 起動 → addOrg3 で 3Org 合流
# MSP ID は fabric-samples 標準（Org1MSP/Org2MSP/Org3MSP, Issue #1）

set -euo pipefail

# ===== 設定 =====
CHANNEL_NAME="${CHANNEL_NAME:-supplychannel}"

# ===== パス =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SAMPLES_DIR="${REPO_ROOT}/fabric/fabric-samples"
TEST_NET_DIR="${SAMPLES_DIR}/test-network"

# ===== 色 =====
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi
log()  { echo "${C_DIM}[network_up]${C_OFF} $*"; }
ok()   { echo "${C_OK}[ ok ]${C_OFF} $*"; }
warn() { echo "${C_WARN}[warn]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[err ]${C_OFF} $*" >&2; }

# ===== ヘルプ =====
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

test-network 標準フローで 3Org + supplychannel を起動。

Options:
  -c, --channel <name>   channel 名（default: supplychannel）
  -h, --help             ヘルプ

既存ネットワークがある場合はエラーで停止する。
再起動する場合は scripts/reset.sh を先に実行。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--channel) CHANNEL_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
done

# ===== 前提チェック =====
preflight() {
  if [[ ! -d "${TEST_NET_DIR}" ]]; then
    err "test-network が見つからない: ${TEST_NET_DIR}"
    err "先に ./scripts/setup.sh を実行してください"
    exit 1
  fi
  if [[ ! -x "${TEST_NET_DIR}/network.sh" ]]; then
    err "network.sh が実行可能でない: ${TEST_NET_DIR}/network.sh"
    exit 1
  fi
  if [[ ! -x "${TEST_NET_DIR}/addOrg3/addOrg3.sh" ]]; then
    err "addOrg3.sh が見つからない: ${TEST_NET_DIR}/addOrg3/addOrg3.sh"
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    err "docker daemon に接続できない"
    exit 1
  fi

  # 既存コンテナ検出
  local running
  running="$(docker ps --format '{{.Names}}' | grep -E '^(peer|orderer)' || true)"
  if [[ -n "${running}" ]]; then
    err "既存の Fabric コンテナが稼働中:"
    echo "${running}" | sed 's/^/    /' >&2
    err "scripts/reset.sh を実行してからやり直してください"
    exit 1
  fi
}

# ===== 2Org 起動 + channel 作成 =====
up_two_org() {
  log "==== test-network up (2Org + CA + channel=${CHANNEL_NAME}) ===="
  (cd "${TEST_NET_DIR}" && ./network.sh up createChannel -c "${CHANNEL_NAME}" -ca)
  ok "2Org + ${CHANNEL_NAME} 起動完了"
}

# ===== Org3 合流 =====
up_org3() {
  log "==== addOrg3 up (join ${CHANNEL_NAME}) ===="
  (cd "${TEST_NET_DIR}/addOrg3" && ./addOrg3.sh up -c "${CHANNEL_NAME}" -ca)
  ok "Org3 合流完了"
}

# ===== 検証 =====
verify() {
  log "==== 検証 ===="
  log "稼働中コンテナ:"
  docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '^(NAMES|peer|orderer|ca_)' | sed 's/^/  /'
}

main() {
  log "repo root: ${REPO_ROOT}"
  log "channel:   ${CHANNEL_NAME}"
  preflight
  up_two_org
  up_org3
  verify
  echo
  ok "Phase 2 network up 完了"
  echo "${C_DIM}次: Phase 3 Chaincode 実装 / Phase 4 deploy_chaincode.sh${C_OFF}"
  echo "${C_DIM}クリーンアップ: ./scripts/reset.sh${C_OFF}"
}
main "$@"
