#!/usr/bin/env bash
# network_up.sh — Phase 2 ネットワーク起動
# test-network 標準フローで 2Org 起動 → addOrg3 で 3Org 合流
# MSP ID は fabric-samples 標準（Org1MSP/Org2MSP/Org3MSP, Issue #1）

set -euo pipefail

# ===== 設定 =====
CHANNEL_NAME="${CHANNEL_NAME:-supplychannel}"

# test-network が使うポート（orderer=7050, Org1 peer=7051, Org2 peer=9051, Org3 peer=11051）
FABRIC_PORTS=(7050 7051 9051 11051)

# 期待稼働数: orderer 1 + peer 3 + CA 4 (org1/org2/org3/orderer) = 8
EXPECTED_CONTAINERS=8

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

  # 既存コンテナ検出（peer/orderer/dev-peer 含む）
  local running
  running="$(docker ps --format '{{.Names}}' | grep -E '^(peer|orderer|dev-peer)' || true)"
  if [[ -n "${running}" ]]; then
    err "既存の Fabric コンテナが稼働中:"
    echo "${running}" | sed 's/^/    /' >&2
    err "scripts/reset.sh を実行してからやり直してください"
    exit 1
  fi

  # ポート衝突検出
  local busy=()
  for port in "${FABRIC_PORTS[@]}"; do
    if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
      exec 3<&- 3>&-
      busy+=("${port}")
    fi
  done
  if [[ ${#busy[@]} -gt 0 ]]; then
    err "Fabric が使うポートが既に使用されている: ${busy[*]}"
    err "他プロセスを停止してからやり直してください"
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

  # 期待数アサート（peer 3 + orderer 1 + CA 3 = 7）
  local actual
  actual="$(docker ps --format '{{.Names}}' | grep -Ec '^(peer[0-9]+\.org[0-9]+|orderer|ca_org[0-9]+|ca_orderer)' || true)"
  if [[ "${actual}" -ne "${EXPECTED_CONTAINERS}" ]]; then
    err "稼働コンテナ数が期待値と不一致: actual=${actual}, expected=${EXPECTED_CONTAINERS}"
    err "peer3 + orderer1 + CA4 = 8 を期待"
    exit 1
  fi
  ok "稼働コンテナ数: ${actual}/${EXPECTED_CONTAINERS}"

  # Org3 視点 channel 疎通確認
  log "==== Org3 視点 channel 疎通確認 ===="
  local peer_bin="${SAMPLES_DIR}/bin/peer"
  local org3_tls="${TEST_NET_DIR}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt"
  local org3_msp="${TEST_NET_DIR}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp"
  if [[ ! -x "${peer_bin}" ]]; then
    warn "peer binary 見つからず: ${peer_bin} → skip"
  elif [[ ! -f "${org3_tls}" ]]; then
    warn "Org3 TLS cert 見つからず: ${org3_tls} → skip"
  elif [[ ! -d "${org3_msp}" ]]; then
    warn "Org3 Admin MSP 見つからず: ${org3_msp} → skip"
  else
    local info
    if info=$(FABRIC_CFG_PATH="${SAMPLES_DIR}/config" \
              CORE_PEER_TLS_ENABLED=true \
              CORE_PEER_LOCALMSPID=Org3MSP \
              CORE_PEER_TLS_ROOTCERT_FILE="${org3_tls}" \
              CORE_PEER_MSPCONFIGPATH="${org3_msp}" \
              CORE_PEER_ADDRESS=localhost:11051 \
              "${peer_bin}" channel getinfo -c "${CHANNEL_NAME}" 2>&1); then
      ok "Org3 から ${CHANNEL_NAME} 参照成功"
      echo "${info}" | sed 's/^/    /'
    else
      warn "Org3 視点 peer channel getinfo 失敗:"
      echo "${info}" | sed 's/^/    /' >&2
    fi
  fi
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
  echo "${C_DIM}次: ./scripts/deploy_chaincode.sh で chaincode を deploy${C_OFF}"
  echo "${C_DIM}クリーンアップ: ./scripts/reset.sh${C_OFF}"
}
main "$@"
