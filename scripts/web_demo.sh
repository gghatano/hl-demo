#!/usr/bin/env bash
# web_demo.sh — Web デモ UI 起動スクリプト
#
# Usage:
#   ./scripts/web_demo.sh            # Web サーバー起動 (NW + deploy 済み前提)
#   ./scripts/web_demo.sh --fresh    # reset → network_up → deploy → seed → web
#                                    # クリーン状態から一発で完成形のデモが立ち上がる
#   ./scripts/web_demo.sh --seed     # 既存 NW にサンプル素材だけ追加投入 → web
#   ./scripts/web_demo.sh --stop     # バックグラウンド起動時の停止
#
# 前提 (--fresh 以外):
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

FRESH=0
SEED=0
for arg in "$@"; do
  case "${arg}" in
    --fresh) FRESH=1 ;;
    --seed)  SEED=1  ;;
    --stop)
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
      ;;
    -h|--help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *) err "unknown option: ${arg}"; exit 2 ;;
  esac
done

# --- --fresh: NW 再構築から一気通貫 ---
if (( FRESH )); then
  log "==== --fresh: reset → network_up → deploy → seed → web ===="
  "${SCRIPT_DIR}/reset.sh" --yes
  "${SCRIPT_DIR}/network_up.sh"
  "${SCRIPT_DIR}/deploy_chaincode.sh"
  "${SCRIPT_DIR}/demo_seed.sh"
  ok "--fresh: クリーン状態から台帳準備まで完了"
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

# --- --seed: 既存 NW にサンプル素材を冪等投入 ---
# --fresh の場合は上で投入済みなのでスキップ
if (( SEED && !FRESH )); then
  log "==== --seed: demo_seed.sh 実行 ===="
  "${SCRIPT_DIR}/demo_seed.sh"
fi

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
