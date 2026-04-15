#!/usr/bin/env bash
# deploy_chaincode.sh — Phase 4 T4-1
# product-trace chaincode を 3Org にデプロイ
# - package → install×3 → approve×3 → commit
# - endorsement policy: OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')  (3Org OR 必須)
# - version / sequence 引数化（再デプロイ衝突回避）
# - 冪等性: 既に install/approve/commit 済なら skip

set -euo pipefail

# ===== 既定値 =====
CHANNEL_NAME="${CHANNEL_NAME:-supplychannel}"
CC_NAME="${CC_NAME:-product-trace}"
CC_VERSION="${CC_VERSION:-1.0}"
CC_SEQUENCE="${CC_SEQUENCE:-1}"
CC_LANG="node"
SIG_POLICY="OR('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')"

# ===== パス =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SAMPLES_DIR="${REPO_ROOT}/fabric/fabric-samples"
TEST_NET_DIR="${SAMPLES_DIR}/test-network"
CC_SRC="${REPO_ROOT}/chaincode/product-trace"
PKG_DIR="${REPO_ROOT}/build"
CC_STAGE="${PKG_DIR}/stage-${CC_NAME}"
PKG_FILE="${PKG_DIR}/${CC_NAME}_${CC_VERSION}.tar.gz"
CC_LABEL="${CC_NAME}_${CC_VERSION}"

PEER_BIN="${SAMPLES_DIR}/bin/peer"
export FABRIC_CFG_PATH="${SAMPLES_DIR}/config"

ORDERER_CA="${TEST_NET_DIR}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER_ADDR="localhost:7050"
ORDERER_HOST="orderer.example.com"

# ===== 色 =====
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi
log()  { echo "${C_DIM}[deploy_cc]${C_OFF} $*"; }
ok()   { echo "${C_OK}[ ok ]${C_OFF} $*"; }
warn() { echo "${C_WARN}[warn]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[err ]${C_OFF} $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

product-trace chaincode を 3Org にデプロイする。

Options:
  -c, --channel <name>     channel 名 (default: ${CHANNEL_NAME})
  -n, --name <name>        chaincode 名 (default: ${CC_NAME})
  -v, --version <ver>      chaincode version (default: ${CC_VERSION})
  -s, --sequence <seq>     lifecycle sequence (default: ${CC_SEQUENCE})
  -h, --help               ヘルプ

再デプロイ時は version / sequence を必ず上げること:
  例) ./deploy_chaincode.sh -v 1.1 -s 2
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--channel)  CHANNEL_NAME="$2"; shift 2 ;;
    -n|--name)     CC_NAME="$2"; shift 2 ;;
    -v|--version)  CC_VERSION="$2"; shift 2 ;;
    -s|--sequence) CC_SEQUENCE="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
done

PKG_FILE="${PKG_DIR}/${CC_NAME}_${CC_VERSION}.tar.gz"
CC_LABEL="${CC_NAME}_${CC_VERSION}"

# ===== Org 切替 =====
# set_org_env <1|2|3>  — CORE_PEER_* を対象 Org の Admin にセット
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
    *) err "invalid org: $n"; exit 2 ;;
  esac
}

peer_tls_args() {
  # stdout に peer CLI 用 TLS 引数を吐く
  local n="$1"
  local tls="${TEST_NET_DIR}/organizations/peerOrganizations/org${n}.example.com/peers/peer0.org${n}.example.com/tls/ca.crt"
  local host port
  case "$n" in
    1) host="localhost"; port=7051  ;;
    2) host="localhost"; port=9051  ;;
    3) host="localhost"; port=11051 ;;
  esac
  printf -- '--peerAddresses %s:%s --tlsRootCertFiles %s' "$host" "$port" "$tls"
}

preflight() {
  [[ -x "${PEER_BIN}" ]] || { err "peer binary 不在: ${PEER_BIN} (setup.sh 実行要)"; exit 1; }
  [[ -d "${CC_SRC}" ]]   || { err "chaincode ソース不在: ${CC_SRC}"; exit 1; }
  [[ -f "${ORDERER_CA}" ]] || { err "orderer TLS CA 不在: ${ORDERER_CA} (network_up.sh 実行要)"; exit 1; }
  if ! docker ps --format '{{.Names}}' | grep -q '^peer0.org1.example.com$'; then
    err "Fabric ネットワーク未起動。先に ./scripts/network_up.sh を実行してください"
    exit 1
  fi
  mkdir -p "${PKG_DIR}"
}

# ===== 1) package =====
# node_modules / test / build 成果物を除いた staging ディレクトリから package する
# （そのまま CC_SRC を指すと node_modules 込みで tar が肥大化し peer 側 docker build が
#   "write unix @->/run/docker.sock: broken pipe" で落ちる）
do_package() {
  log "==== package (label=${CC_LABEL}) ===="
  if [[ -f "${PKG_FILE}" ]]; then
    log "既存 package 削除: ${PKG_FILE}"
    rm -f "${PKG_FILE}"
  fi
  log "staging source → ${CC_STAGE}"
  rm -rf "${CC_STAGE}"
  mkdir -p "${CC_STAGE}"
  # node_modules, test, .nyc_output 等を除外して rsync 相当
  tar --exclude='node_modules' \
      --exclude='test' \
      --exclude='.nyc_output' \
      --exclude='coverage' \
      --exclude='*.log' \
      -C "${CC_SRC}" -cf - . | tar -C "${CC_STAGE}" -xf -
  set_org_env 1
  "${PEER_BIN}" lifecycle chaincode package "${PKG_FILE}" \
    --path "${CC_STAGE}" \
    --lang "${CC_LANG}" \
    --label "${CC_LABEL}"
  ok "package: ${PKG_FILE}"
}

# ===== 2) install (3Org) + package ID 取得 =====
PACKAGE_ID=""
do_install_all() {
  log "==== install on Org1/Org2/Org3 ===="
  for n in 1 2 3; do
    set_org_env "$n"
    if "${PEER_BIN}" lifecycle chaincode queryinstalled --output json 2>/dev/null \
         | jq -e --arg l "${CC_LABEL}" \
             '.installed_chaincodes // [] | map(.label) | index($l)' >/dev/null; then
      ok "Org${n}: ${CC_LABEL} 既に install 済 → skip"
    else
      log "Org${n}: install ${PKG_FILE}"
      "${PEER_BIN}" lifecycle chaincode install "${PKG_FILE}"
      ok "Org${n}: install 完了"
    fi
  done

  set_org_env 1
  # 正確な label 一致で package ID を取るため JSON 出力 → jq
  PACKAGE_ID="$(
    "${PEER_BIN}" lifecycle chaincode queryinstalled --output json \
      | jq -r --arg l "${CC_LABEL}" \
          '.installed_chaincodes[] | select(.label==$l) | .package_id' \
      | head -n1
  )"
  [[ -n "${PACKAGE_ID}" ]] || { err "package ID 取得失敗 (label=${CC_LABEL})"; exit 1; }
  ok "package ID: ${PACKAGE_ID}"
}

# ===== 3) approve (3Org) =====
# skip 判定は version / sequence / package_id の 3 点一致。
# package_id まで見ないと、staging 差分で hash が変わったのに「approve 済」扱いされ、
# commit / invoke 時に古い approval と新 install の不整合で壊れる
do_approve_all() {
  log "==== approveformyorg on Org1/Org2/Org3 ===="
  for n in 1 2 3; do
    set_org_env "$n"
    # queryapproved JSON 構造 (Fabric 2.5.15):
    #   .version / .sequence / .source.Type.LocalPackage.package_id
    if "${PEER_BIN}" lifecycle chaincode queryapproved \
         -C "${CHANNEL_NAME}" -n "${CC_NAME}" --output json 2>/dev/null \
         | jq -e --arg v "${CC_VERSION}" \
                --argjson s "${CC_SEQUENCE}" \
                --arg p "${PACKAGE_ID}" \
             '.version==$v and .sequence==$s and .source.Type.LocalPackage.package_id==$p' \
         >/dev/null; then
      ok "Org${n}: seq=${CC_SEQUENCE} ver=${CC_VERSION} pkg=${PACKAGE_ID##*:} 既に approve 済 → skip"
      continue
    fi
    log "Org${n}: approveformyorg"
    "${PEER_BIN}" lifecycle chaincode approveformyorg \
      -o "${ORDERER_ADDR}" --ordererTLSHostnameOverride "${ORDERER_HOST}" \
      --tls --cafile "${ORDERER_CA}" \
      --channelID "${CHANNEL_NAME}" \
      --name "${CC_NAME}" \
      --version "${CC_VERSION}" \
      --package-id "${PACKAGE_ID}" \
      --sequence "${CC_SEQUENCE}" \
      --signature-policy "${SIG_POLICY}"
    ok "Org${n}: approve 完了"
  done
}

# ===== 4) commit readiness & commit =====
do_commit() {
  set_org_env 1

  # 先に querycommitted: 既に同 ver/seq で commit 済なら checkcommitreadiness ごと skip
  # (checkcommitreadiness は「次に commit すべき sequence」を要求するため、現 seq を
  #  渡すと "requested sequence is X, but new definition must be sequence X+1" で落ちる)
  if "${PEER_BIN}" lifecycle chaincode querycommitted \
       -C "${CHANNEL_NAME}" -n "${CC_NAME}" --output json 2>/dev/null \
       | jq -e --arg v "${CC_VERSION}" --argjson s "${CC_SEQUENCE}" \
           '.version==$v and .sequence==$s' >/dev/null; then
    ok "seq=${CC_SEQUENCE} ver=${CC_VERSION} 既に commit 済 → skip"
    return
  fi

  log "==== check commit readiness ===="
  local readiness
  readiness="$("${PEER_BIN}" lifecycle chaincode checkcommitreadiness \
    --channelID "${CHANNEL_NAME}" \
    --name "${CC_NAME}" \
    --version "${CC_VERSION}" \
    --sequence "${CC_SEQUENCE}" \
    --signature-policy "${SIG_POLICY}" \
    --output json)"
  echo "${readiness}"
  # PoC 規約: OR policy だが lifecycle は 3Org 全 approve を前提条件として強制する
  if ! echo "${readiness}" | jq -e '[.approvals | to_entries[] | .value] | all' >/dev/null; then
    err "3Org 全 approve が揃っていません (checkcommitreadiness):"
    echo "${readiness}" | jq '.approvals' >&2
    exit 1
  fi
  ok "3Org 全 approve 確認"

  log "==== commit ===="
  # 3Org すべての peer を target にして OR policy 下で lifecycle endorsement を満たす
  # shellcheck disable=SC2046
  "${PEER_BIN}" lifecycle chaincode commit \
    -o "${ORDERER_ADDR}" --ordererTLSHostnameOverride "${ORDERER_HOST}" \
    --tls --cafile "${ORDERER_CA}" \
    --channelID "${CHANNEL_NAME}" \
    --name "${CC_NAME}" \
    --version "${CC_VERSION}" \
    --sequence "${CC_SEQUENCE}" \
    --signature-policy "${SIG_POLICY}" \
    $(peer_tls_args 1) \
    $(peer_tls_args 2) \
    $(peer_tls_args 3)
  ok "commit 完了"
}

do_verify() {
  log "==== querycommitted ===="
  set_org_env 1
  "${PEER_BIN}" lifecycle chaincode querycommitted \
    --channelID "${CHANNEL_NAME}" --name "${CC_NAME}"
}

main() {
  log "channel:  ${CHANNEL_NAME}"
  log "cc:       ${CC_NAME} v${CC_VERSION} seq=${CC_SEQUENCE}"
  log "policy:   ${SIG_POLICY}"
  preflight
  do_package
  do_install_all
  do_approve_all
  do_commit
  do_verify
  echo
  ok "Phase 4 deploy 完了"
  echo "${C_DIM}次: ./scripts/invoke_as.sh org1 CreateProduct X001 Org1MSP Org1MSP${C_OFF}"
}
main "$@"
