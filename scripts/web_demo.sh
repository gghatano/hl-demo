#!/usr/bin/env bash
# web_demo.sh — Web デモ UI 起動スクリプト
#
# Usage:
#   ./scripts/web_demo.sh          # Web サーバー起動
#   ./scripts/web_demo.sh --stop   # 停止（バックグラウンド実行時）
#
# 前提:
#   - Fabric ネットワーク起動済み (./scripts/network_up.sh)
#   - Chaincode デプロイ済み (./scripts/deploy_chaincode.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# fabric-samples が別ディレクトリにある場合は FABRIC_REPO_ROOT で上書き可能
FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT:-${REPO_ROOT}}"
export FABRIC_REPO_ROOT
WEB_DIR="${REPO_ROOT}/web"

if [[ -t 1 ]]; then
  C_HDR=$'\033[1;36m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_OFF=$'\033[0m'
else
  C_HDR=""; C_OK=""; C_ERR=""; C_OFF=""
fi
log()  { echo "${C_HDR}[web-demo]${C_OFF} $*"; }
ok()   { echo "${C_OK}[web-demo]${C_OFF} $*"; }
err()  { echo "${C_ERR}[web-demo]${C_OFF} $*" >&2; }

# --stop: kill running server
if [[ "${1:-}" == "--stop" ]]; then
  if [[ -f "${WEB_DIR}/.pid" ]]; then
    PID=$(cat "${WEB_DIR}/.pid")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID"
      ok "Server stopped (PID=$PID)"
    else
      log "Server not running (stale PID=$PID)"
    fi
    rm -f "${WEB_DIR}/.pid"
  else
    log "No .pid file found"
  fi
  exit 0
fi

# --- Preflight checks ---

log "Preflight: Fabric ネットワーク確認..."
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^peer0.org1.example.com$'; then
  err "Fabric ネットワーク未起動。先に実行:"
  err "  ./scripts/network_up.sh"
  exit 1
fi
ok "Fabric ネットワーク起動中"

log "Preflight: Chaincode デプロイ確認..."
PEER_BIN="${FABRIC_REPO_ROOT}/fabric/fabric-samples/bin/peer"
export FABRIC_CFG_PATH="${FABRIC_REPO_ROOT}/fabric/fabric-samples/config"
TEST_NET_DIR="${FABRIC_REPO_ROOT}/fabric/fabric-samples/test-network"
ORG1_DIR="${TEST_NET_DIR}/organizations/peerOrganizations/org1.example.com"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${ORG1_DIR}/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${ORG1_DIR}/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

CC_NAME="${CC_NAME:-product-trace}"
CHANNEL_NAME="${CHANNEL_NAME:-supplychannel}"

if ! "${PEER_BIN}" lifecycle chaincode querycommitted -C "${CHANNEL_NAME}" -n "${CC_NAME}" >/dev/null 2>&1; then
  err "Chaincode '${CC_NAME}' 未デプロイ。先に実行:"
  err "  ./scripts/deploy_chaincode.sh"
  exit 1
fi
ok "Chaincode '${CC_NAME}' デプロイ済み"

# --- npm install ---

log "npm install..."
cd "${WEB_DIR}"
if [[ ! -d node_modules ]]; then
  npm install --no-fund --no-audit 2>&1 | tail -1
else
  log "node_modules 存在 → スキップ (再インストールは rm -rf web/node_modules 後に再実行)"
fi

# --- Start server ---

log "Web サーバーを起動します..."
echo ""
ok "=========================================="
ok "  http://localhost:${PORT:-3000}"
ok "=========================================="
echo ""
log "Ctrl+C で停止"

exec node server.js
