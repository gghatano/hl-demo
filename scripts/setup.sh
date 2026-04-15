#!/usr/bin/env bash
# setup.sh — Phase 1 環境準備
# - 前提ソフトのバージョン確認
# - fabric-samples tag 固定 clone
# - Fabric binaries / Docker images 取得
# - 冪等性: 既存ありはスキップ。--force で再導入

set -euo pipefail

# ===== バージョン固定 =====
# NOTE: Fabric 2.5.15 / CA 1.5.18 は Docker 29+ 互換修正 (fabric PR #5355,
#       go-dockerclient → moby/client 置換) を含む最初の 2.5 系 patch。
#       これ未満だと node chaincode install が "broken pipe" で壊れる。
#       詳細: docs/fabric-pitfalls.md §「Fabric 2.5.10 以前 × Docker 29+」
#       pin 更新時は上流 release notes を必ず確認してから上げること。
FABRIC_VERSION="2.5.15"
CA_VERSION="1.5.18"
# fabric-samples は v2.4.9 以降 tag 廃止 → main の commit を固定
# 更新時は `git ls-remote https://github.com/hyperledger/fabric-samples.git refs/heads/main` で取得
FABRIC_SAMPLES_COMMIT="bf7e75c6c159dc1959f3bb8979ed739171673b4d"

# ===== パス =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FABRIC_DIR="${REPO_ROOT}/fabric"
SAMPLES_DIR="${FABRIC_DIR}/fabric-samples"

# ===== 色 =====
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi
log()  { echo "${C_DIM}[setup]${C_OFF} $*"; }
ok()   { echo "${C_OK}[ ok ]${C_OFF} $*"; }
warn() { echo "${C_WARN}[warn]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[err ]${C_OFF} $*" >&2; }

# ===== 引数 =====
FORCE=0
SKIP_IMAGES=0
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --force         既存 fabric-samples / bin を削除して再取得
  --skip-images   Docker image 取得をスキップ（CI 等で事前 pull 済みの場合）
  -h, --help      ヘルプ

Env:
  FABRIC_VERSION=${FABRIC_VERSION}
  CA_VERSION=${CA_VERSION}
  FABRIC_SAMPLES_COMMIT=${FABRIC_SAMPLES_COMMIT}
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --skip-images) SKIP_IMAGES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
done

# ===== 前提チェック =====
check_cmd() {
  local cmd="$1" min="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "必須コマンドが見つからない: $cmd"
    return 1
  fi
  ok "$cmd: $(command -v "$cmd")${min:+ (推奨 $min)}"
}

check_docker() {
  if ! docker info >/dev/null 2>&1; then
    err "docker daemon に接続できない。Docker Desktop / systemd を起動してください"
    return 1
  fi
  ok "docker daemon 応答 OK"
}

check_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    err "docker compose v2 が使えない（旧 docker-compose は非対応）"
    return 1
  fi
  ok "docker compose: $(docker compose version --short)"
}

check_node() {
  if ! command -v node >/dev/null 2>&1; then
    err "node が無い（18.x LTS 推奨）"
    return 1
  fi
  local v
  v="$(node --version)"
  ok "node: $v"
  if [[ ! "$v" =~ ^v(18|20)\. ]]; then
    warn "node $v は未検証。v18 LTS 推奨"
  fi
}

check_port() {
  local port="$1"
  if ! command -v ss >/dev/null 2>&1; then
    return 0
  fi
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
    warn "ポート ${port} 使用中。Phase 2 で衝突する可能性"
  fi
}

preflight() {
  log "==== 前提チェック ===="
  check_cmd curl
  check_cmd git
  check_cmd jq
  check_cmd bash
  check_cmd docker
  check_docker
  check_compose
  check_node
  check_cmd npm

  if ! command -v ss >/dev/null 2>&1; then
    warn "ss 未インストール（iproute2 パッケージ）: ポート衝突チェックをスキップ"
  fi

  log "ポート使用状況（使用中なら警告のみ）"
  for p in 7050 7051 9051 11051 7054 8054 9054; do
    check_port "$p"
  done

  log "ディスク空き"
  df -h "${REPO_ROOT}" | tail -1
}

# ===== fabric-samples clone（commit 固定） =====
clone_samples() {
  log "==== fabric-samples @ ${FABRIC_SAMPLES_COMMIT:0:12} ===="
  mkdir -p "${FABRIC_DIR}"

  if [[ -d "${SAMPLES_DIR}/.git" ]]; then
    if [[ $FORCE -eq 1 ]]; then
      log "既存 fabric-samples を削除（--force）"
      rm -rf "${SAMPLES_DIR}"
    else
      local cur
      cur="$(git -C "${SAMPLES_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
      if [[ "$cur" == "${FABRIC_SAMPLES_COMMIT}" ]]; then
        ok "fabric-samples 既存・commit 一致: ${cur:0:12} → skip"
        return
      else
        err "fabric-samples commit 不一致: ${cur:0:12} != ${FABRIC_SAMPLES_COMMIT:0:12}"
        err "バージョン混在を防ぐため停止。--force で再取得してください"
        exit 1
      fi
    fi
  fi

  log "clone 中（filter=blob:none で遅延取得）..."
  git -c advice.detachedHead=false clone \
    --filter=blob:none --no-checkout \
    https://github.com/hyperledger/fabric-samples.git "${SAMPLES_DIR}"
  git -C "${SAMPLES_DIR}" -c advice.detachedHead=false checkout "${FABRIC_SAMPLES_COMMIT}"
  ok "fabric-samples clone 完了 ($(git -C "${SAMPLES_DIR}" rev-parse --short HEAD))"
}

# ===== install-fabric.sh 取得 =====
# 現在は hyperledger/fabric リポジトリ配下（fabric-samples から移動済）
fetch_installer() {
  local url="https://raw.githubusercontent.com/hyperledger/fabric/v${FABRIC_VERSION}/scripts/install-fabric.sh"
  local dest="${FABRIC_DIR}/install-fabric.sh"
  if [[ -x "${dest}" && $FORCE -eq 0 ]]; then
    ok "install-fabric.sh 既存 → skip"
  else
    log "install-fabric.sh 取得: ${url}"
    curl -sSLf "${url}" -o "${dest}"
    chmod +x "${dest}"
    ok "install-fabric.sh 取得完了"
  fi
  INSTALLER="${dest}"
}

# ===== Fabric binaries / images =====
install_fabric() {
  log "==== Fabric binaries / images ===="
  fetch_installer

  local bin_dir="${SAMPLES_DIR}/bin"
  if [[ -d "${bin_dir}" && $FORCE -eq 0 ]]; then
    ok "fabric-samples/bin 既存 → skip（--force で再取得）"
  else
    [[ $FORCE -eq 1 ]] && rm -rf "${bin_dir}" "${SAMPLES_DIR}/config"
    # install-fabric.sh は CWD 配下に bin/ config/ を展開する
    (cd "${SAMPLES_DIR}" && "${INSTALLER}" \
      --fabric-version "${FABRIC_VERSION}" \
      --ca-version "${CA_VERSION}" \
      binary)
    ok "Fabric binaries 取得完了"
  fi

  if [[ $SKIP_IMAGES -eq 1 ]]; then
    warn "--skip-images 指定: Docker image 取得スキップ"
    return
  fi
  (cd "${SAMPLES_DIR}" && "${INSTALLER}" \
    --fabric-version "${FABRIC_VERSION}" \
    --ca-version "${CA_VERSION}" \
    docker)
  ok "Docker image 取得完了"
}

# ===== main =====
record_images() {
  log "==== 取得済み Fabric image ===="
  if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
       | grep -E '^hyperledger/fabric' | sort; then
    :
  else
    warn "hyperledger/fabric* image が見当たらない"
  fi
}

main() {
  log "repo root: ${REPO_ROOT}"
  preflight
  clone_samples
  install_fabric
  record_images
  echo
  ok "Phase 1 setup 完了"
  echo "${C_DIM}次: Phase 2 ネットワーク構築（scripts/network_up.sh 未実装）${C_OFF}"
}
main "$@"
