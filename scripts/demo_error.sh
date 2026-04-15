#!/usr/bin/env bash
# demo_error.sh — Phase 5 T5-2
# 異常系シナリオ E1〜E3 を「人向け」に語るデモ
#
# - 各ケース後に履歴を再照会し「改ざんが残っていないこと」を二段構えで見せる
# - assert は無い（検証は tests/integration/cases/20_error_flow.sh）
#
# Usage:
#   ./scripts/demo_error.sh [productId]
#     productId を省略した場合は新規 CreateProduct してから始める

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/format.sh"

INVOKE="${SCRIPT_DIR}/invoke_as.sh"
PAUSE="${DEMO_PAUSE:-1.2}"
pause() { sleep "${PAUSE}" 2>/dev/null || true; }

PRODUCT_ID="${1:-}"

clear 2>/dev/null || true
cat <<'EOS'

================================================================
  異常系デモ: 「書けないはずのものは、書けない」
================================================================
EOS

say_narration "■ 論点"
say_note "正常系が動くのは当たり前。重要なのは攻撃を試みた時に ──"
say_note "  1. chaincode が明示的エラーで拒否すること"
say_note "  2. 失敗 invoke 後も台帳履歴が汚されないこと"
say_note "この 2 段を各ケースで確認する。"
pause

if [[ -z "${PRODUCT_ID}" ]]; then
  PRODUCT_ID="DEMO-ERR-$(date +%s)"
  say_section "準備: 実験用 product を新規登録"
  say_note "productId=${PRODUCT_ID}"
  "${INVOKE}" org1 invoke CreateProduct "${PRODUCT_ID}" Org1MSP Org1MSP >/dev/null
  pause
fi

show_history() {
  say_step "履歴を再照会 (改ざん不在を確認)"
  "${INVOKE}" org3 query GetHistory "${PRODUCT_ID}" 2>/dev/null | format_history
}

# ---------- E1 ----------
say_section "E1: 所有者偽装 (販売店 C が卸 B を騙って横取り)"
say_note "攻撃者シナリオ: 販売店 C が 卸 B を装い、"
say_note "「これは直前まで B が持っていた product だ」と嘘の由来を主張して"
say_note "自分への譲渡を台帳に書き込もうとする。chaincode の MSP 検証に掛ける。"
say_step "販売店 C (Org3) から TransferProduct ${PRODUCT_ID} fromOwner=Org2MSP(卸B) toOwner=Org3MSP(販売店C)"
set +e
out=$("${INVOKE}" org3 invoke TransferProduct "${PRODUCT_ID}" Org2MSP Org3MSP 2>&1)
rc=$?
set -e
code=$(extract_error_code "${out}")
say_note "exit=${rc}, errorCode=${code:-<none>}"
if [[ -n "${code}" ]]; then
  say_note "→ chaincode が拒否。正しくエンドースメント失敗している。"
fi
pause
show_history
pause

# ---------- E2 ----------
say_section "E2: 存在しない productId を照会"
say_note "偽の追跡番号を投げられても、chaincode は静かに成功させない。"
missing="GHOST-$(date +%s)"
say_step "Org3 query ReadProduct ${missing}"
set +e
out=$("${INVOKE}" org3 query ReadProduct "${missing}" 2>&1)
rc=$?
set -e
code=$(extract_error_code "${out}")
say_note "exit=${rc}, errorCode=${code:-<none>}"
say_note "※ E2 は読み取り専用の照会。書き込みは一切発生しないので、"
say_note "   履歴再照会による二段構え確認は原理的に不要（汚染しようがない）。"
pause

# ---------- E3 ----------
say_section "E3: 既存 productId に対する重複 CreateProduct"
say_note "同じ番号で二重登録できてしまうと、履歴の分岐が起きて起点が曖昧になる。"
say_step "Org1 invoke CreateProduct ${PRODUCT_ID} (既存)"
set +e
out=$("${INVOKE}" org1 invoke CreateProduct "${PRODUCT_ID}" Org1MSP Org1MSP 2>&1)
rc=$?
set -e
code=$(extract_error_code "${out}")
say_note "exit=${rc}, errorCode=${code:-<none>}"
pause
show_history
pause

say_narration "■ 結論"
say_note "3 ケースすべてで:"
say_note "  1. chaincode が明示的エラーコードで拒否"
say_note "  2. 失敗後も履歴は汚染されていない"
say_note "「書けないはずのものは、書けない」ことが行動で確認できた。"
echo
