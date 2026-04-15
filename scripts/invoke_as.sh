#!/usr/bin/env bash
# invoke_as.sh — Phase 4 T4-2
# 指定 Org の Admin identity で product-trace chaincode を invoke / query
#
# Usage:
#   ./invoke_as.sh <org> <invoke|query> <fn> [args...]
#   ./invoke_as.sh <org> <fn> [args...]              # invoke 省略時 invoke 扱い
#
# 例:
#   ./invoke_as.sh org1 invoke CreateProduct X001 Org1MSP Org1MSP
#   ./invoke_as.sh org3 query  ReadProduct X001
#   ./invoke_as.sh org1 query  GetHistory X001
#
# 仕様:
#   - invoke 時は 3Org すべての peer を --peerAddresses で target し endorsement policy
#     OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer') を充足
#   - query は呼出元 Org の peer 単体
#   - FABRIC_CFG_PATH=<samples>/config を必ず export

set -euo pipefail

CHANNEL_NAME="${CHANNEL_NAME:-supplychannel}"
CC_NAME="${CC_NAME:-product-trace}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SAMPLES_DIR="${REPO_ROOT}/fabric/fabric-samples"
TEST_NET_DIR="${SAMPLES_DIR}/test-network"
PEER_BIN="${SAMPLES_DIR}/bin/peer"
export FABRIC_CFG_PATH="${SAMPLES_DIR}/config"

ORDERER_CA="${TEST_NET_DIR}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER_ADDR="localhost:7050"
ORDERER_HOST="orderer.example.com"

if [[ -t 1 ]]; then
  C_DIM=$'\033[2m'; C_ERR=$'\033[31m'; C_OFF=$'\033[0m'
else
  C_DIM=""; C_ERR=""; C_OFF=""
fi
log() { echo "${C_DIM}[invoke_as]${C_OFF} $*" >&2; }
err() { echo "${C_ERR}[err ]${C_OFF} $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <org> <invoke|query> <fn> [args...]
  $(basename "$0") <org> <fn> [args...]        # invoke 省略時 invoke

org:  org1 | org2 | org3
EOF
}

[[ $# -ge 2 ]] || { usage; exit 2; }

ORG_RAW="$1"; shift
MODE=""
case "${1:-}" in
  invoke|query) MODE="$1"; shift ;;
  *) MODE="invoke" ;;
esac
FN="${1:-}"
[[ -n "${FN}" ]] || { err "function 名が必要"; usage; exit 2; }
shift
FN_ARGS=("$@")

preflight() {
  [[ -x "${PEER_BIN}" ]] || { err "peer binary 不在: ${PEER_BIN} (setup.sh 実行要)"; exit 1; }
  [[ -f "${ORDERER_CA}" ]] || { err "orderer TLS CA 不在: ${ORDERER_CA} (network_up.sh 実行要)"; exit 1; }
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^peer0.org1.example.com$'; then
    err "Fabric ネットワーク未起動。先に ./scripts/network_up.sh を実行してください"
    exit 1
  fi
}
preflight

case "${ORG_RAW}" in
  org1|1) ORG_N=1 ;;
  org2|2) ORG_N=2 ;;
  org3|3) ORG_N=3 ;;
  *) err "invalid org: ${ORG_RAW} (org1|org2|org3)"; exit 2 ;;
esac

set_org_env() {
  local n="$1"
  local org_dir="${TEST_NET_DIR}/organizations/peerOrganizations/org${n}.example.com"
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_LOCALMSPID="Org${n}MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="${org_dir}/peers/peer0.org${n}.example.com/tls/ca.crt"
  export CORE_PEER_MSPCONFIGPATH="${org_dir}/users/Admin@org${n}.example.com/msp"
  case "$n" in
    1) export CORE_PEER_ADDRESS=localhost:7051  ;;
    2) export CORE_PEER_ADDRESS=localhost:9051  ;;
    3) export CORE_PEER_ADDRESS=localhost:11051 ;;
  esac
}

peer_tls_args() {
  local n="$1"
  local tls="${TEST_NET_DIR}/organizations/peerOrganizations/org${n}.example.com/peers/peer0.org${n}.example.com/tls/ca.crt"
  local host="localhost" port
  case "$n" in
    1) port=7051  ;;
    2) port=9051  ;;
    3) port=11051 ;;
  esac
  printf -- '--peerAddresses %s:%s --tlsRootCertFiles %s' "$host" "$port" "$tls"
}

# 標準形 ctor: {"Args":["fn","arg1","arg2",...]}
ctor_json() {
  local json='{"Args":['
  local a
  json+="\"${FN}\""
  for a in "${FN_ARGS[@]}"; do
    local esc="${a//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    json+=",\"${esc}\""
  done
  json+="]}"
  printf '%s' "${json}"
}

set_org_env "${ORG_N}"
CTOR="$(ctor_json)"

if [[ "${MODE}" == "query" ]]; then
  log "query as Org${ORG_N}: ${FN} ${FN_ARGS[*]}"
  "${PEER_BIN}" chaincode query \
    -C "${CHANNEL_NAME}" -n "${CC_NAME}" \
    -c "${CTOR}"
else
  log "invoke as Org${ORG_N}: ${FN} ${FN_ARGS[*]}"
  # shellcheck disable=SC2046
  "${PEER_BIN}" chaincode invoke \
    -o "${ORDERER_ADDR}" --ordererTLSHostnameOverride "${ORDERER_HOST}" \
    --tls --cafile "${ORDERER_CA}" \
    -C "${CHANNEL_NAME}" -n "${CC_NAME}" \
    $(peer_tls_args 1) \
    $(peer_tls_args 2) \
    $(peer_tls_args 3) \
    -c "${CTOR}" \
    --waitForEvent
fi
