#!/usr/bin/env bash
# 20_error_flow.sh — E1〜E3 異常系
# 共通 env: INVOKE / PRODUCT_N_ID / PRODUCT_E1_ID

# shellcheck shell=bash

tc_begin "E1 OWNER_MISMATCH (Org3 が偽の fromOwner で transfer)"
# N フロー終盤 currentOwner=Org3MSP。ここで fromOwner=Org1MSP と偽って transfer を試みる。
# chaincode 側は currentOwner と fromOwner の不一致 → OWNER_MISMATCH
out=$("${INVOKE}" org3 invoke TransferProduct "${PRODUCT_N_ID}" Org1MSP Org3MSP 2>&1 || true)
assert_error_code "${out}" "OWNER_MISMATCH" "expected [OWNER_MISMATCH]" && \
  tc_pass "rejected with OWNER_MISMATCH"

tc_begin "E1 履歴改ざん不在 (失敗 invoke 後も history は 3 のまま)"
if hist_json=$("${INVOKE}" org3 query GetHistory "${PRODUCT_N_ID}" 2>/dev/null); then
  len=$(printf '%s' "${hist_json}" | jq 'length')
  assert_eq "${len}" "3" "history length unchanged after failed invoke" && \
    tc_pass "ledger intact"
else
  tc_fail "query failed"
fi

tc_begin "E2 PRODUCT_NOT_FOUND (存在しない id の query)"
nonexistent="NOPE-$(date +%s)-$$"
out=$("${INVOKE}" org3 query ReadProduct "${nonexistent}" 2>&1 || true)
assert_error_code "${out}" "PRODUCT_NOT_FOUND" "expected [PRODUCT_NOT_FOUND]" && \
  tc_pass "rejected with PRODUCT_NOT_FOUND"

tc_begin "E3 PRODUCT_ALREADY_EXISTS (既存 id を再度 CreateProduct)"
out=$("${INVOKE}" org1 invoke CreateProduct "${PRODUCT_N_ID}" Org1MSP Org1MSP 2>&1 || true)
assert_error_code "${out}" "PRODUCT_ALREADY_EXISTS" "expected [PRODUCT_ALREADY_EXISTS]" && \
  tc_pass "rejected with PRODUCT_ALREADY_EXISTS"
