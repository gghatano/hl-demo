#!/usr/bin/env bash
# gen_addorg.sh — addOrg3 を雛形に addOrg<N> patch 一式を機械生成する
#
# Fabric sample の test-network は addOrg3 までしか同梱していないため、
# hl-proto の 5Org 化に必要な addOrg4 / addOrg5 をこのスクリプトで作る。
#
# 生成方針:
#   - addOrg3/ のファイルを addOrg<N>/ にコピー (fabric-ca/ 等の生成物は除外)
#   - ファイル内の識別子 (org3, Org3, ORG3, Org3MSP) を <n>/<N>/<NMSP> に sed 置換
#   - ポート 11051/11052/11054 を引数指定の 3 連 (例: 13051/13052/13054) に置換
#   - scripts/org3-scripts/ を scripts/org<n>-scripts/ にコピー + 置換
#
# 使用例:
#   ./gen_addorg.sh 4 13051 13054 > /tmp/gen4.log 2>&1
#   ./gen_addorg.sh 5 15051 15054
#
# 出力先: このスクリプトと同階層の patches/addOrg<n>/ + patches/scripts/org<n>-scripts/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <orgNumber> <peerPort> <caPort>

  orgNumber : 4 / 5 (3 は既存 addOrg3 をそのまま使う)
  peerPort  : peer0 が listen するポート (例: 13051)
              chaincode 通信用は peerPort+1 (例: 13052)
  caPort    : fabric-ca が listen するポート (例: 13054)

出力:
  ${SCRIPT_DIR}/patches/addOrg<n>/
  ${SCRIPT_DIR}/patches/scripts/org<n>-scripts/
EOF
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

N="$1"
PEER_PORT="$2"
CA_PORT="$3"
CC_PORT=$((PEER_PORT + 1))

if [[ ! "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 4 ]]; then
  echo "error: orgNumber must be >= 4" >&2
  exit 2
fi

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/fabric/fabric-samples/test-network/addOrg3"
SRC_SCRIPTS_DIR="${REPO_ROOT}/fabric/fabric-samples/test-network/scripts/org3-scripts"
DST_PATCH_DIR="${SCRIPT_DIR}/patches/addOrg${N}"
DST_SCRIPTS_DIR="${SCRIPT_DIR}/patches/scripts/org${N}-scripts"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "error: addOrg3 テンプレートが見つからない: ${SRC_DIR}" >&2
  echo "先に ./scripts/setup.sh で fabric-samples を clone してください" >&2
  exit 1
fi

rm -rf "${DST_PATCH_DIR}" "${DST_SCRIPTS_DIR}"
mkdir -p "${DST_PATCH_DIR}" "${DST_SCRIPTS_DIR}"

# ---- ファイルコピー (fabric-ca/ 下の生成物 + log.txt は除外) ----
# rsync がない環境向けに cp ベース
pushd "${SRC_DIR}" > /dev/null
find . -type f \
  -not -path './fabric-ca/org3/fabric-ca-server.db' \
  -not -path './fabric-ca/org3/msp/*' \
  -not -path './fabric-ca/org3/Issuer*' \
  -not -path './fabric-ca/org3/tls-cert.pem' \
  -not -path './fabric-ca/org3/ca-cert.pem' \
  -not -path './fabric-ca/org3/fabric-ca-server-config.yaml' \
  -not -name 'log.txt' \
  | while read -r f; do
    dst="${DST_PATCH_DIR}/${f#./}"
    # ファイル名内の org3 → org<n>
    dst="${dst//org3/org${N}}"
    dst="${dst//addOrg3/addOrg${N}}"
    mkdir -p "$(dirname "${dst}")"
    cp "${f}" "${dst}"
  done
popd > /dev/null

# ---- org<n>-scripts コピー ----
for sf in updateChannelConfig.sh joinChannel.sh; do
  cp "${SRC_SCRIPTS_DIR}/${sf}" "${DST_SCRIPTS_DIR}/${sf}"
done

# ---- sed 置換 (テキストファイルのみ) ----
# 順序重要: Org3MSP を先に置換しておかないと Org3 マッチで壊れる。
# yaml/sh/json/conf 系のみ対象、バイナリはスキップ。
replace_in_file() {
  local f="$1"
  # bash/sh/yaml/yml/json/conf/md/txt/pem など
  case "${f}" in
    *.db|*.der|*.pem|*.crt|*.key|*.pb|*IssuerPublicKey|*IssuerSecretKey|*IssuerRevocation*|*_sk) return 0 ;;
  esac
  # MSP → org 番号 → 港番号 の順で処理
  sed -i \
    -e "s/Org3MSP/Org${N}MSP/g" \
    -e "s/Org3/Org${N}/g" \
    -e "s/ORG3/ORG${N}/g" \
    -e "s/org3/org${N}/g" \
    -e "s/addOrg3/addOrg${N}/g" \
    -e "s/11051/${PEER_PORT}/g" \
    -e "s/11052/${CC_PORT}/g" \
    -e "s/11054/${CA_PORT}/g" \
    "${f}"
}

find "${DST_PATCH_DIR}" "${DST_SCRIPTS_DIR}" -type f | while read -r f; do
  replace_in_file "${f}"
done

# ---- updateChannelConfig.sh の署名 org を 1→2→... のサイクルから固定 ----
# 元は setGlobals 2 (= Org2 が共同署名)。addOrg4/5 でも Org2 が署名しても問題ないので据え置き。
# ただし sed で Org2 → Org${N} に化けないよう注意 (Org3 → Org4 のみ置換される設計なので OK)。

echo "生成完了:"
echo "  patch dir   : ${DST_PATCH_DIR}"
echo "  scripts dir : ${DST_SCRIPTS_DIR}"
echo "  peer port   : ${PEER_PORT}"
echo "  cc port     : ${CC_PORT}"
echo "  ca port     : ${CA_PORT}"
echo ""
echo "次のステップ: scripts/network_up.sh が patch をコピー＋起動する"
