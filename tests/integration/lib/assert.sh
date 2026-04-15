#!/usr/bin/env bash
# assert.sh — Phase 5 T5-5
# L2 integration test の assert / 集計ヘルパ

# shellcheck shell=bash

if [[ -n "${_HL_ASSERT_SH_LOADED:-}" ]]; then return 0; fi
_HL_ASSERT_SH_LOADED=1

: "${TC_PASS:=0}"
: "${TC_FAIL:=0}"
: "${TC_CURRENT:=}"
FAILED_CASES=()

if [[ -t 1 ]]; then
  A_OK=$'\033[32m'; A_NG=$'\033[31m'; A_DIM=$'\033[2m'; A_OFF=$'\033[0m'
else
  A_OK=""; A_NG=""; A_DIM=""; A_OFF=""
fi

tc_begin() {
  TC_CURRENT="$1"
  echo "${A_DIM}--- [case] ${TC_CURRENT} ---${A_OFF}"
}

tc_pass() {
  TC_PASS=$((TC_PASS + 1))
  echo "${A_OK}[PASS]${A_OFF} ${TC_CURRENT}${1:+ — $1}"
}

tc_fail() {
  TC_FAIL=$((TC_FAIL + 1))
  FAILED_CASES+=("${TC_CURRENT}: $*")
  echo "${A_NG}[FAIL]${A_OFF} ${TC_CURRENT} — $*" >&2
}

# assert_eq <actual> <expected> <message>
assert_eq() {
  local actual="$1" expected="$2" msg="${3:-}"
  if [[ "${actual}" == "${expected}" ]]; then
    return 0
  fi
  tc_fail "${msg} (expected='${expected}', actual='${actual}')"
  return 1
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    return 0
  fi
  tc_fail "${msg} (needle='${needle}' not in output)"
  return 1
}

# assert_error_code <stderr_text> <CODE> <message>
assert_error_code() {
  local text="$1" want="$2" msg="${3:-}"
  if printf '%s' "${text}" | grep -qE "\[${want}\]"; then
    return 0
  fi
  tc_fail "${msg} (want=[${want}] not found in error output)"
  return 1
}

# 集計サマリを出力 + exit code 決定
tc_summary() {
  local total=$((TC_PASS + TC_FAIL))
  echo
  echo "================ L2 integration summary ================"
  echo "  total : ${total}"
  echo "  pass  : ${TC_PASS}"
  echo "  fail  : ${TC_FAIL}"
  if ((TC_FAIL > 0)); then
    echo "  failed cases:"
    for c in "${FAILED_CASES[@]}"; do
      echo "    - $c"
    done
    return 1
  fi
  return 0
}
