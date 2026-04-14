#!/usr/bin/env bash
# reset.sh — Phase 2 ネットワーク完全リセット
# test-network の network.sh down に加え、chaincode コンテナ・image・volume 残留も削除

set -euo pipefail

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
log()  { echo "${C_DIM}[reset]${C_OFF} $*"; }
ok()   { echo "${C_OK}[ ok ]${C_OFF} $*"; }
warn() { echo "${C_WARN}[warn]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[err ]${C_OFF} $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Fabric ネットワーク完全リセット:
  1. test-network の network.sh down
  2. chaincode コンテナ (dev-peer*) 削除
  3. chaincode image (dev-peer*) 削除
  4. Fabric docker volume / network の残留削除
  5. 生成物 (organizations/ / channel-artifacts/) は network.sh down 側で削除

Options:
  --yes         確認プロンプトを省略
  -h, --help    ヘルプ
EOF
}

ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
done

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  warn "Fabric ネットワークを完全に削除します（実行中コンテナ・chaincode image・volume）"
  read -r -p "続行しますか? [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

down_test_network() {
  log "==== network.sh down ===="
  if [[ -x "${TEST_NET_DIR}/network.sh" ]]; then
    (cd "${TEST_NET_DIR}" && ./network.sh down || true)
    ok "test-network down 実行"
  else
    warn "test-network が見つからない（skip）"
  fi
}

remove_chaincode_containers() {
  log "==== chaincode コンテナ削除 ===="
  local ids
  ids="$(docker ps -aq -f name=dev-peer 2>/dev/null || true)"
  if [[ -n "${ids}" ]]; then
    # shellcheck disable=SC2086
    docker rm -f ${ids} >/dev/null
    ok "削除: $(echo "${ids}" | wc -l) container"
  else
    ok "dev-peer コンテナなし"
  fi
}

remove_chaincode_images() {
  log "==== chaincode image 削除 ===="
  local imgs
  imgs="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E '^dev-peer' || true)"
  if [[ -n "${imgs}" ]]; then
    # shellcheck disable=SC2086
    docker rmi -f ${imgs} >/dev/null 2>&1 || true
    ok "削除: $(echo "${imgs}" | wc -l) image"
  else
    ok "dev-peer image なし"
  fi
}

remove_leftover_volumes() {
  log "==== Fabric 残留 volume 削除 ===="
  local vols
  vols="$(docker volume ls --format '{{.Name}}' 2>/dev/null \
            | grep -E '(orderer|peer|fabric_test|docker_)' || true)"
  if [[ -n "${vols}" ]]; then
    # shellcheck disable=SC2086
    docker volume rm ${vols} >/dev/null 2>&1 || true
    ok "volume 削除試行: $(echo "${vols}" | wc -l)"
  else
    ok "残留 volume なし"
  fi
}

remove_leftover_networks() {
  log "==== Fabric 残留 network 削除 ===="
  local nets
  nets="$(docker network ls --format '{{.Name}}' 2>/dev/null \
            | grep -E '(fabric_test|docker_test)' || true)"
  if [[ -n "${nets}" ]]; then
    # shellcheck disable=SC2086
    docker network rm ${nets} >/dev/null 2>&1 || true
    ok "network 削除試行: $(echo "${nets}" | wc -l)"
  else
    ok "残留 network なし"
  fi
}

verify_clean() {
  log "==== 残留確認 ===="
  local remaining
  remaining="$(docker ps --format '{{.Names}}' | grep -E '(peer|orderer|ca_|dev-peer)' || true)"
  if [[ -n "${remaining}" ]]; then
    err "コンテナが残っている:"
    echo "${remaining}" | sed 's/^/    /' >&2
    return 1
  fi
  ok "Fabric コンテナ完全クリーン"
}

main() {
  log "repo root: ${REPO_ROOT}"
  confirm || { warn "キャンセル"; exit 0; }
  down_test_network
  remove_chaincode_containers
  remove_chaincode_images
  remove_leftover_volumes
  remove_leftover_networks
  verify_clean
  echo
  ok "Phase 2 reset 完了"
  echo "${C_DIM}次: ./scripts/network_up.sh で再起動${C_OFF}"
}
main "$@"
