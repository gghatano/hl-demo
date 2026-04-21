#!/usr/bin/env bash
# network_up.sh — Phase 8: 5Org (Org1〜Org5) + supplychannel 起動
#
# 起動順序:
#   1. fabric/test-network-wrapper/patches/ を fabric-samples/test-network/ に適用
#   2. test-network 標準で 2Org (Org1+Org2) + orderer + supplychannel 起動
#   3. addOrg3 で Org3 合流
#   4. addOrg4 (patches 由来) で Org4 合流
#   5. addOrg5 (patches 由来) で Org5 合流
#   6. 5Org 稼働確認 (Org5 視点で channel getinfo)
#
# 期待稼働コンテナ: orderer 1 + peer 5 + CA 6 = 12

set -euo pipefail

# ===== 設定 =====
CHANNEL_NAME="${CHANNEL_NAME:-supplychannel}"

# ポート: Org1=7051 / Org2=9051 / Org3=11051 / Org4=13051 / Org5=15051
FABRIC_PORTS=(7050 7051 9051 11051 13051 15051)

# 期待稼働数: orderer 1 + peer 5 + CA 6 (orderer/org1〜org5) = 12
EXPECTED_CONTAINERS=12

# ===== パス =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SAMPLES_DIR="${REPO_ROOT}/fabric/fabric-samples"
TEST_NET_DIR="${SAMPLES_DIR}/test-network"
WRAPPER_DIR="${REPO_ROOT}/fabric/test-network-wrapper"
PATCHES_DIR="${WRAPPER_DIR}/patches"

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

hl-proto v2 (Phase 8) の 5Org supplychannel を起動する。

Options:
  -c, --channel <name>   channel 名 (default: supplychannel)
  -h, --help             ヘルプ

既存ネットワークがある場合はエラー停止。再起動時は scripts/reset.sh --yes 先行。
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
  if [[ ! -d "${PATCHES_DIR}/addOrg4" ]] || [[ ! -d "${PATCHES_DIR}/addOrg5" ]]; then
    err "patches/addOrg{4,5} が見つからない: ${PATCHES_DIR}"
    err "先に ${WRAPPER_DIR}/gen_addorg.sh 4 13051 13054 と 5 15051 15054 を実行してください"
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    err "docker daemon に接続できない"
    exit 1
  fi

  # 既存コンテナ検出 (peer/orderer/dev-peer)
  local running
  running="$(docker ps --format '{{.Names}}' | grep -E '^(peer|orderer|dev-peer)' || true)"
  if [[ -n "${running}" ]]; then
    err "既存の Fabric コンテナが稼働中:"
    echo "${running}" | sed 's/^/    /' >&2
    err "scripts/reset.sh --yes を実行してからやり直してください"
    exit 1
  fi

  # ポート衝突
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

# ===== patches 適用 =====
# fabric-samples 側に addOrg4/5 と org4/5-scripts を配置する。
# 既に存在する場合は冪等に上書き (既存生成物は reset.sh で掃除済前提)。
apply_patches() {
  log "==== patches 適用 (addOrg4/5, org4/5-scripts, envVar/setAnchorPeer 5Org 対応) ===="

  # envVar.sh / setAnchorPeer.sh は fabric-samples 同梱の Org1-3 限定版を
  # 5Org 対応版で上書きする。オリジナルは fabric-samples の git checkout で戻せる。
  local core_scripts_src="${PATCHES_DIR}/scripts"
  if [[ -f "${core_scripts_src}/envVar.sh" ]]; then
    cp "${core_scripts_src}/envVar.sh" "${TEST_NET_DIR}/scripts/envVar.sh"
    log "  envVar.sh → test-network/scripts/ (5Org 対応)"
  fi
  if [[ -f "${core_scripts_src}/setAnchorPeer.sh" ]]; then
    cp "${core_scripts_src}/setAnchorPeer.sh" "${TEST_NET_DIR}/scripts/setAnchorPeer.sh"
    chmod +x "${TEST_NET_DIR}/scripts/setAnchorPeer.sh"
    log "  setAnchorPeer.sh → test-network/scripts/ (5Org 対応)"
  fi

  local n
  for n in 4 5; do
    local src="${PATCHES_DIR}/addOrg${n}"
    local dst="${TEST_NET_DIR}/addOrg${n}"
    if [[ ! -d "${src}" ]]; then
      err "patches/addOrg${n} なし: ${src}"
      exit 1
    fi
    log "  addOrg${n}/ → ${dst#${SAMPLES_DIR}/}"
    rm -rf "${dst}"
    cp -r "${src}" "${dst}"
    chmod +x "${dst}/addOrg${n}.sh" 2>/dev/null || true
    chmod +x "${dst}/ccp-generate.sh" 2>/dev/null || true
    chmod +x "${dst}/fabric-ca/registerEnroll.sh" 2>/dev/null || true
  done
  for n in 4 5; do
    local src="${PATCHES_DIR}/scripts/org${n}-scripts"
    local dst="${TEST_NET_DIR}/scripts/org${n}-scripts"
    if [[ ! -d "${src}" ]]; then
      err "patches/scripts/org${n}-scripts なし: ${src}"
      exit 1
    fi
    log "  scripts/org${n}-scripts/ → ${dst#${SAMPLES_DIR}/}"
    rm -rf "${dst}"
    cp -r "${src}" "${dst}"
    chmod +x "${dst}/"*.sh 2>/dev/null || true
  done
  ok "patches 適用完了"
}

# ===== 2Org (Org1+Org2) + channel 起動 =====
up_two_org() {
  log "==== test-network up (2Org + CA + channel=${CHANNEL_NAME}) ===="
  (cd "${TEST_NET_DIR}" && ./network.sh up createChannel -c "${CHANNEL_NAME}" -ca)
  ok "Org1+Org2 + ${CHANNEL_NAME} 起動完了"
}

# ===== addOrg<N> 合流 汎用 =====
up_org_n() {
  local n="$1"
  log "==== addOrg${n} up (join ${CHANNEL_NAME}) ===="
  (cd "${TEST_NET_DIR}/addOrg${n}" && ./addOrg${n}.sh up -c "${CHANNEL_NAME}" -ca)
  ok "Org${n} 合流完了"
}

# ===== 検証 =====
verify() {
  log "==== 検証 ===="
  log "稼働中コンテナ:"
  docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '^(NAMES|peer|orderer|ca_)' | sed 's/^/  /'

  # 期待数アサート (peer 5 + orderer 1 + CA 6 = 12)
  local actual
  actual="$(docker ps --format '{{.Names}}' | grep -Ec '^(peer[0-9]+\.org[0-9]+|orderer|ca_org[0-9]+|ca_orderer)' || true)"
  if [[ "${actual}" -ne "${EXPECTED_CONTAINERS}" ]]; then
    err "稼働コンテナ数が期待値と不一致: actual=${actual}, expected=${EXPECTED_CONTAINERS}"
    err "peer5 + orderer1 + CA6 = 12 を期待"
    exit 1
  fi
  ok "稼働コンテナ数: ${actual}/${EXPECTED_CONTAINERS}"

  # Org5 視点 channel 疎通確認 (最後に合流した Org が channel を見えているか)
  log "==== Org5 視点 channel 疎通確認 ===="
  local peer_bin="${SAMPLES_DIR}/bin/peer"
  local org5_tls="${TEST_NET_DIR}/organizations/peerOrganizations/org5.example.com/peers/peer0.org5.example.com/tls/ca.crt"
  local org5_msp="${TEST_NET_DIR}/organizations/peerOrganizations/org5.example.com/users/Admin@org5.example.com/msp"
  if [[ ! -x "${peer_bin}" ]]; then
    warn "peer binary 見つからず: ${peer_bin} → skip"
  elif [[ ! -f "${org5_tls}" ]]; then
    warn "Org5 TLS cert 見つからず: ${org5_tls} → skip"
  elif [[ ! -d "${org5_msp}" ]]; then
    warn "Org5 Admin MSP 見つからず: ${org5_msp} → skip"
  else
    local info
    if info=$(FABRIC_CFG_PATH="${SAMPLES_DIR}/config" \
              CORE_PEER_TLS_ENABLED=true \
              CORE_PEER_LOCALMSPID=Org5MSP \
              CORE_PEER_TLS_ROOTCERT_FILE="${org5_tls}" \
              CORE_PEER_MSPCONFIGPATH="${org5_msp}" \
              CORE_PEER_ADDRESS=localhost:15051 \
              "${peer_bin}" channel getinfo -c "${CHANNEL_NAME}" 2>&1); then
      ok "Org5 から ${CHANNEL_NAME} 参照成功"
      echo "${info}" | sed 's/^/    /'
    else
      warn "Org5 視点 peer channel getinfo 失敗:"
      echo "${info}" | sed 's/^/    /' >&2
    fi
  fi
}

main() {
  log "repo root: ${REPO_ROOT}"
  log "channel:   ${CHANNEL_NAME}"
  preflight
  apply_patches
  up_two_org
  up_org_n 3
  up_org_n 4
  up_org_n 5
  verify
  echo
  ok "Phase 8 network up 完了 (5Org)"
  echo "${C_DIM}次: ./scripts/deploy_chaincode.sh で chaincode を deploy${C_OFF}"
  echo "${C_DIM}クリーンアップ: ./scripts/reset.sh --yes${C_OFF}"
}
main "$@"
