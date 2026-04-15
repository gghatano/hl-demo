#!/usr/bin/env bash
# format.sh — Phase 5 T5-3
# 出力整形ライブラリ: MSP ID → 業務語彙 / GetHistory → 表形式 / エラーコード抽出
#
# 使い方: source "${SCRIPT_DIR}/lib/format.sh"

# shellcheck shell=bash

if [[ -z "${_HL_FORMAT_SH_LOADED:-}" ]]; then
_HL_FORMAT_SH_LOADED=1

# 色（端末のみ）
if [[ -t 1 ]]; then
  FMT_BOLD=$'\033[1m'; FMT_DIM=$'\033[2m'
  FMT_GREEN=$'\033[32m'; FMT_YELLOW=$'\033[33m'
  FMT_CYAN=$'\033[36m'; FMT_MAGENTA=$'\033[35m'
  FMT_OFF=$'\033[0m'
else
  FMT_BOLD=""; FMT_DIM=""; FMT_GREEN=""; FMT_YELLOW=""
  FMT_CYAN=""; FMT_MAGENTA=""; FMT_OFF=""
fi

# MSP ID → 業務語彙
# 対応: Org1MSP=メーカー A / Org2MSP=卸 B / Org3MSP=販売店 C
msp_to_role() {
  case "${1:-}" in
    Org1MSP) printf 'メーカー A' ;;
    Org2MSP) printf '卸 B'       ;;
    Org3MSP) printf '販売店 C'    ;;
    '')      printf '-'           ;;
    *)       printf '%s' "$1"     ;;
  esac
}

# GetHistory 応答（JSON 配列）を表形式で整形
# stdin から JSON を受け取り、番号付き行を出力する
#   #1 [2026-04-15T10:00:00.000Z] CREATE   -          → メーカー A   (by メーカー A)
#   #2 [2026-04-15T10:01:00.000Z] TRANSFER メーカー A → 卸 B         (by メーカー A)
format_history() {
  local json
  json="$(cat)"
  if [[ -z "${json}" ]]; then
    echo "(履歴なし)"
    return 0
  fi
  # jq で events を TSV 化 → 業務語彙にマップして整形
  local tsv
  tsv="$(
    printf '%s' "${json}" | jq -r '
      . as $arr
      | if (type != "array") then empty
        elif (length == 0) then empty
        else
          to_entries[] | [
            (.key + 1 | tostring),
            (.value.timestamp // "-"),
            (.value.eventType // "-"),
            (.value.fromOwner // "-"),
            (.value.toOwner   // "-"),
            (.value.actor.mspId // "-"),
            (.value.txId // "-")
          ] | @tsv
        end
    '
  )"
  if [[ -z "${tsv}" ]]; then
    echo "(履歴なし)"
    return 0
  fi

  printf '  %-3s %-26s %-9s %-24s %s\n' '#' 'timestamp' 'event' 'flow' 'actor'
  printf '  %-3s %-26s %-9s %-24s %s\n' '---' '--------------------------' '---------' '------------------------' '------------'
  local idx ts evt from to actor txid
  while IFS=$'\t' read -r idx ts evt from to actor txid; do
    [[ -z "${idx}" ]] && continue
    local from_r to_r actor_r flow
    [[ "${from}"  == "-" ]] && from=""
    [[ "${to}"    == "-" ]] && to=""
    [[ "${actor}" == "-" ]] && actor=""
    from_r="$(msp_to_role "${from}")"
    to_r="$(msp_to_role "${to}")"
    actor_r="$(msp_to_role "${actor}")"
    if [[ "${evt}" == "CREATE" ]]; then
      flow="(新規) → ${to_r}"
    else
      flow="${from_r} → ${to_r}"
    fi
    printf '  #%-2s %-26s %-9s %-24s %s\n' "${idx}" "${ts}" "${evt}" "${flow}" "by ${actor_r}"
  done <<< "${tsv}"
}

# Product 状態（ReadProduct 応答 JSON）を整形
format_product() {
  local json
  json="$(cat)"
  if [[ -z "${json}" ]]; then
    echo "(製品情報なし)"
    return 0
  fi
  local pid manuf owner status created updated
  pid=$(printf '%s' "${json}"     | jq -r '.productId // "-"')
  manuf=$(printf '%s' "${json}"   | jq -r '.manufacturer // "-"')
  owner=$(printf '%s' "${json}"   | jq -r '.currentOwner // "-"')
  status=$(printf '%s' "${json}"  | jq -r '.status // "-"')
  created=$(printf '%s' "${json}" | jq -r '.createdAt // "-"')
  updated=$(printf '%s' "${json}" | jq -r '.updatedAt // "-"')
  local manuf_r owner_r
  manuf_r="$(msp_to_role "${manuf}")"
  owner_r="$(msp_to_role "${owner}")"
  printf '  productId    : %s\n' "${pid}"
  printf '  製造元       : %s (%s)\n' "${manuf_r}" "${manuf}"
  printf '  現在の所有者 : %s (%s)\n' "${owner_r}" "${owner}"
  printf '  status       : %s\n' "${status}"
  printf '  createdAt    : %s\n' "${created}"
  printf '  updatedAt    : %s\n' "${updated}"
}

# chaincode エラー出力から [CODE] を抽出
# 使い方: extract_error_code "$stderr_text"
extract_error_code() {
  local text="${1:-}"
  local code
  code="$(printf '%s' "${text}" | grep -oE '\[[A-Z_]+\]' | head -n1)"
  printf '%s' "${code}"
}

# chaincode エラー出力に特定のエラーコードが含まれるか判定
# 使い方: has_error_code "$stderr_text" OWNER_MISMATCH
has_error_code() {
  local text="${1:-}"
  local want="${2:-}"
  printf '%s' "${text}" | grep -qE "\[${want}\]"
}

# 見出し / 区切り
say_section() {
  printf '\n%s=== %s ===%s\n' "${FMT_BOLD}${FMT_CYAN}" "$*" "${FMT_OFF}"
}
say_step() {
  printf '%s▸%s %s\n' "${FMT_GREEN}" "${FMT_OFF}" "$*"
}
say_note() {
  printf '%s  %s%s\n' "${FMT_DIM}" "$*" "${FMT_OFF}"
}
say_narration() {
  printf '%s%s%s\n' "${FMT_MAGENTA}" "$*" "${FMT_OFF}"
}

fi  # _HL_FORMAT_SH_LOADED
